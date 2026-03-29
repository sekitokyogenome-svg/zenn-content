---
title: "GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した"
emoji: "🎯"
type: "idea"
topics: ["bigquery", "ec", "marketing"]
published: false
---

## ポイント還元施策、「なんとなく効いている」で済ませていませんか

ECサイトでよく実施されるポイント還元キャンペーン。「ポイント5倍キャンペーン」「初回購入500ポイント付与」といった施策は、多くのEC事業者が定期的に行っています。

しかし、その効果を定量的に検証しているケースは意外と少ないです。

- 施策期間中の売上が増えた → 「効果があった」と判断
- ポイント還元分のコストを差し引いた利益は把握していない
- 施策で獲得した顧客がその後も継続購入しているかは追えていない

この記事では、GA4×BigQueryを使って、ポイント還元施策の前後でコホートを比較し、購入頻度やLTVの変化を定量的に評価する方法を解説します。

## 分析の設計: 施策前後コホートの定義

施策の効果を正しく評価するには、以下の2つのコホートを比較します。

| コホート | 定義 |
|---------|------|
| 施策前コホート | 施策開始前の1ヶ月間に初回購入したユーザー |
| 施策後コホート | 施策期間中に初回購入したユーザー |

ここでは、2025年4月に「初回購入ポイント500円還元」施策を実施した想定で進めます。

- 施策前コホート: 2025年3月に初回購入
- 施策後コホート: 2025年4月に初回購入

## Step 1: コホートの抽出

まず、各コホートに属するユーザーを特定します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  COUNT(*) AS new_customers
FROM first_purchase
WHERE cohort_month IN ('2025-03', '2025-04')
GROUP BY cohort_month, cohort_label
ORDER BY cohort_month
```

この時点で、施策後コホートの新規顧客数が施策前と比べて増加しているかを確認します。

## Step 2: コホート別の月次購入回数

各コホートのユーザーが、初回購入後にどの程度リピート購入しているかを月次で追跡します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
subsequent_purchases AS (
  SELECT
    e.user_pseudo_id,
    fp.cohort_month,
    DATE_DIFF(
      DATE(TIMESTAMP_MICROS(e.event_timestamp), 'Asia/Tokyo'),
      fp.first_purchase_date,
      MONTH
    ) AS months_after
  FROM
    `beeracle.analytics_263425816.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
  WHERE
    e._TABLE_SUFFIX BETWEEN '20250301' AND '20251231'
    AND e.event_name = 'purchase'
    AND fp.cohort_month IN ('2025-03', '2025-04')
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  months_after,
  COUNT(DISTINCT user_pseudo_id) AS active_users,
  COUNT(*) AS total_purchases
FROM subsequent_purchases
WHERE months_after BETWEEN 0 AND 6
GROUP BY cohort_month, cohort_label, months_after
ORDER BY cohort_month, months_after
```

## Step 3: コホート別LTVの比較

施策前後のコホートで、6ヶ月間の累積LTVを比較します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
user_ltv AS (
  SELECT
    fp.user_pseudo_id,
    fp.cohort_month,
    COUNT(*) AS purchase_count,
    SUM(e.ecommerce.purchase_revenue) AS total_revenue
  FROM
    `beeracle.analytics_263425816.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
  WHERE
    e._TABLE_SUFFIX BETWEEN '20250301' AND '20251231'
    AND e.event_name = 'purchase'
    AND fp.cohort_month IN ('2025-03', '2025-04')
    AND DATE_DIFF(
      DATE(TIMESTAMP_MICROS(e.event_timestamp), 'Asia/Tokyo'),
      fp.first_purchase_date,
      DAY
    ) <= 180
  GROUP BY fp.user_pseudo_id, fp.cohort_month
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  COUNT(*) AS customers,
  ROUND(AVG(purchase_count), 2) AS avg_purchases,
  ROUND(AVG(total_revenue), 0) AS avg_ltv_180d,
  ROUND(STDDEV(total_revenue), 0) AS stddev_ltv
FROM user_ltv
GROUP BY cohort_month, cohort_label
ORDER BY cohort_month
```

## Step 4: 施策のROI算出

施策の投資対効果を算出するために、ポイント還元コストとLTV増分を比較します。

```sql
-- 施策コストと効果のサマリー（手動入力値との組み合わせ）
WITH cohort_metrics AS (
  -- Step 3の結果を仮定
  SELECT '施策前' AS label, 150 AS customers, 12500 AS avg_ltv UNION ALL
  SELECT '施策後' AS label, 220 AS customers, 11800 AS avg_ltv
)
SELECT
  *,
  customers * avg_ltv AS total_ltv,
  CASE
    WHEN label = '施策後' THEN customers * 500  -- ポイント還元500円/人
    ELSE 0
  END AS campaign_cost,
  CASE
    WHEN label = '施策後' THEN (customers * avg_ltv) - (customers * 500)
    ELSE customers * avg_ltv
  END AS net_revenue
FROM cohort_metrics
```

:::message
上記は計算構造を示すための簡略化した例です。実際の分析では、Step 3の結果を直接利用して計算します。ポイント還元額は自社の施策条件に合わせて変更してください。
:::

## 結果の解釈と判断基準

コホート比較の結果は、以下の4パターンに分類できます。

**パターンA: 新規増加 + LTV維持**
ポイント還元で新規顧客が増え、かつその後のLTVも施策前コホートと同等。施策は成功と判断できます。

**パターンB: 新規増加 + LTV低下**
ポイント目当ての「浅い顧客」が流入した可能性があります。ポイント還元コストを差し引くと、実質的にはマイナスになるケースもあり得ます。

**パターンC: 新規微増 + LTV維持**
施策のリーチが不足していた可能性があります。告知チャネルや施策内容の見直しが必要です。

**パターンD: 新規増加 + リピート率低下**
初回購入のハードルは下がったものの、商品・サービスの満足度が伴っていない可能性があります。

## 注意点: 外部要因の排除

コホート比較では、施策以外の外部要因（季節変動、競合の動き、メディア露出など）が結果に影響する可能性があります。より精度の高い検証を行うには、以下の工夫が有効です。

- 前年同月のデータとも比較する
- 施策対象外のチャネルからの流入をコントロールグループとして使う
- 施策期間を複数回設けてN数を増やす

## まとめ

ポイント還元施策は「売上が増えたかどうか」だけで評価すると、本質的な効果を見誤ります。BigQueryでコホート分析を行うことで、施策で獲得した顧客の「その後の行動」まで追跡でき、投資対効果を正しく評価できるようになります。

次回施策を企画する前に、過去の施策のコホートデータを振り返ることをおすすめします。

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
