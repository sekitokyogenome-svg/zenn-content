---
title: "2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する"
emoji: "🚛"
type: "idea"
topics: ["bigquery","ec","sql","dataengineering","googlecloud"]
published: false
---

## はじめに

「送料が上がって利益が出ない」「どの商品が配送コストの足を引っ張っているのかわからない」――そうした声を、EC事業者の方から多くお聞きします。2024年問題と呼ばれる物流業界の労働規制強化（トラックドライバーの時間外労働上限規制）は、配送コストの構造的な上昇をもたらしました。2026年現在、その影響は中小ECにも着実に波及しており、以前と同じ感覚で送料設定を続けていると、売上が伸びても利益が縮小するという状況が起きやすくなっています。

一方で、多くの中小EC事業者がデータを活用した意思決定に踏み出せていないのも現実です。「Googleアナリティクス（GA4）は入れているが、数字の見方がわからない」「配送の数字は配送会社の明細しか見ていない」というケースは珍しくありません。しかし、GA4のデータをBigQueryに連携し、注文データと組み合わせることで、どの流入経路・どの商品カテゴリが配送コストを圧迫しているかを把握できるようになります。

本記事では、BigQueryを活用して配送コストを可視化・分析する方法を、非エンジニアの方にも理解しやすいよう丁寧にご説明します。SQLのサンプルも掲載していますので、エンジニアや外部パートナーへの依頼時の参考としても活用していただけます。

---

## なぜ配送コストの「見える化」が急務なのか

2024年問題以降、大手物流会社は相次いで配送料金を改定しました。従来は「1件あたり◯円」という固定的なイメージで捉えていた送料も、サイズ・重量・エリア・時間指定の有無によって変動幅が広がっています。この変動をざっくりした平均値でしか把握していない場合、以下のようなリスクが生じます。

- 重量のある商品や遠距離配送の多い商品を、利益が出ない価格帯で販売し続ける
- 送料無料キャンペーンの対象を絞りきれず、高コスト注文に送料補填が発生する
- 広告経由の注文ほど遠方・単品購入が多く、LTV（顧客生涯価値）が低い

こうした問題は、注文データと配送コストデータをひもづけて初めて見えてきます。ECカートのCSVを毎月手作業で集計している場合、分析に工数がかかりすぎて「わかってはいるが対処できない」状態になりがちです。BigQueryを活用すると、データの蓄積・集計・可視化を自動化でき、月次レポートの作成時間を大幅に短縮できます。

---

## BigQueryで配送コストを分析するためのデータ設計

BigQueryによる配送コスト分析では、主に以下のデータソースを連携させます。

| データソース | 内容 | 連携方法 |
|---|---|---|
| GA4（BigQueryエクスポート） | 流入元・セッション・購買イベント | GA4管理画面から設定 |
| ECカート注文データ | 注文ID・商品・金額・エリア | CSVインポートまたはAPI |
| 配送会社の請求データ | 送り状番号・重量・配送料 | CSVインポート |

GA4のBigQueryエクスポートは、GA4管理画面の「BigQueryのリンク」から設定することで、毎日自動的にデータが送られてきます。エクスポートされたデータは `プロジェクトID.analytics_XXXXXXXXX.events_YYYYMMDD` という形式のテーブルに格納されます。

注文データや配送データは、まずBigQueryのストレージ（GCS）経由でインポートするか、Cloud Functionsを使ってAPIから自動取り込みする方法が一般的です。最初はCSVの手動インポートから始め、慣れてきたら自動化を検討するとよいでしょう。

---

## 流入経路別・配送コスト分析のSQLサンプル

GA4の購買イベント（`purchase`）と流入元情報を使い、どのマーケティングチャネル経由の注文が配送コストを押し上げているかを分析するクエリの例を示します。

```sql
-- GA4の購買イベントから流入元と注文IDを取得する
SELECT
  event_date,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS session_id,
  -- 流入元はcollected_traffic_sourceから取得する
  collected_traffic_source.manual_medium  AS traffic_medium,
  collected_traffic_source.manual_source  AS traffic_source,
  -- ecommerce情報
  ecommerce.purchase_revenue             AS revenue,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'transaction_id'
  ) AS transaction_id
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
  AND event_name = 'purchase'
```

このクエリで取得した `transaction_id` と、別途インポートした注文データ・配送コストデータを `JOIN` することで、チャネル別の配送コスト合計や1注文あたりの平均配送費を算出できます。

```sql
-- 流入経路別の配送コスト集計（GA4と配送データのJOIN例）
WITH ga4_purchases AS (
  SELECT
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    ecommerce.purchase_revenue             AS revenue
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
    AND event_name = 'purchase'
)
SELECT
  COALESCE(g.traffic_medium, '(none)')       AS medium,
  COALESCE(g.traffic_source, '(direct)')     AS source,
  COUNT(*)                                    AS order_count,
  ROUND(SUM(g.revenue), 0)                   AS total_revenue,
  ROUND(SUM(s.shipping_cost), 0)             AS total_shipping_cost,
  ROUND(AVG(s.shipping_cost), 0)             AS avg_shipping_cost_per_order,
  ROUND(SUM(s.shipping_cost) / SUM(g.revenue) * 100, 1) AS shipping_cost_ratio_pct
FROM
  ga4_purchases AS g
  LEFT JOIN `your_project.dataset.shipping_costs` AS s
    ON g.transaction_id = s.order_id
GROUP BY
  medium,
  source
ORDER BY
  total_shipping_cost DESC
```

