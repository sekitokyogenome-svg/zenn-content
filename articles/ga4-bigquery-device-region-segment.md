---
title: "GA4×BigQueryでデバイス別・地域別セグメント分析をする"
emoji: "📱"
type: "tech"
topics: ["bigquery", "googleanalytics", "dataanalytics"]
published: false
---

## はじめに

「モバイルとPCでコンバージョン率がどれくらい違うのか」「どの都道府県からのアクセスが多いのか」を正確に把握できていますか？

GA4のUIでもデバイス別・地域別のレポートは確認できますが、サンプリングの影響を受けやすく、複数ディメンションの掛け合わせ分析は制限があります。BigQueryを使えば、100%のデータでデバイス・地域のセグメント分析を自由に構築できます。

この記事では、GA4のBigQueryエクスポートデータからデバイス別・地域別の分析を行うSQLを解説します。

---

## GA4のデバイス情報・地域情報はどこにあるか

GA4のBigQueryエクスポートテーブルでは、デバイスと地域の情報がSTRUCT型のカラムに格納されています。

### デバイス関連カラム

| カラム | 内容 | 例 |
|--------|------|-----|
| `device.category` | デバイスカテゴリ | desktop, mobile, tablet |
| `device.operating_system` | OS名 | Android, iOS, Windows, Macintosh |
| `device.mobile_brand_name` | 端末メーカー | Apple, Samsung, Google |
| `device.mobile_model_name` | 端末モデル名 | iPhone, Pixel 7 |
| `device.web_info.browser` | ブラウザ名 | Chrome, Safari, Edge |

### 地域関連カラム

| カラム | 内容 | 例 |
|--------|------|-----|
| `geo.continent` | 大陸 | Asia, Americas, Europe |
| `geo.country` | 国 | Japan, United States |
| `geo.region` | 地域（都道府県等） | Tokyo, Osaka, Kanagawa |
| `geo.city` | 市区町村 | Shibuya, Shinjuku, Osaka |

:::message
`device.category` や `geo.country` はトップレベルのSTRUCT内にあるため、UNNESTは不要です。ドット記法でそのままアクセスできます。
:::

---

## デバイス別セッション数・コンバージョン率

デバイスカテゴリ別にセッション数とコンバージョン率を集計します。

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    device.category AS device_category,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
session_summary AS (
  SELECT
    session_id,
    device_category,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM sessions
  GROUP BY session_id, device_category
)
SELECT
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS cv_sessions,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cv_rate_percent
FROM session_summary
GROUP BY device_category
ORDER BY sessions DESC
```

出力例：

```text
device_category | sessions | cv_sessions | cv_rate_percent
----------------|----------|-------------|----------------
mobile          | 5,200    | 78          | 1.50
desktop         | 3,100    | 93          | 3.00
tablet          |   400    |  8          | 2.00
```

モバイルのセッション数が多いのにCVRが低い場合、モバイルUIの改善が有効な可能性があります。

---

## デバイス別×チャネル別のクロス集計

デバイスとチャネルの掛け合わせで、より詳細な分析ができます。

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    device.category AS device_category,
    collected_traffic_source.manual_medium AS medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
)
SELECT
  device_category,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT session_id) AS sessions
FROM sessions
GROUP BY device_category, medium
ORDER BY device_category, sessions DESC
```

---

## 地域別セッション数（都道府県ランキング）

日本国内の都道府県別にセッション数をランキングします。

```sql
SELECT
  geo.region AS region,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
  AND geo.country = 'Japan'
GROUP BY region
ORDER BY sessions DESC
LIMIT 20
```

:::message
GA4のBigQueryデータでは、地域名が英語表記（Tokyo, Osaka等）で格納されています。日本語に変換したい場合は、マッピングテーブルを別途用意してJOINするのが実用的です。
:::

---

## 国別セッション数（海外展開サイト向け）

海外ユーザーの動向を把握したい場合は、国別の集計が有効です。

```sql
SELECT
  geo.country AS country,
  geo.continent AS continent,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY country, continent
ORDER BY sessions DESC
LIMIT 30
```

---

## PIVOT的なデバイス別集計（日別×デバイス）

日別×デバイス別のセッション数を横持ちで表示します。Looker Studioやスプレッドシートでの可視化に便利です。

```sql
WITH daily_device AS (
  SELECT
    event_date,
    device.category AS device_category,
    COUNT(DISTINCT
      CONCAT(
        user_pseudo_id, '.',
        CAST(
          (SELECT value.int_value
           FROM UNNEST(event_params)
           WHERE key = 'ga_session_id') AS STRING)
      )
    ) AS sessions
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY event_date, device_category
)
SELECT
  event_date,
  SUM(CASE WHEN device_category = 'desktop' THEN sessions ELSE 0 END) AS desktop,
  SUM(CASE WHEN device_category = 'mobile' THEN sessions ELSE 0 END) AS mobile,
  SUM(CASE WHEN device_category = 'tablet' THEN sessions ELSE 0 END) AS tablet,
  SUM(sessions) AS total
FROM daily_device
GROUP BY event_date
ORDER BY event_date
```

出力例：

```text
event_date | desktop | mobile | tablet | total
-----------|---------|--------|--------|------
20260301   | 105     | 180    | 15     | 300
20260302   | 98      | 165    | 12     | 275
20260303   | 112     | 190    | 18     | 320
```

---

## 地域×デバイスのクロス分析

地域とデバイスを掛け合わせることで、地域ごとのデバイス利用傾向が見えます。

```sql
SELECT
  geo.region AS region,
  device.category AS device_category,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
  AND geo.country = 'Japan'
GROUP BY region, device_category
HAVING sessions >= 5
ORDER BY region, sessions DESC
```

地方都市でモバイル比率が高い場合、モバイルファーストのUI改善が地方からの集客に効く可能性があります。

---

## OS別・ブラウザ別の分析

特定のOSやブラウザで問題が発生していないかを確認する用途にも使えます。

```sql
SELECT
  device.operating_system AS os,
  device.web_info.browser AS browser,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  ROUND(AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'engagement_time_msec')
  ) / 1000, 1) AS avg_engagement_sec
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY os, browser
HAVING sessions >= 10
ORDER BY sessions DESC
LIMIT 20
```

特定のブラウザでエンゲージメント時間が極端に短い場合、表示崩れやJSエラーの可能性があります。

---

## まとめ

GA4のBigQueryデータでは、`device.category` や `geo.region` を使ってデバイス別・地域別のセグメント分析をSQLで自由に構築できます。PIVOT的な横持ち集計やクロス分析を組み合わせることで、GA4 UIでは難しい多次元の分析が可能になります。特にモバイルとデスクトップのCVR差や地域別のアクセス傾向は、サイト改善の具体的なアクションにつながりやすい指標です。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
