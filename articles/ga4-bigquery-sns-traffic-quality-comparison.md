---
title: "GA4×BigQueryでSNS流入の質を測定してInstagramとTikTokを比較した"
emoji: "📊"
type: "idea"
topics: ["bigquery", "googleanalytics", "sns"]
published: false
---

## はじめに

ECサイトの集客にSNSを活用している事業者は多いですが、「どのSNSからの流入が売上に貢献しているか」を正確に把握できているでしょうか。

InstagramとTikTokではユーザーの行動パターンがまったく異なります。TikTokは瞬間的なバズを生みやすい一方、Instagramはブランドへの親和性が高い傾向があります。しかし、GA4の標準レポートだけでは、SNSごとの流入品質を深く分析するのは困難です。

この記事では、BigQueryを使ってGA4の生データからSNS流入の品質指標を比較する方法を解説します。

---

## SNS流入を識別する仕組み

GA4では、`collected_traffic_source` フィールドにユーザーの流入元情報が記録されます。SNS経由の流入を正しく識別するには、`manual_source` と `manual_medium` を組み合わせて判定します。

| フィールド | 用途 |
|-----------|------|
| `collected_traffic_source.manual_source` | 流入元（instagram, tiktokなど） |
| `collected_traffic_source.manual_medium` | 流入メディア（social, cpcなど） |

UTMパラメータを正しく設定していれば、`manual_source` にSNS名が入ります。設定していない場合はGA4のデフォルト分類に依存するため、精度が下がる点に注意してください。

---

## セッション単位でSNS流入を集計するSQL

まず、セッションごとにSNS流入元を特定し、品質指標を算出します。

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
),

session_metrics AS (
  SELECT
    user_pseudo_id,
    session_id,
    source,
    -- セッション内のエンゲージメント時間合計（秒）
    SUM(engagement_time_msec) / 1000 AS engagement_sec,
    -- セッション内のページビュー数
    COUNTIF(event_name = 'page_view') AS page_views,
    -- 購入の有無
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    -- セッション開始・終了タイムスタンプ
    MIN(event_timestamp) AS session_start,
    MAX(event_timestamp) AS session_end
  FROM session_base
  GROUP BY user_pseudo_id, session_id, source
)

SELECT
  source,
  COUNT(*) AS sessions,
  ROUND(AVG(engagement_sec), 1) AS avg_engagement_sec,
  ROUND(AVG(page_views), 1) AS avg_page_views,
  -- 直帰率（ページビュー1以下のセッション割合）
  ROUND(COUNTIF(page_views <= 1) / COUNT(*) * 100, 1) AS bounce_rate,
  -- CV率
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_metrics
GROUP BY source
ORDER BY sessions DESC
```

このSQLで得られる結果のイメージは以下の通りです。

| source | sessions | avg_engagement_sec | avg_page_views | bounce_rate | cvr |
|--------|----------|--------------------|----------------|-------------|-----|
| instagram | 1,240 | 85.3 | 3.2 | 42.1 | 1.85 |
| tiktok | 2,890 | 32.7 | 1.8 | 68.4 | 0.42 |

---

## 結果から読み取れるSNSごとの流入特性

### TikTok流入の傾向

TikTokからの流入はセッション数が多い一方、エンゲージメント時間が短く直帰率が高い傾向があります。これは、TikTok上のショート動画を見て「なんとなく気になった」程度のモチベーションで訪問するユーザーが多いためと考えられます。

CVRが低いからといってTikTokが無価値というわけではありません。認知獲得のチャネルとして機能している可能性があるため、後述のアシストコンバージョン分析と組み合わせて評価する必要があります。

### Instagram流入の傾向

Instagramからの流入はセッション数こそ少ないものの、エンゲージメント時間が長く、ページを複数閲覧する傾向があります。ブランドの世界観に共感した上で訪問するユーザーが多いためと推測できます。

---

## SNS流入のアシストコンバージョンを確認する

直接CVに至らなくても、最初の接点としてSNSが機能しているケースがあります。以下のSQLで、SNS流入後に別経路でCVしたユーザーを抽出できます。

```sql
WITH sns_users AS (
  -- SNS経由で訪問したことがあるユーザー
  SELECT DISTINCT user_pseudo_id, collected_traffic_source.manual_source AS first_sns
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
    AND event_name = 'session_start'
),

purchasers AS (
  -- 購入したユーザー
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  s.first_sns,
  COUNT(DISTINCT s.user_pseudo_id) AS sns_visitors,
  COUNT(DISTINCT p.user_pseudo_id) AS eventual_purchasers,
  ROUND(COUNT(DISTINCT p.user_pseudo_id) / COUNT(DISTINCT s.user_pseudo_id) * 100, 2) AS eventual_cvr
FROM sns_users s
LEFT JOIN purchasers p ON s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.first_sns
ORDER BY sns_visitors DESC
```

この分析により、直接CVだけでは見えなかったSNSの「種まき効果」を数値化できます。

---

## 施策への活かし方

分析結果をもとに、SNSごとに異なるKPIを設定することが重要です。

| SNS | 主な役割 | 重視すべきKPI |
|-----|---------|--------------|
| Instagram | ブランド理解・直接CV | CVR、エンゲージメント時間 |
| TikTok | 認知獲得・集客 | セッション数、アシストCV |

すべてのSNSを同じCVR基準で評価すると、認知チャネルとして有効なTikTokを過小評価してしまうリスクがあります。チャネルの役割に応じた評価軸を持つことが、データドリブンなSNS運用の第一歩です。

---

## まとめ

- GA4の `collected_traffic_source` を使えば、SNSごとの流入品質をBigQueryで詳細に比較できる
- セッション品質指標（滞在時間、ページビュー数、直帰率、CVR）を組み合わせることで、各SNSの役割が明確になる
- 直接CVだけでなくアシストコンバージョンも含めた評価が、正しいSNS投資判断につながる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
