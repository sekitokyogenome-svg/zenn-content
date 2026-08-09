---
title: "BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した"
emoji: "📊"
type: "idea"
topics: ["bigquery", "ec", "dataanalytics"]
published: true
---

## ECサイトの「売れ筋商品」、本当に把握できていますか？

「うちの売れ筋はだいたいわかっている」

EC運営者の方からよくこのセリフを聞きます。しかし、感覚値と実際のデータには大きなギャップがあるケースが少なくありません。特に商品点数が100を超えてくると、どの商品が売上全体のどれくらいを占めているのか、正確に把握するのは困難です。

この記事では、BigQueryを使ってGA4のeコマースデータからパレート分析（ABC分析）を行い、売上上位20%の商品がどれだけの収益を生み出しているかを定量的に検証します。

## パレート法則とは

パレート法則（80:20の法則）は、「全体の結果の80%は、全体の20%の要因から生み出されている」という経験則です。ECサイトに当てはめると、以下のような仮説が立てられます。

- 売上の80%は、上位20%の商品が生み出している
- 利益の大部分は、少数の優良顧客から生まれている

この仮説が自社のデータでも成り立つかを検証することで、商品戦略の優先順位づけに根拠を持たせることができます。

## Step 1: 商品別売上集計SQL

まず、GA4のpurchaseイベントから商品別の売上を集計します。

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    items.item_id,
    SUM(items.item_revenue) AS total_revenue,
    COUNT(DISTINCT event_bundle_sequence_id) AS purchase_count
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY
    items.item_name, items.item_id
)
SELECT
  item_name,
  item_id,
  total_revenue,
  purchase_count,
  ROUND(total_revenue / SUM(total_revenue) OVER () * 100, 2) AS revenue_pct
FROM item_revenue
ORDER BY total_revenue DESC
```

このSQLで、各商品の売上合計・購入回数・売上構成比が取得できます。

## Step 2: 累積比率を算出してパレート曲線を描く

次に、累積構成比を算出してパレート分析の核となるデータを作ります。

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    items.item_id,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY
    items.item_name, items.item_id
),
ranked AS (
  SELECT
    item_name,
    item_id,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
cumulative AS (
  SELECT
    *,
    SUM(total_revenue) OVER (ORDER BY rank) AS cumulative_revenue,
    ROUND(rank / total_items * 100, 2) AS item_pct,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cumulative_revenue_pct
  FROM ranked
)
SELECT
  rank,
  item_name,
  total_revenue,
  item_pct,
  cumulative_revenue_pct,
  CASE
    WHEN cumulative_revenue_pct <= 80 THEN 'A'
    WHEN cumulative_revenue_pct <= 95 THEN 'B'
    ELSE 'C'
  END AS abc_rank
FROM cumulative
ORDER BY rank
```

このクエリのポイントは以下の通りです。

- `ROW_NUMBER()` で売上順にランク付け
- `SUM() OVER (ORDER BY rank)` で累積売上を算出
- 累積比率80%以内をAランク、95%以内をBランク、それ以外をCランクに分類

## Step 3: ABC分析のサマリー

ABCランク別に商品数と売上合計をまとめます。

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY items.item_name
),
ranked AS (
  SELECT
    item_name,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
classified AS (
  SELECT
    *,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cum_pct,
    CASE
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 80 THEN 'A'
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 95 THEN 'B'
      ELSE 'C'
    END AS abc_rank
  FROM ranked
)
SELECT
  abc_rank,
  COUNT(*) AS item_count,
  ROUND(COUNT(*) / MAX(total_items) * 100, 1) AS item_pct,
  SUM(total_revenue) AS total_revenue,
  ROUND(SUM(total_revenue) / MAX(grand_total) * 100, 1) AS revenue_pct
FROM classified
GROUP BY abc_rank
ORDER BY abc_rank
```

## 分析結果から読み取れること

パレート分析の結果を見ると、多くのECサイトで以下のような傾向が確認できます。

- Aランク商品は全体の15〜25%程度で、売上の70〜85%を占める
- Cランク商品は商品数の50%以上を占めるが、売上貢献は5%未満

このデータから、以下のような商品戦略の判断材料が得られます。

**Aランク商品（売上の柱）**
- 在庫切れを起こさないよう重点管理する
- 広告予算を優先配分する
- 関連商品のクロスセル施策を検討する

**Bランク商品（成長候補）**
- Aランクに引き上げる施策を検討する
- 商品ページの改善やレビュー獲得を進める

**Cランク商品（要検討）**
- 在庫コストに見合うかを評価する
- 廃番やセット販売への組み替えを検討する

## Looker Studioでの可視化

BigQueryの結果をLooker Studioに接続すれば、パレート曲線をグラフとして可視化できます。棒グラフで商品別売上を、折れ線グラフで累積比率を重ねて表示すると、直感的にABC分類の境界が把握できます。

経営者が毎月のレビュー会議で確認するダッシュボードに組み込むと、商品ポートフォリオの健全性を継続的にモニタリングできるようになります。

## まとめ

パレート分析は古典的な手法ですが、BigQueryとGA4を組み合わせることで、リアルタイムに近いデータで繰り返し検証できるようになります。感覚に頼った商品管理から、データに基づいた意思決定へ移行する第一歩として、まず自社データでのパレート分析を試してみてください。

## 関連記事

- [ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法](https://zenn.dev/web_benriya/articles/bigquery-ec-seasonal-yoy-analysis)
- [BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した](https://zenn.dev/web_benriya/articles/bigquery-one-time-vs-repeat-buyer-analysis)
- [チャネル別ROASをBigQueryで集計してLooker Studioに可視化する](https://zenn.dev/web_benriya/articles/bigquery-channel-roas-looker-studio)
- [BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った](https://zenn.dev/web_benriya/articles/bigquery-ec-product-profit-cvr-dashboard)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
