---
title: "BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った"
emoji: "💰"
type: "idea"
topics: ["bigquery", "ec", "lookerstudio"]
published: false
---

## はじめに

「売上が高い商品=利益が出ている商品」とは限らない――これはEC運営者なら一度は実感したことがあるはずです。

自分が支援していた某雑貨系ECでは、売上ランキングTOP5のうち2商品が、原価率の高さと広告費を考慮すると実質赤字だったことが発覚しました。売上だけを見ていると、こういう落とし穴に気づけません。

そこで作ったのが、商品別の「粗利×CVR×流入数」を一覧で確認できる利益ダッシュボードです。BigQueryで各指標を算出し、LookerStudioで可視化する仕組みを構築しました。本記事では、そのSQLと設計のポイントを紹介します。

---

## 必要な3つの指標

利益の観点で商品を評価するには、以下の3指標を掛け合わせて見ることが重要です。

| 指標 | 意味 | なぜ必要か |
|------|------|-----------|
| **粗利** | 売上 - 原価 | 利益の絶対額 |
| **CVR** | 商品ページ閲覧→購入の転換率 | ページの説得力 |
| **流入数** | 商品ページへのセッション数 | 露出の大きさ |

粗利が高くてもCVRが低ければ改善余地があるし、CVRが高くても流入数が少なければ露出を増やす施策が必要です。3つの指標をセットで見ることで、商品ごとの「次の打ち手」が見えてきます。

---

## 商品別の流入数とCVRを算出するSQL

GA4のBigQueryデータから、商品ページ別の流入数とCVRを算出します。

```sql
WITH product_views AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') AS item_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'view_item'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_purchases AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND ecommerce.purchase_revenue > 0
)
SELECT
  v.item_id,
  v.item_name,
  COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING))) AS view_sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr,
  SUM(p.revenue) AS total_revenue
FROM product_views v
LEFT JOIN product_purchases p
  ON v.user_pseudo_id = p.user_pseudo_id
  AND v.ga_session_id = p.ga_session_id
  AND v.item_id = p.item_id
GROUP BY v.item_id, v.item_name
HAVING view_sessions >= 10
ORDER BY total_revenue DESC;
```

---

## 原価データとの結合で粗利を算出する

GA4のデータには原価情報が含まれていないため、別途原価テーブルを用意してBigQueryに取り込みます。スプレッドシートからBigQueryへのインポートや、CSVアップロードが手軽です。

```sql
-- 原価テーブルの想定スキーマ
-- スプレッドシートまたはCSVからBigQueryにインポートする
CREATE TABLE IF NOT EXISTS `project.dataset.product_cost` (
  item_id STRING,
  item_name STRING,
  cost_price FLOAT64,
  selling_price FLOAT64
);
```

GA4の売上データと原価テーブルを結合して、商品別粗利を算出します。

```sql
WITH product_performance AS (
  -- 前述のクエリ結果（item_id, view_sessions, purchase_sessions, cvr, total_revenue）
  SELECT * FROM product_cvr_data
),
product_profit AS (
  SELECT
    pp.item_id,
    pp.item_name,
    pp.view_sessions,
    pp.purchase_sessions,
    pp.cvr,
    pp.total_revenue,
    pc.cost_price,
    pc.selling_price,
    ROUND(pp.total_revenue - (pc.cost_price * pp.purchase_sessions), 0) AS gross_profit,
    ROUND(
      SAFE_DIVIDE(
        pp.total_revenue - (pc.cost_price * pp.purchase_sessions),
        pp.total_revenue
      ) * 100, 1
    ) AS gross_margin_pct
  FROM product_performance pp
  LEFT JOIN `project.dataset.product_cost` pc
    ON pp.item_id = pc.item_id
)
SELECT
  item_id,
  item_name,
  view_sessions,
  purchase_sessions,
  cvr,
  total_revenue,
  gross_profit,
  gross_margin_pct,
  ROUND(SAFE_DIVIDE(gross_profit, view_sessions), 0) AS profit_per_view
FROM product_profit
ORDER BY gross_profit DESC;
```