:::message
`your_project` や `analytics_XXXXXXXXX`、`your_project.dataset.shipping_costs` の部分は、ご自身のGCPプロジェクトIDおよびテーブル名に置き換えてください。日付範囲の `_TABLE_SUFFIX` も分析対象期間に合わせて調整してください。
:::

このクエリを実行すると、たとえば「Meta広告経由の注文は配送コスト比率が高い」「自然検索経由は平均配送コストが低い」といった傾向が見えてきます。広告費の投資対効果を評価する際に、配送コストを考慮に入れることで、より実態に即した判断が可能になります。

---

## 商品カテゴリ別の配送コスト分析で値付けを見直す

流入経路と並んで重要なのが、商品ごとの配送コスト分析です。商品サイズや重量が異なれば配送料も変わりますが、商品ページの価格設定にその差が反映されていないケースがよくあります。

以下のクエリは、商品カテゴリ別に粗利から配送コストを差し引いた「実質利益」を算出する例です。

```sql
-- 商品カテゴリ別の実質利益を計算する
SELECT
  p.category                                              AS product_category,
  COUNT(DISTINCT o.order_id)                              AS order_count,
  ROUND(SUM(o.revenue), 0)                               AS total_revenue,
  ROUND(SUM(o.cost_of_goods), 0)                         AS total_cogs,
  ROUND(SUM(s.shipping_cost), 0)                         AS total_shipping_cost,
  ROUND(SUM(o.revenue - o.cost_of_goods - s.shipping_cost), 0) AS actual_profit,
  ROUND(
    SUM(o.revenue - o.cost_of_goods - s.shipping_cost)
    / NULLIF(SUM(o.revenue), 0) * 100, 1
  )                                                       AS actual_margin_pct
FROM
  `your_project.dataset.orders`          AS o
  LEFT JOIN `your_project.dataset.products`       AS p
    ON o.product_id = p.product_id
  LEFT JOIN `your_project.dataset.shipping_costs` AS s
    ON o.order_id = s.order_id
WHERE
  o.order_date BETWEEN '2026-01-01' AND '2026-07-31'
GROUP BY
  product_category
ORDER BY
  actual_margin_pct ASC
```

このような分析を行うと、「見かけの粗利率は高いが、重量があるため配送コストが高く、実質利益率が低い商品」を特定できます。その商品については価格改定・送料別途設定・梱包の見直しといった対策を検討する材料になります。

---

## LookerStudioでダッシュボード化して継続的に監視する

SQLでの分析結果は、Google LookerStudio（旧データポータル）と接続することで、グラフやカード形式のダッシュボードとして関係者に共有できます。BigQueryとLookerStudioの連携は、LookerStudioの「データソース追加」からBigQueryを選択するだけで設定でき、専門的なサーバー設定は不要です。

ダッシュボードに含めると有用な指標の例を挙げます。

- **月別配送コスト総額と売上比率の推移**：コスト上昇のトレンドを早期に把握する
- **チャネル別・配送コスト比率ランキング**：高コストな流入元への広告予算配分を見直す
- **商品カテゴリ別・実質利益率一覧**：値付けや送料設定の改善優先度を可視化する
- **エリア別・平均配送費**：遠距離エリアへの送料無料適用条件を設定する判断材料にする

ダッシュボードが整備されると、毎月の定例会議やEC担当者のモニタリング業務が大幅に効率化されます。「今月も配送コストが高い気がするが、何が原因かわからない」という状態から、「◯◯カテゴリの売上が伸びたことで配送コストが増加した」という原因特定まで、データで会話できるようになります。

---

## まとめ

2024年問題を契機とした配送コストの上昇は、構造的なものであり、今後も続く可能性があります。この変化に対応するには、感覚や経験だけでなく、データに基づいた意思決定が求められます。

本記事で取り上げたポイントを整理します。

- GA4のBigQueryエクスポートと注文データ・配送コストデータを連携させることで、流入経路別・商品別の配送コスト分析が可能になる
- `ga_session_id` は `UNNEST(event_params)` 経由で取得し、流入元は `collected_traffic_source.manual_medium / manual_source` を使用する
- LookerStudioと組み合わせることで、継続的なモニタリング体制を低コストで構築できる
- 分析結果は値付け・送料設定・広告予算配分の見直しに直結させることが重要

最初の一歩として、GA4のBigQueryエクスポートを有効化するだけでも、将来のデータ活用の幅が大きく広がります。まだ設定されていない場合は、GA4管理画面の「BigQueryのリンク」から今日にでも試してみることをお勧めします。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
