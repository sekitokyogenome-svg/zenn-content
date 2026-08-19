---
title: "楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法"
emoji: "🔄"
type: "tech"
topics: ["bigquery","ec","googlecloud","sql","dataengineering"]
published: true
---

## はじめに

楽天市場・Amazon・自社ECサイトと複数のチャネルで販売を展開しているEC事業者の方は、月末の売上集計にどれほどの手間をかけているでしょうか。「楽天のRMS管理画面からCSVをダウンロードして、Amazonセラーセントラルからも別のCSVを落として、自社サイトの管理画面からもデータを取り出して、最後にExcelで手作業で合わせる」——こうした作業を毎月繰り返している方は少なくありません。

この方法の問題点は、時間がかかるだけでなく、転記ミスや集計基準のズレが生じやすいことです。たとえば「注文日ベース」と「出荷日ベース」で集計しているデータが混在してしまい、実態と乖離した数字で意思決定をしてしまうリスクがあります。

本記事では、楽天・Amazon・自社ECの売上データをGoogle BigQueryに集約し、一元管理する仕組みの構築方法をご紹介します。難しいプログラミング知識がなくても進められるよう、ステップごとに丁寧に解説していきます。

---

## なぜBigQueryを選ぶのか

BigQueryはGoogleが提供するクラウド型のデータウェアハウスです。データ分析に特化した設計になっており、数百万件のデータを数秒で集計できます。EC事業者がBigQueryを選ぶ理由として、以下の点が挙げられます。

**コストが抑えやすい**  
BigQueryは従量課金制のため、最初から大きな固定費は発生しません。小規模なEC事業者であれば、月々の無料枠（クエリ1TBまで、ストレージ10GBまで）の範囲内に収まるケースも多くあります。

**GA4との連携がスムーズ**  
Google Analytics 4（GA4）とBigQueryは同じGoogle Cloud Platform上にあるため、ウェブサイトのアクセスデータと売上データを紐づけた分析が容易に行えます。「どの広告経由のユーザーが最も購買につながっているか」といった分析が、SQLだけで実現できます。

**Looker Studioでそのまま可視化できる**  
BigQueryに集約したデータは、Google公式の無料BIツール「Looker Studio」と直接接続できます。ダッシュボードを作成すれば、毎朝最新の売上状況を確認するだけの運用に切り替えられます。

---

## 各チャネルのデータをBigQueryに取り込む方法

データを集約するにあたって、まず各プラットフォームからどのようにデータを取得するかを整理する必要があります。

### 楽天市場のデータ取り込み

楽天市場では、RMS（楽天マーチャントサービス）の「注文管理」から受注データをCSV形式でエクスポートできます。このCSVファイルをBigQueryに取り込む方法は大きく2つあります。

1. **Google Cloud Storageを経由する方法**：CSVをGCSのバケットにアップロードし、BigQueryのデータ転送機能でテーブルに読み込む
2. **スプレッドシート連携を使う方法**：CSVをGoogleスプレッドシートに貼り付け、BigQueryのコネクタで同期する

自動化を優先する場合は、楽天の注文APIを利用する方法も検討できます。ただし楽天APIの利用にはRMSの申請が必要で、設定に数週間かかることがあります。まずはCSVによる手動取り込みから始め、運用が安定してから自動化を検討するのが現実的です。

### AmazonセラーセントラルのデータをBigQueryへ

Amazonでは「レポート」メニューから売上レポートをダウンロードできます。Amazonが提供しているSP-API（Selling Partner API）を使えば、プログラムから定期的にデータを取得することも可能です。

よりシンプルな方法として、Amazon Selling Partner APIに対応したSaaSツール（例：Airbyte、Stitch Data）を使うと、コードをほとんど書かずにBigQueryへのデータパイプラインを構築できます。無料プランで試せるものもあるため、まず動かしてみることをお勧めします。

### 自社ECサイトのデータ連携

自社ECがShopifyの場合は、公式のBigQueryコネクタが提供されており、設定画面から接続を有効にするだけでデータ転送が始まります。

EC-CUBEやMagentoなどのオープンソース系ECの場合は、MySQLやPostgreSQLのデータベースから直接BigQueryにデータを転送するパイプラインを構築するケースが多くなります。Google Cloud DataflowやCloud Functionsを組み合わせる方法が一般的です。

---

## BigQuery上でデータを統合するテーブル設計

各チャネルからデータを取り込んだら、分析しやすいように統合ビューを作成します。チャネルごとにカラム名が異なるため、統一したスキーマに合わせてSQLで変換するのがポイントです。

以下は、統合売上テーブルを作成するSQLの例です。楽天・Amazon・自社ECの各テーブルを`UNION ALL`でつなぎ合わせています。

