---
title: "Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする"
emoji: "🎨"
type: "tech"
topics: ["bigquery", "googleanalytics", "metaads"]
published: false
---

## はじめに

Meta広告（Facebook/Instagram広告）を運用していると、「どのクリエイティブが実際に売上につながっているのか」を正確に把握したくなります。Meta広告マネージャーでもROASは確認できますが、計測はMeta独自のアトリビューションに基づいているため、GA4のデータと照合すると数値にズレが出ることが珍しくありません。

自分が支援していた某美容系ECでは、Meta広告マネージャー上のROASが4.0だったクリエイティブが、GA4×BigQueryベースで再計算すると2.3だった、というケースがありました。この差を無視して予算配分していたら、利益が出ていないクリエイティブに広告費を投下し続けることになっていたかもしれません。

本記事では、UTMパラメータを使ったクリエイティブの識別方法と、GA4×BigQueryでクリエイティブ別ROASを算出するSQLを紹介します。

---

## UTMパラメータ設計

Meta広告のクリエイティブをGA4側で識別するには、UTMパラメータの設計が重要です。Meta広告マネージャーの「URLパラメータ」設定で、以下のように設定します。

```text
utm_source=facebook
&utm_medium=paid_social
&utm_campaign={{campaign.name}}
&utm_content={{ad.name}}
```

`utm_content` にクリエイティブ名（広告名）を入れるのがポイントです。`{{ad.name}}` はMetaの動的パラメータで、広告名が自動挿入されます。

:::message
広告名には命名規則を設けましょう。例えば「2026Q1_skincare_video_01」のように、期間・商品カテゴリ・フォーマット・番号を含めると、後のBigQuery分析が格段にやりやすくなります。
:::

### 命名規則の例

| 要素 | 例 | 説明 |
|------|-----|------|
| 期間 | 2026Q1 | 四半期単位 |
| 商品カテゴリ | skincare | 対象商品ジャンル |
| フォーマット | video / static / carousel | クリエイティブ形式 |
| 番号 | 01, 02... | バリエーション |

---

## GA4×BigQueryでUTMパラメータを取得するSQL

GA4のBigQueryデータから `utm_content`（クリエイティブ識別子）を抽出します。

```sql
WITH ad_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS content,
    event_name,
    event_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  campaign,
  content AS creative_name,
  event_date
FROM ad_sessions
WHERE content IS NOT NULL;
```

`collected_traffic_source.manual_source` と `collected_traffic_source.manual_medium` でMeta広告経由のセッションに絞り込み、`content` パラメータからクリエイティブ名を取得しています。

---

## クリエイティブ別ROASを算出するSQL

セッションデータと購買データを結合して、クリエイティブ別のROASを算出します。

```sql
WITH meta_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS creative_name,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
),
session_summary AS (
  SELECT
    creative_name,
    campaign,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase' THEN revenue ELSE 0 END) AS total_revenue
  FROM meta_sessions
  WHERE creative_name IS NOT NULL
  GROUP BY creative_name, campaign
)
SELECT
  creative_name,
  campaign,
  sessions,
  purchases,
  total_revenue,
  ROUND(SAFE_DIVIDE(purchases, sessions) * 100, 2) AS cvr,
  ROUND(SAFE_DIVIDE(total_revenue, sessions), 0) AS revenue_per_session
FROM session_summary
ORDER BY total_revenue DESC;
```

ここで算出しているのはGA4ベースの売上データです。ROAS（Return on Ad Spend）を正確に出すには、Meta広告マネージャーからクリエイティブ別の広告費データを取得して結合する必要があります。

---

## 広告費データとの結合

Meta広告の費用データはMeta Marketing APIまたはCSVエクスポートで取得し、BigQueryにインポートします。

```sql
WITH ga4_revenue AS (
  -- 前述のクエリ結果
  SELECT
    creative_name,
    total_revenue,
    sessions,
    purchases
  FROM session_summary
),
meta_cost AS (
  -- Meta広告費用テーブル（API or CSVインポート）
  SELECT
    ad_name AS creative_name,
    SUM(spend) AS total_spend,
    SUM(impressions) AS total_impressions,
    SUM(clicks) AS total_clicks
  FROM `project.dataset.meta_ads_cost`
  WHERE date BETWEEN '2026-03-01' AND '2026-03-31'
  GROUP BY ad_name
)
SELECT
  g.creative_name,
  g.sessions,
  g.purchases,
  g.total_revenue,
  m.total_spend,
  m.total_clicks,
  ROUND(SAFE_DIVIDE(g.total_revenue, m.total_spend), 2) AS roas,
  ROUND(SAFE_DIVIDE(m.total_spend, g.purchases), 0) AS cpa
FROM ga4_revenue g
JOIN meta_cost m
  ON g.creative_name = m.creative_name
ORDER BY roas DESC;
```

:::message
Meta広告マネージャーとGA4のクリエイティブ名（広告名）を一致させることが、この結合の前提条件です。命名規則が揃っていないと結合に失敗するため、運用ルールの整備が先決です。
:::

---

## 某EC案件での分析結果

某美容系ECで3月のクリエイティブ別ROAS分析を実施した結果です。

| クリエイティブ | セッション数 | CV数 | 売上 | 広告費 | ROAS（GA4基準） |
|---------------|------------|------|------|--------|---------------|
| skincare_video_01 | 1,240 | 38 | 285,000円 | 82,000円 | 3.48 |
| skincare_static_02 | 890 | 22 | 176,000円 | 65,000円 | 2.71 |
| skincare_carousel_01 | 1,580 | 18 | 132,000円 | 95,000円 | 1.39 |
| skincare_video_02 | 420 | 15 | 118,000円 | 35,000円 | 3.37 |

カルーセル形式のクリエイティブはクリック数（セッション数）は多いものの、CVRが低くROASも低い結果でした。一方、動画クリエイティブはセッション数あたりのCV率が高く、ROAS的には良好でした。

Meta広告マネージャー上では、カルーセルのROASは2.8と表示されていました。GA4ベースの1.39とは大きな乖離があり、Metaのビュースルーコンバージョンが数値を押し上げていたことが原因と考えられます。

---

## フォーマット別の傾向分析

クリエイティブのフォーマット（動画/静止画/カルーセル）別に集計することで、どのフォーマットに予算を寄せるべきかが見えてきます。

```sql
SELECT
  CASE
    WHEN creative_name LIKE '%video%' THEN 'video'
    WHEN creative_name LIKE '%static%' THEN 'static'
    WHEN creative_name LIKE '%carousel%' THEN 'carousel'
    ELSE 'other'
  END AS format_type,
  SUM(sessions) AS total_sessions,
  SUM(purchases) AS total_purchases,
  SUM(total_revenue) AS total_revenue,
  SUM(total_spend) AS total_spend,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(total_spend)), 2) AS roas
FROM creative_performance
GROUP BY format_type
ORDER BY roas DESC;
```

命名規則でフォーマットを識別できるようにしておくと、こうした横断的な分析がSQLだけで完結します。

---

## まとめ

Meta広告のクリエイティブ別ROAS分析は、「Meta広告マネージャーの数値だけでは判断しきれない」という前提に立つことが出発点です。GA4×BigQueryで再計算することで、より実態に近い収益性が見えてきます。

自分としては、Meta広告のROASは広告プラットフォーム側の計測を鵜呑みにせず、GA4のデータで検算する習慣をつけるのが良いと感じています。とくにクリエイティブの入れ替え判断に関わる数値なので、正確性にはこだわりたいところです。

皆さんは、Meta広告のクリエイティブ評価にGA4のデータをどの程度活用していますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
