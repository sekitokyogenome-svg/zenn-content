---
title: "EC事業の粗利率をBigQueryで商品×チャネル別に自動計算する仕組み"
emoji: "💹"
type: "tech"
topics: ["bigquery","ec","sql","googleanalytics","lookerstudio"]
published: false
---

## はじめに

「売上は伸びているのに、なぜか手元にお金が残らない」——そのような状況に心当たりはないでしょうか。EC事業において、売上高だけを追いかけていると、商品ごと・チャネルごとの収益性の差が見えにくくなりがちです。広告費をかけて集客したチャネルが実は赤字だった、あるいは利益率の低い商品ばかりが売れていた、といったことは珍しくありません。

粗利率（売上総利益率）は、売上から原価を引いた額が売上に占める割合を示す指標です。商品単位・流入チャネル単位で粗利率を把握できれば、「どこに予算を集中すべきか」「どの商品の価格や仕入れを見直すべきか」という意思決定の精度が大きく向上します。

本記事では、GA4のBigQueryエクスポートデータと社内の売上・原価データを組み合わせて、商品×チャネル別の粗利率を自動で算出する仕組みを紹介します。SQLの基本的な読み方さえ押さえていれば、エンジニアでなくても内容を理解いただけるよう解説しますので、ぜひ最後までご覧ください。

## なぜ「商品×チャネル別」の粗利率が重要なのか

EC事業では、同じ商品でも流入チャネルによって購入単価・返品率・広告コストが異なります。たとえばSNS広告経由の購入者は低単価商品を購入しがちで、かつ広告費が高くつく一方、SEO経由の購入者は指名検索で来ており購入意欲が高く、広告費ゼロでも成約することがあります。

もし「商品A」の全体粗利率が30%だとしても、チャネル別に見たときに「Instagram広告経由は5%」「自然検索経由は45%」といった差がある場合、広告予算の配分を見直すだけで収益構造が大きく改善します。

商品×チャネルの2軸でクロス集計することで、「高粗利×高流入のゴールデンゾーン」と「低粗利×高広告費のレッドゾーン」を可視化でき、改善施策の優先順位付けが容易になります。これは、売上データだけを見ていては気づけない視点です。

## データ構成の設計：GA4エクスポートと売上データの連携

今回の仕組みでは以下の2種類のテーブルを利用します。

| テーブル | 用途 |
|---|---|
| GA4 BigQueryエクスポートテーブル | セッション・流入元・商品閲覧データ |
| 社内売上・原価テーブル | 注文番号・商品SKU・売上・原価 |

GA4のBigQueryエクスポートは、GCPプロジェクトとGA4プロパティを接続することで有効化できます。エクスポート先には `events_YYYYMMDD` 形式のテーブルが日次で生成されます。

社内の売上・原価データは、ECカート（Shopify・ECCUBEなど）からCSVエクスポートしてBigQueryにアップロードするか、Fivetran・Stitch等のETLツールを使って自動連携させるのが一般的です。

連携のキーは「注文ID（order_id）」です。GA4側ではeコマースイベントの `transaction_id` として取得されており、社内売上テーブルの注文番号と突合することで、どのセッション経由の注文かを特定できます。

:::message
GA4のeコマース計測が未設定の場合、`purchase` イベントや `transaction_id` のデータが存在しません。まずGA4のeコマース設定を確認してください。
:::

## BigQueryで流入チャネルと購入を紐づけるSQL

以下のSQLは、GA4の `events_*` テーブルからセッションの流入元と購入（purchase）イベントを取得するクエリです。

```sql
WITH session_source AS (
  SELECT
    -- ga_session_idはevent_params経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_date
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchase_events AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS revenue,
    event_date
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  ss.medium,
  ss.source,
  pe.transaction_id,
  pe.revenue,
  pe.event_date
FROM
  purchase_events AS pe
LEFT JOIN
  session_source AS ss
  ON pe.ga_session_id = ss.ga_session_id
  AND pe.user_pseudo_id = ss.user_pseudo_id
WHERE
  pe.transaction_id IS NOT NULL
```

このクエリで、「どの流入元（source/medium）からの訪問が購入に至ったか」を注文ID単位で取得できます。`your_project` と `analytics_XXXXXXX` の部分は、実際のGCPプロジェクトIDとGA4のプロパティIDに置き換えてください。

:::message
`collected_traffic_source.manual_medium` は UTMパラメータの `utm_medium` に対応しています。UTMタグが付与されていない流入（直接流入やオーガニック検索）の場合は NULL になることがあります。
:::

## 商品×チャネル別の粗利率を計算するSQL

