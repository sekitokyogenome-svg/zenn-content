---
title: "BigQueryでGA4の流入経路×購入金額のヒートマップを作成した"
emoji: "🗺️"
type: "tech"
topics: ["bigquery", "googleanalytics", "visualization"]
published: false
---

## はじめに

ECサイトの流入経路を分析する際、「チャネル別のセッション数」だけを見ていませんか。セッション数が多くても売上に貢献していないチャネルもあれば、セッション数は少なくても客単価が高いチャネルもあります。

流入経路とデバイスや地域をクロス集計し、ヒートマップとして可視化すると、どの組み合わせが売上に貢献しているかが一目でわかるようになります。

この記事では、BigQueryでGA4のデータをクロス集計し、Looker Studioでヒートマップを作成する方法を解説します。

---

## チャネル×デバイスのクロス集計SQL

まず、流入チャネルとデバイスカテゴリの組み合わせごとに、セッション数と売上を集計します。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    device.category AS device_category,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    -- チャネルグルーピング
    CASE
      WHEN medium = 'organic' THEN 'Organic Search'
      WHEN medium = 'cpc' THEN 'Paid Search'
      WHEN medium = 'social' THEN 'Social'
      WHEN medium = 'email' THEN 'Email'
      WHEN medium = 'referral' THEN 'Referral'
      WHEN medium = '(none)' OR medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    device_category,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, device_category
)

SELECT
  channel,
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / COUNT(*), 0) AS revenue_per_session,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, device_category
ORDER BY total_revenue DESC
```

結果のイメージは以下の通りです。

| channel | device_category | sessions | purchases | total_revenue | revenue_per_session | cvr |
|---------|----------------|----------|-----------|---------------|--------------------|----|
| Organic Search | desktop | 3,200 | 85 | 680,000 | 213 | 2.66 |
| Paid Search | mobile | 2,800 | 42 | 320,000 | 114 | 1.50 |
| Social | mobile | 1,900 | 15 | 95,000 | 50 | 0.79 |
| Direct | desktop | 1,500 | 38 | 450,000 | 300 | 2.53 |

---

## チャネル×地域のクロス集計SQL

地域（都道府県や国）との組み合わせも有用です。特定の地域からの特定チャネル流入が高い売上を生んでいるケースがあります。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN collected_traffic_source.manual_medium = '(none)'
        OR collected_traffic_source.manual_medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    geo.region AS region,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND geo.country = 'Japan'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    region,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, region
)

SELECT
  channel,
  region,
  COUNT(*) AS sessions,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / NULLIF(COUNT(*), 0), 0) AS revenue_per_session
FROM session_summary
GROUP BY channel, region
HAVING sessions >= 10
ORDER BY total_revenue DESC
```

---

## 時間帯×チャネルのクロス集計

曜日や時間帯との組み合わせも、広告配信の最適化に役立ちます。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      ELSE 'Other'
    END AS channel,
    -- 日本時間に変換
    EXTRACT(HOUR FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS hour_jst,
    EXTRACT(DAYOFWEEK FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS dow,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    -- 時間帯を4分割
    CASE
      WHEN hour_jst BETWEEN 6 AND 11 THEN '朝(6-11時)'
      WHEN hour_jst BETWEEN 12 AND 17 THEN '昼(12-17時)'
      WHEN hour_jst BETWEEN 18 AND 23 THEN '夜(18-23時)'
      ELSE '深夜(0-5時)'
    END AS time_slot,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, time_slot
)

SELECT
  channel,
  time_slot,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, time_slot
ORDER BY channel, time_slot
```

---

## Looker Studioでヒートマップを作成する

BigQueryの集計結果をLooker Studioに接続し、ヒートマップとして可視化する手順は以下の通りです。

### 1. データソースの接続

Looker Studioで新しいレポートを作成し、BigQueryをデータソースとして選択します。上記のSQLをカスタムクエリとして登録するか、BigQueryにビューとして保存しておくと便利です。

### 2. ピボットテーブルの作成

ヒートマップの代わりに、Looker Studioのピボットテーブルを使う方法が実用的です。

| 設定項目 | 値 |
|---------|-----|
| 行のディメンション | channel |
| 列のディメンション | device_category（またはtime_slot） |
| 指標 | revenue_per_session |
| 条件付き書式 | ヒートマップ（緑→赤のグラデーション） |

ピボットテーブルの条件付き書式機能を使えば、数値の大小に応じてセルの色が変わり、ヒートマップと同等の視覚効果が得られます。

### 3. フィルターの追加

日付範囲のフィルターを追加しておくと、月次での比較や季節変動の確認が容易になります。

---

## 分析から得られる施策

ヒートマップで見つかる典型的なパターンと施策例を紹介します。

| パターン | 意味 | 施策 |
|---------|------|------|
| Paid Search × desktopのrevenue_per_sessionが高い | デスクトップユーザーは高額購入の傾向 | PC向けの広告入札を引き上げる |
| Social × mobileのCVRが低い | SNS流入のモバイルユーザーが離脱している | モバイルLPの改善を検討する |
| Email × 夜のCVRが高い | メルマガは夜に読まれて購入される | メルマガ配信時間を夕方に変更する |
| Direct × desktopの売上が大きい | ブランド認知があるユーザーがデスクトップで購入 | ブランドキーワード広告で取りこぼしを防ぐ |

---

## まとめ

- チャネル×デバイス、チャネル×地域、チャネル×時間帯のクロス集計で、売上の集中ポイントが見える
- BigQueryでクロス集計を行い、Looker Studioのピボットテーブルでヒートマップ化する
- 売上の集中ポイントに対して広告予算やコンテンツを最適化することで、効率的な投資が可能になる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