```sql
-- 統合売上ビューの作成
CREATE OR REPLACE VIEW `your_project.ec_dataset.unified_sales` AS

-- 楽天市場の売上データ
SELECT
  '楽天市場'                              AS channel,
  PARSE_DATE('%Y%m%d', order_date_str)   AS order_date,
  order_id,
  item_id                                 AS product_id,
  item_name                               AS product_name,
  unit_price                              AS price,
  quantity,
  unit_price * quantity                   AS revenue,
  shipping_fee,
  status
FROM `your_project.ec_dataset.rakuten_orders`

UNION ALL

-- Amazon の売上データ
SELECT
  'Amazon'                                AS channel,
  DATE(purchase_date)                     AS order_date,
  amazon_order_id                         AS order_id,
  asin                                    AS product_id,
  product_name,
  item_price                              AS price,
  quantity_ordered                        AS quantity,
  item_price * quantity_ordered           AS revenue,
  shipping_price                          AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.amazon_orders`

UNION ALL

-- 自社ECの売上データ
SELECT
  '自社EC'                                AS channel,
  DATE(created_at)                        AS order_date,
  CAST(id AS STRING)                      AS order_id,
  sku                                     AS product_id,
  product_name,
  price,
  quantity,
  price * quantity                        AS revenue,
  shipping_amount                         AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.mysite_orders`;
```

このビューを作成しておくことで、以降の分析はすべて`unified_sales`テーブルに対してクエリを書くだけで済みます。

---

## GA4データと売上を紐づける分析クエリ

BigQueryにGA4のエクスポートデータがある場合、流入元と売上を組み合わせた分析が可能です。どの広告チャネルからの訪問が売上に貢献しているかを把握するクエリ例を示します。

:::message
GA4のBigQueryエクスポートでは、`ga_session_id`は`event_params`配列の中にネストされているため、`UNNEST`を使って展開する必要があります。また流入元の情報は`collected_traffic_source`フィールドを参照します。
:::

```sql
-- 流入元別のセッション数と売上を集計する例
WITH sessions AS (
  SELECT
    -- ga_session_id は event_params 経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    -- 流入元は collected_traffic_source を参照
    collected_traffic_source.manual_medium                     AS medium,
    collected_traffic_source.manual_source                     AS source,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')      AS session_date
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchases AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    event_value_in_usd                                         AS purchase_value
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  s.medium,
  s.source,
  COUNT(DISTINCT s.ga_session_id)  AS sessions,
  COUNT(DISTINCT p.ga_session_id)  AS converting_sessions,
  ROUND(SUM(p.purchase_value), 0)  AS total_revenue_usd
FROM sessions AS s
LEFT JOIN purchases AS p
  ON s.ga_session_id  = p.ga_session_id
 AND s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.medium, s.source
ORDER BY total_revenue_usd DESC;
```

このクエリにより、「メール経由のセッションがどれだけの売上を生み出しているか」「リスティング広告とSNS広告ではどちらの転換率が高いか」といった分析が可能になります。

---

## Looker Studioでダッシュボードを構築する

BigQueryにデータが集まったら、Looker Studioと接続してダッシュボードを作成します。手順は以下のとおりです。

1. Looker Studio（datastudio.google.com）にアクセスし、「レポートを作成」を選択
2. データソースとして「BigQuery」を選び、先ほど作成した`unified_sales`ビューを指定
3. 日付範囲フィルターを設置し、チャネル別の売上推移グラフを追加

ダッシュボードには以下の指標を入れると、日常運用に役立ちます。

- チャネル別売上（棒グラフ）
- 日次売上推移（折れ線グラフ）
- 商品別売上ランキング（表）
- 返品・キャンセル率（スコアカード）

一度作成すれば、毎日自動でデータが更新されるため、朝の確認作業がグッと効率化されます。

---

## まとめ

本記事では、楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法をご紹介しました。要点を整理すると以下のとおりです。

- 各チャネルのデータ取り込みは、まずCSV手動取り込みから始め、慣れたら自動化を検討する
- BigQuery上でチャネルを統合するビューを作成すると、以降の分析が大幅に楽になる
- GA4との連携により、流入元と売上を結びつけた広告効果の分析が可能になる
- Looker Studioでダッシュボード化すれば、日々の確認作業を大幅に省力化できる

**次のアクション**として、まずはGoogleアカウントでBigQueryを有効化し、テスト用のプロジェクトを作成してみましょう。Google Cloud Platformの新規登録時には無料クレジットが付与されており、試験的に動かすコストはほとんどかかりません。小さく始めて、効果を確認しながら段階的に拡張していくアプローチが、運用負担を抑えながら仕組みを整えるうえで有効です。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
