---
title: "GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した"
emoji: "⚡"
type: "idea"
topics: ["bigquery", "googleanalytics", "performance"]
published: false
---

## 「サイトが遅い」と感じたら、売上を失っているかもしれない

Googleの調査によると、ページの読み込み時間が1秒から3秒に増加すると、直帰率は32%増加するとされています。ECサイトにおいては、ページ速度の低下がそのままCVR（コンバージョン率）の低下につながります。

しかし、「サイト速度を改善しよう」という判断を下すには、速度とCVRの関係を自社データで定量的に示す必要があります。この記事では、GA4×BigQueryを使ってCore Web VitalsとCVRの相関を分析し、速度改善前後の効果を測定する方法を解説します。

## Core Web Vitalsとは

Core Web Vitals（CWV）は、Googleが定めるWebページのユーザー体験指標です。

| 指標 | 意味 | 良好の基準 |
|------|------|-----------|
| LCP (Largest Contentful Paint) | メインコンテンツの表示速度 | 2.5秒以下 |
| INP (Interaction to Next Paint) | インタラクションの応答速度 | 200ms以下 |
| CLS (Cumulative Layout Shift) | レイアウトのずれ | 0.1以下 |

これらの指標は、Google Search Consoleの「ウェブに関する主な指標」レポートや、Chrome UX Report（CrUX）で確認できます。

## CrUXデータをBigQueryで活用する

Chrome UX Report（CrUX）は、Chromeブラウザの実ユーザーから匿名で収集されたパフォーマンスデータで、BigQueryで公開されています。

```sql
SELECT
  origin,
  effective_connection_type.name AS connection_type,
  form_factor.name AS device,
  largest_contentful_paint.histogram AS lcp_histogram,
  interaction_to_next_paint.histogram AS inp_histogram,
  cumulative_layout_shift.histogram AS cls_histogram
FROM
  `chrome-ux-report.all.202503`
WHERE
  origin = 'https://your-ec-site.com'
```

:::message
CrUXデータは月次で更新され、`chrome-ux-report.all.YYYYMM` の形式でテーブルが公開されています。自社サイトのオリジンを指定して抽出します。
:::

## Step 1: GA4でページ速度関連のイベントを取得する

GA4では、Web Vitalsのデータを取得するためにGTMでカスタムイベントを設定する方法が一般的です。`web-vitals` ライブラリを使ってLCP・INP・CLSを計測し、GA4にカスタムイベントとして送信します。

BigQueryでカスタムイベントとして計測されたCWVデータを集計するSQLは以下の通りです。

```sql
WITH web_vitals AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS metric_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    device.category AS device_category
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
)
SELECT
  metric_name,
  device_category,
  COUNT(*) AS sample_count,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(50)], 2) AS p50,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(75)], 2) AS p75,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(90)], 2) AS p90
FROM web_vitals
WHERE metric_name IN ('LCP', 'INP', 'CLS')
GROUP BY metric_name, device_category
ORDER BY metric_name, device_category
```

P75（75パーセンタイル）がGoogleの推奨する「フィールドデータ」の評価基準に使われる値です。

## Step 2: LCPとCVRの相関分析

ユーザーごとのLCP値とコンバージョン（購入）の有無を突合し、相関を分析します。

```sql
WITH user_lcp AS (
  SELECT
    user_pseudo_id,
    APPROX_QUANTILES(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value'),
      100
    )[OFFSET(50)] AS median_lcp
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
  GROUP BY user_pseudo_id
),
user_conversions AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
combined AS (
  SELECT
    l.user_pseudo_id,
    l.median_lcp,
    CASE
      WHEN l.median_lcp <= 2500 THEN '良好（2.5秒以下）'
      WHEN l.median_lcp <= 4000 THEN '改善が必要（2.5-4秒）'
      ELSE '不良（4秒超）'
    END AS lcp_category,
    IFNULL(c.purchases, 0) AS purchases,
    IF(IFNULL(c.purchases, 0) > 0, 1, 0) AS converted
  FROM user_lcp l
  LEFT JOIN user_conversions c
    ON l.user_pseudo_id = c.user_pseudo_id
)
SELECT
  lcp_category,
  COUNT(*) AS users,
  SUM(converted) AS converters,
  ROUND(SUM(converted) / COUNT(*) * 100, 2) AS cvr_pct
FROM combined
GROUP BY lcp_category
ORDER BY cvr_pct DESC
```

このクエリの結果から、LCPが良好なユーザーと不良なユーザーでCVRにどの程度の差があるかを確認できます。

## Step 3: 速度改善前後の比較