`profit_per_view`（1閲覧あたりの粗利）は、流入数とCVRと粗利を1つの数値にまとめた指標です。この値が高い商品ほど「見せれば利益になる」商品であり、広告投資やサイト内露出を優先すべき対象です。

---

## 某ECでの分析結果

某雑貨系ECでの商品別分析結果です。

| 商品 | 流入数 | CVR | 売上 | 粗利 | 粗利率 | 利益/閲覧 |
|------|--------|-----|------|------|--------|----------|
| 商品A | 3,200 | 3.8% | 486,000円 | 245,000円 | 50.4% | 77円 |
| 商品B | 2,800 | 2.1% | 352,000円 | 68,000円 | 19.3% | 24円 |
| 商品C | 1,500 | 5.2% | 312,000円 | 198,000円 | 63.5% | 132円 |
| 商品D | 4,100 | 1.8% | 295,000円 | -12,000円 | -4.1% | -3円 |
| 商品E | 800 | 6.5% | 208,000円 | 142,000円 | 68.3% | 178円 |

ここから見えるインサイトは以下の通りです。

- **商品D**: 売上ランキングでは4位だが、粗利がマイナス。広告費を含めると赤字商品
- **商品E**: 流入数は少ないが、CVRと粗利率が高い。露出を増やせば利益が伸びる可能性がある
- **商品C**: CVRと粗利率のバランスが良好。利益/閲覧が132円と高く、広告投資の優先対象

---

## 4象限マトリクスで優先度を整理する

商品をCVRと粗利率の2軸で4象限に分類すると、打ち手が明確になります。

```text
           CVR 高
            │
  改善不要    │  最優先投資
  (維持)     │  (露出拡大)
            │
────────────┼──────────── 粗利率
            │
  撤退検討   │  CVR改善
  (広告停止)  │  (ページ改善)
            │
           CVR 低
```

BigQueryで4象限の分類を自動化するSQLも書けます。

```sql
SELECT
  item_id,
  item_name,
  cvr,
  gross_margin_pct,
  CASE
    WHEN cvr >= 3.0 AND gross_margin_pct >= 40 THEN '最優先投資'
    WHEN cvr >= 3.0 AND gross_margin_pct < 40 THEN '改善不要（維持）'
    WHEN cvr < 3.0 AND gross_margin_pct >= 40 THEN 'CVR改善'
    ELSE '撤退検討'
  END AS quadrant
FROM product_profit
ORDER BY quadrant, gross_profit DESC;
```

:::message
閾値（CVR 3.0%、粗利率 40%）はサイトの平均値をベースに設定します。業種や価格帯によって適切な閾値は変わるので、自社のデータに合わせて調整してください。
:::

---

## LookerStudioでダッシュボード化する

BigQueryのクエリ結果をLookerStudioに接続してダッシュボードを構築します。

### ダッシュボードの構成要素

1. **スコアカード**: 全商品合計の粗利・平均CVR・総流入数
2. **テーブル**: 商品別の詳細指標一覧（ソート・フィルタ対応）
3. **散布図**: 横軸=CVR、縦軸=粗利率、バブルサイズ=流入数
4. **棒グラフ**: 利益/閲覧のTOP10・WORST10

特に散布図は、先ほどの4象限マトリクスをそのまま可視化できるので、経営者やバイヤーにとって直感的に理解しやすいチャートです。

### 更新頻度

原価テーブルの更新頻度に合わせますが、月1回の更新でも実用的です。GA4データは日次でBigQueryに自動エクスポートされるため、流入数とCVRは常に最新値が反映されます。

---

## まとめ

「売上ランキング」だけで商品の評価をしていると、利益が出ていない商品に気づけません。粗利×CVR×流入数の3指標を掛け合わせて見ることで、「どの商品に投資すべきか」「どの商品を改善すべきか」が明確になります。

自分としては、利益ダッシュボードはECの経営判断に直結するツールだと感じています。作って終わりではなく、月次の振り返りで定期的に確認する運用を組み込むことが大事です。

皆さんのECでは、商品別の利益をどの程度可視化できていますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
