---
title: "ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法"
emoji: "📅"
type: "idea"
topics: ["bigquery", "ec", "dataanalytics"]
published: false
---

## はじめに

「去年の今頃、何が売れていたか覚えていますか？」――EC運営歴が長くなると、なんとなく肌感覚で季節のトレンドはわかってきます。でも、「感覚」で仕入れ判断をしていると、在庫過多や欠品のリスクが常につきまといます。

自分が支援していた某アパレル系ECでは、前年のセール時期に合わせて大量に仕入れたところ、今年はセール開始を2週間後ろにずらしたため、在庫が1ヶ月以上滞留してしまった経験がありました。

こうした判断ミスを減らすためには、「感覚」ではなく「データ」に基づく前年比分析が有効です。本記事では、BigQueryを使ったECの季節変動分析と、仕入れ計画への活用方法を紹介します。

---

## なぜBigQueryで前年比分析をするのか

GA4の標準UIにも前年比較機能はありますが、以下の点でBigQueryのほうが柔軟です。

- **任意の粒度で集計できる**: 月別・週別・日別を自由に切り替え可能
- **商品カテゴリ×期間のクロス分析**: 標準UIでは限界がある掛け合わせ
- **SQL結果をそのまま仕入れ計画シートに反映**: スプレッドシートやLookerStudioとの連携が容易
- **サンプリングなし**: データ量が多くても正確な数値で比較できる

---

## 月別売上の前年比SQL

まず、月別の売上を前年同月と並べて比較するクエリです。

```sql
WITH monthly_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS year_month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT user_pseudo_id) AS purchasers
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year_month, year, month
)
SELECT
  curr.month,
  curr.year_month AS current_period,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  curr.purchasers AS current_purchasers,
  prev.purchasers AS prev_purchasers,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  ROUND(SAFE_DIVIDE(curr.purchasers - prev.purchasers, prev.purchasers) * 100, 1) AS purchasers_yoy_pct
FROM monthly_revenue curr
LEFT JOIN monthly_revenue prev
  ON curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.month;
```

`LEFT JOIN` で前年同月を結合しています。前年データがない月は `NULL` になるため、新規商品のローンチ月などを確認する際にも使えます。

---

## 週別売上の前年比SQL

仕入れ判断を精度高くするには、月単位よりも週単位のほうが実務的です。

```sql
WITH weekly_revenue AS (
  SELECT
    EXTRACT(ISOYEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_year,
    EXTRACT(ISOWEEK FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_week,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT
      CONCAT(
        user_pseudo_id, '-',
        CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
      )
    ) AS purchase_sessions
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY iso_year, iso_week
)
SELECT
  curr.iso_week,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.purchase_sessions AS current_sessions,
  prev.purchase_sessions AS prev_sessions
FROM weekly_revenue curr
LEFT JOIN weekly_revenue prev
  ON curr.iso_week = prev.iso_week
  AND curr.iso_year = prev.iso_year + 1
WHERE curr.iso_year = 2026
ORDER BY curr.iso_week;
```

ISO週番号を使うことで、曜日のズレを最小限に抑えた前年比較ができます。

:::message
年末年始やGWなど、祝日の配置が前年と異なる場合は週番号ベースの比較でもズレが出ます。大型連休周辺は手動で補正を入れるか、前後の週を含めた移動平均で見るのがおすすめです。
:::

---

## 商品カテゴリ別×月別の分析

仕入れ判断に直結するのは、カテゴリ単位の季節パターンです。

```sql
WITH category_monthly AS (
  SELECT
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS category,
    SUM(ecommerce.purchase_revenue) AS revenue,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'quantity')
    ) AS quantity
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year, month, category
)
SELECT
  curr.category,
  curr.month,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.quantity AS current_qty,
  prev.quantity AS prev_qty
FROM category_monthly curr
LEFT JOIN category_monthly prev
  ON curr.category = prev.category
  AND curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.category, curr.month;
```

---

## 某ECでの活用事例

某アパレル系ECで、カテゴリ別×月別の前年比分析を実施した結果です。

| カテゴリ | 月 | 前年売上 | 今年売上 | 前年比 |
|---------|-----|---------|---------|--------|
| アウター | 1月 | 420万円 | 380万円 | -9.5% |
| アウター | 2月 | 280万円 | 310万円 | +10.7% |
| Tシャツ | 3月 | 150万円 | 210万円 | +40.0% |
| Tシャツ | 4月 | 320万円 | ― | ― |

この結果から見えたのは以下のポイントです。

1. **アウターの売れ行きピークが前年より1ヶ月後ろにズレている**: 暖冬の影響で1月の売上が減少、2月に流れた
2. **Tシャツの立ち上がりが前年より早い**: 3月時点で前年比+40%は、仕入れの前倒しが必要なサイン
3. **前年のデータがない月（4月以降）は、3月までのトレンドから予測を立てる**

---

## 仕入れ計画への活かし方

データ分析の結果を仕入れ判断に落とし込む際は、以下の3ステップで考えます。

### ステップ1：前年の月別売上カーブを確認する

「何月にピークがあるか」「ピーク前にどの程度売れ始めるか」を把握します。

### ステップ2：今年の直近データで補正する

前年比で+20%なのか-10%なのかによって、仕入れ量の調整幅が変わります。直近1〜2ヶ月のトレンドを重視します。

### ステップ3：安全在庫を設定する

前年データ＋直近トレンドから予測した販売数に対して、10〜20%の安全在庫を上乗せするのが一般的です。ただし、過剰在庫のリスクとのバランスが重要なので、カテゴリの利益率も考慮に入れます。

---

## LookerStudioでの可視化

BigQueryの前年比データをLookerStudioに接続すると、売上推移のグラフ上に前年のラインを重ねて表示できます。

可視化のポイントは以下の通りです。

- **折れ線グラフ**: 今年と前年を色分けして重ね表示
- **棒グラフ**: カテゴリ別の前年比増減を横棒グラフで表示
- **スコアカード**: 前年比のパーセンテージを月ごとに表示
- **フィルタ**: カテゴリ・期間で絞り込めるようにしておく

経営者やバイヤーが「パッと見で傾向がわかる」ダッシュボードを作ることで、データ分析の価値が伝わりやすくなります。

---

## まとめ

ECの季節変動を前年比で分析することは、仕入れ判断の精度を上げる基本です。BigQueryを使えば、月別・週別・カテゴリ別の切り口を自由に掛け合わせて、GA4の標準UIでは難しい多角的な比較が可能になります。

自分としては、前年比分析は「去年と比べてどうか」を知ることよりも、「今年の仕入れ判断にどう使うか」までセットで考えることが大事だと感じています。分析結果が意思決定に繋がらなければ、ただのレポートで終わってしまうので。

皆さんのECでは、仕入れ判断にどの程度データを活用できていますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
