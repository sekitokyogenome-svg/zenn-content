---
title: "GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する"
emoji: "🔎"
type: "tech"
topics: ["bigquery", "googleanalytics", "seo"]
published: true
---

## はじめに

GA4でオーガニック検索のパフォーマンスを分析しようとすると、「どのキーワードで流入しているか」がほぼ見えません。GA4のレポートではキーワードデータの大半が `(not provided)` になっているためです。

一方、Google Search Consoleにはキーワード（検索クエリ）ごとのクリック数やインプレッション数が蓄積されています。この2つのデータをBigQueryで結合すれば、「キーワード × ランディングページ × サイト内行動」を横断した分析が可能になります。

この記事では、Search ConsoleのBigQueryエクスポートとGA4データの結合方法を解説します。

---

## Search ConsoleのBigQueryエクスポートを設定する

Search Consoleのデータは、Search Console管理画面からBigQueryへエクスポートできます。

### 設定手順

1. Search Console管理画面 → 対象プロパティ →「設定」
2. 「一括データエクスポート」→「BigQuery」
3. GCPプロジェクトとデータセットを指定
4. エクスポートを有効化

エクスポートされるテーブル：

| テーブル | 内容 |
|---|---|
| `searchdata_site_impression` | サイト全体のインプレッション・クリックデータ |
| `searchdata_url_impression` | URL別のインプレッション・クリックデータ |

:::message
Search Consoleのデータは設定後、過去16ヶ月分がバックフィルされます。GA4とは異なり、エクスポート開始前のデータも取得可能です。
:::

---

## Search Consoleデータの構造を確認する

`searchdata_url_impression` テーブルの主要カラムです。

```sql
SELECT
  data_date,
  query,
  url,
  country,
  device,
  impressions,
  clicks,
  sum_position
FROM `beeracle.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
ORDER BY clicks DESC
LIMIT 20
```

| カラム | 内容 |
|---|---|
| `data_date` | データの日付 |
| `query` | 検索クエリ（キーワード） |
| `url` | 表示されたURL |
| `impressions` | 検索結果での表示回数 |
| `clicks` | クリック数 |
| `sum_position` | 掲載順位の合計（平均順位 = sum_position / impressions） |

---

## Search Console単体での分析

結合の前に、Search Console単体でのSEO分析クエリを紹介します。

### キーワード別パフォーマンス

```sql
SELECT
  query,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `beeracle.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND query IS NOT NULL
GROUP BY query
HAVING total_impressions >= 10
ORDER BY total_clicks DESC
LIMIT 30
```

### ランディングページ別パフォーマンス

```sql
SELECT
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position,
  COUNT(DISTINCT query) AS unique_queries
FROM `beeracle.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
GROUP BY page_path
ORDER BY total_clicks DESC
LIMIT 20
```

---

## GA4データとSearch Consoleデータを結合する

2つのデータソースをランディングページ（URL）と日付で結合します。

### 結合のためのGA4側の準備

GA4側でランディングページ別のセッション指標を集計します。

```sql
WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'page_view'
),

ga4_sessions AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM ga4_landing
  WHERE is_entrance = 1
  GROUP BY event_date, page_path
)

SELECT * FROM ga4_sessions
```

### GA4 × Search Console結合クエリ

```sql
WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
),

ga4_by_page AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CASE WHEN is_entrance = 1
      THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
    END) AS organic_sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM ga4_landing
  GROUP BY event_date, page_path
),

gsc AS (
  SELECT
    data_date AS event_date,
    REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
  FROM `beeracle.searchconsole.searchdata_url_impression`
  WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  GROUP BY event_date, page_path
)

SELECT
  COALESCE(ga.page_path, gsc.page_path) AS page_path,
  SUM(gsc.impressions) AS search_impressions,
  SUM(gsc.clicks) AS search_clicks,
  ROUND(SAFE_DIVIDE(SUM(gsc.clicks), SUM(gsc.impressions)) * 100, 2) AS ctr_pct,
  ROUND(AVG(gsc.avg_position), 1) AS avg_position,
  SUM(ga.organic_sessions) AS site_sessions,
  SUM(ga.purchases) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(ga.purchases), SUM(ga.organic_sessions)) * 100, 2) AS cvr_pct
FROM gsc
LEFT JOIN ga4_by_page ga
  ON gsc.event_date = ga.event_date
  AND gsc.page_path = ga.page_path
GROUP BY page_path
HAVING search_clicks >= 5
ORDER BY search_clicks DESC
LIMIT 30
```

この結果から、「検索でのクリック数は多いがCVRが低いページ」「検索順位が高いがCTRが低いページ」などの改善ポイントが見つかります。

---

## キーワード × ランディングページの分析

特定のランディングページに対して、どのキーワードが流入を生んでいるかを分析します。

```sql
SELECT
  query,
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `beeracle.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND url LIKE '%/blog/%'
  AND query IS NOT NULL
GROUP BY query, page_path
HAVING clicks >= 2
ORDER BY clicks DESC
LIMIT 50
```

---

## 結合時の注意点

### URLの正規化

GA4とSearch Consoleでは、同じページでもURLの形式が異なることがあります。

| ソース | URLの形式例 |
|---|---|
| GA4 (`page_location`) | `https://example.com/blog/post-1?utm_source=twitter` |
| Search Console (`url`) | `https://example.com/blog/post-1` |

結合前にクエリパラメータを除去する処理が必要です。

```sql
-- GA4側のURL正規化
REGEXP_EXTRACT(page_location, r'^(https?://[^?#]+)') AS clean_url

-- Search Console側のURL正規化
REGEXP_EXTRACT(url, r'^(https?://[^?#]+)') AS clean_url
```

### 日付のずれ

Search Consoleのデータは2〜3日遅れで確定します。リアルタイムの分析には向かないため、1週間以上前のデータを使う方が安定します。

:::message
Search Consoleのデータとga4のデータでは集計方法が異なるため、クリック数とセッション数が一致しないことがあります。Search Consoleの「クリック」はGoogle検索結果でのクリック、GA4の「セッション」はサイト側の計測です。この差異は正常です。
:::

---

## まとめ

GA4単体では見えない「検索キーワード」の情報を、Search ConsoleのBigQueryエクスポートと結合することで補完できます。

自分としては、「CTRが低いが掲載順位は高いページ」と「CVRが低いが検索流入が多いページ」の2軸で改善対象を見つけるのが、SEO施策の優先順位付けとして実用的だと感じています。

皆さんはSearch ConsoleのデータをBigQueryで活用していますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