サイト速度の改善施策（画像最適化、CDN導入、JavaScriptの遅延読み込みなど）を実施した前後で、CWVとCVRの変化を測定します。

```sql
WITH period_metrics AS (
  SELECT
    CASE
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-06-01' AND '2025-06-30' THEN '改善前（6月）'
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-08-01' AND '2025-08-31' THEN '改善後（8月）'
    END AS period,
    event_name,
    user_pseudo_id,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS lcp_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250831'
    AND (
      event_name = 'web_vitals'
      OR event_name = 'purchase'
      OR event_name = 'session_start'
    )
),
lcp_summary AS (
  SELECT
    period,
    ROUND(APPROX_QUANTILES(lcp_value, 100)[OFFSET(75)], 0) AS lcp_p75
  FROM period_metrics
  WHERE metric_name = 'LCP'
    AND period IS NOT NULL
  GROUP BY period
),
cvr_summary AS (
  SELECT
    period,
    COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS purchasers,
    ROUND(
      COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END)
      / COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) * 100,
      2
    ) AS cvr_pct
  FROM period_metrics
  WHERE period IS NOT NULL
  GROUP BY period
)
SELECT
  c.period,
  l.lcp_p75,
  c.sessions,
  c.purchasers,
  c.cvr_pct
FROM cvr_summary c
INNER JOIN lcp_summary l
  ON c.period = l.period
ORDER BY c.period
```

:::message
改善前後の比較では、改善実施月（7月）を除外し、その前後の月を比較しています。季節変動の影響を排除するため、前年同月のデータとも比較することを推奨します。
:::

## Step 4: デバイス別の速度×CVR分析

モバイルとデスクトップでは速度の影響度が異なります。デバイス別に分析することで、どのデバイスに優先的に速度改善の投資をすべきかが判断できます。

```sql
WITH device_performance AS (
  SELECT
    device.category AS device_category,
    CASE
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 2500 THEN '良好'
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 4000 THEN '要改善'
      ELSE '不良'
    END AS lcp_status,
    user_pseudo_id
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
),
device_conversions AS (
  SELECT
    user_pseudo_id,
    1 AS converted
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  dp.device_category,
  dp.lcp_status,
  COUNT(DISTINCT dp.user_pseudo_id) AS users,
  COUNTIF(dc.converted = 1) AS converters,
  ROUND(COUNTIF(dc.converted = 1) / COUNT(DISTINCT dp.user_pseudo_id) * 100, 2) AS cvr_pct
FROM device_performance dp
LEFT JOIN device_conversions dc
  ON dp.user_pseudo_id = dc.user_pseudo_id
GROUP BY dp.device_category, dp.lcp_status
ORDER BY dp.device_category, dp.lcp_status
```

モバイルでの速度不良×CVR低下が顕著であれば、モバイル向けの速度改善（画像の遅延読み込み、AMP対応、軽量テーマへの変更など）を優先する判断材料になります。

## 速度改善の投資対効果を試算する

分析結果をもとに、速度改善によるCVR改善の経済的インパクトを試算します。

例えば以下のような結果が得られた場合を考えます。

- 月間セッション数: 50,000
- 改善前CVR: 1.2%
- 改善後CVR: 1.5%
- 平均注文単価: 5,000円

CVR改善による月間売上増は以下のように計算できます。

```
50,000 × (1.5% - 1.2%) × 5,000円 = 750,000円/月
```

年間では900万円のインパクトになります。この数字と速度改善にかかるコスト（CDN導入費、開発工数など）を比較して投資判断を行います。

## 注意点

速度とCVRの相関分析には、以下の注意点があります。

**相関と因果の区別**

速度が速いユーザーのCVRが高いとしても、それが速度が原因とは限りません。高速回線を使っているユーザーは、一般的にデジタルリテラシーが高く購買意欲も高い可能性があります。

**Web Vitalsの計測カバレッジ**

GTMでカスタム送信している場合、JavaScript実行後にしかデータが送信されないため、極端に遅いページ読み込みで離脱したユーザーのデータは取得できていない可能性があります。

**外部要因の排除**

速度改善前後の比較では、同時期に行った他の施策（デザイン変更、価格変更、広告出稿量の変化など）の影響を切り分ける必要があります。

## まとめ

サイト速度の改善はSEOだけでなく、CVRにも直接影響する投資です。GA4×BigQueryでCWVデータとコンバージョンデータを突合することで、「速度改善がどの程度の売上改善につながるか」を自社データで検証できます。

まずはStep 1のWeb Vitalsデータ集計から始めて、自社サイトの現状を把握するところからスタートしてみてください。

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