先ほどのクエリで取得したセッション×注文データを、社内の売上・原価テーブルと結合して粗利率を算出します。

以下では、社内テーブルが `your_project.sales.order_items` として存在し、カラム構成が `order_id, item_sku, item_name, quantity, unit_price, unit_cost` であることを前提にしています。

```sql
WITH session_purchase AS (
  -- （前述のクエリをCTEとして再利用）
  SELECT
    medium,
    source,
    transaction_id,
    revenue,
    event_date
  FROM /* 上記のSQLをここにネスト、またはビューとして呼び出す */
    `your_project.analytics.session_purchase_view`
),

item_margin AS (
  SELECT
    oi.order_id,
    oi.item_sku,
    oi.item_name,
    SUM(oi.quantity * oi.unit_price) AS item_revenue,
    SUM(oi.quantity * oi.unit_cost)  AS item_cost,
    SUM(oi.quantity * (oi.unit_price - oi.unit_cost)) AS gross_profit
  FROM
    `your_project.sales.order_items` AS oi
  GROUP BY
    oi.order_id, oi.item_sku, oi.item_name
)

SELECT
  sp.medium,
  sp.source,
  CONCAT(sp.medium, ' / ', COALESCE(sp.source, '(not set)')) AS channel,
  im.item_sku,
  im.item_name,
  SUM(im.item_revenue)  AS total_revenue,
  SUM(im.item_cost)     AS total_cost,
  SUM(im.gross_profit)  AS total_gross_profit,
  ROUND(
    SAFE_DIVIDE(SUM(im.gross_profit), SUM(im.item_revenue)) * 100,
    2
  ) AS gross_margin_rate
FROM
  item_margin AS im
LEFT JOIN
  session_purchase AS sp
  ON im.order_id = sp.transaction_id
GROUP BY
  sp.medium, sp.source, channel, im.item_sku, im.item_name
ORDER BY
  total_gross_profit DESC
```

`gross_margin_rate` が粗利率（%）です。`SAFE_DIVIDE` を使うことで、売上がゼロの場合のゼロ除算エラーを回避しています。このクエリの結果をBigQueryのビューとして保存しておくと、Looker Studioとの連携がスムーズになります。

## Looker Studioで粗利率ダッシュボードを構築する

BigQueryのビューを作成したら、Looker Studio（旧データポータル）に接続してダッシュボードを構築します。手順の概要は以下のとおりです。

1. Looker Studioを開き、「データを追加」からBigQueryコネクタを選択する
2. 先ほど作成したビューをデータソースとして指定する
3. 「スコアカード」でKPIとして全体の粗利率を表示する
4. 「ピボットテーブル」で行に商品名・列にチャネルを設定し、値に粗利率を配置する
5. フィルターとして期間セレクターと商品カテゴリのプルダウンを追加する

ピボットテーブルでヒートマップ（条件付き書式）を設定すると、高粗利率のセルが緑、低粗利率のセルが赤で色分けされ、一目で改善ポイントを把握できます。

:::message
Looker Studioのデータソース接続はBigQueryの課金（スキャン量）が発生します。集計済みのビューやパーティションテーブルを利用してスキャン量を抑えることをおすすめします。
:::

ダッシュボードを社内で共有する際は、Googleアカウント単位でアクセス権を設定できます。経営者・マーケター・バイヤーなど、それぞれの担当領域のチャートを1枚のダッシュボードに集約すると、定例会議での活用がしやすくなります。

## まとめ

本記事では、EC事業の粗利率を商品×チャネル別に自動計算する仕組みについて解説しました。要点を整理します。

- **商品×チャネル別の粗利率**を把握することで、広告予算配分・価格戦略の意思決定精度が向上する
- **GA4のBigQueryエクスポート**では `UNNEST(event_params)` でga_session_idを取得し、`collected_traffic_source` で流入元を取得する
- **社内の売上・原価テーブル**とtransaction_idで結合することで、注文ごとの粗利率を計算できる
- **Looker Studioのピボットテーブル**にヒートマップを設定すると、改善ポイントが視覚的に把握しやすい

次のアクションとしては、まず自社のGA4にeコマース計測が正しく設定されているかを確認し、BigQueryエクスポートを有効化することから始めてみてください。その後、社内の受注・原価データをBigQueryに取り込む方法を検討するとスムーズです。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [チャネル別ROASをBigQueryで集計してLooker Studioに可視化する](https://zenn.dev/web_benriya/articles/bigquery-channel-roas-looker-studio)
- [BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った](https://zenn.dev/web_benriya/articles/bigquery-ec-product-profit-cvr-dashboard)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
