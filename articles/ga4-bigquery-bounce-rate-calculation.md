---
title: "BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）"
emoji: "🚪"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: false
---

## はじめに

「GA4で直帰率を確認しようとしたら、UAのときと数値が全然違う」と感じていませんか？

GA4では、従来のUA（ユニバーサルアナリティクス）とは直帰の定義自体が変わりました。GA4には「エンゲージメント」という新しい概念が導入されており、直帰率の計算ロジックが根本的に異なります。

この記事では、GA4における直帰の定義を整理し、BigQueryで正確に直帰率を計算するSQLを解説します。

---

## UAとGA4で直帰率の定義が違う

### UA（ユニバーサルアナリティクス）の直帰率

UAでは「1ページだけ閲覧して離脱したセッション」を直帰としていました。

```text
直帰率 = 1ページのみのセッション数 / 全セッション数
```

### GA4の直帰率

GA4では「エンゲージメントがなかったセッション」を直帰としています。

```text
直帰率 = エンゲージメントがなかったセッション数 / 全セッション数
直帰率 = 1 - エンゲージメント率
```

---

## エンゲージメントセッションとは

GA4では、以下のいずれかの条件を満たすセッションを「エンゲージメントセッション」と定義しています。

1. **10秒以上の滞在**（デフォルト設定。管理画面で変更可能）
2. **2つ以上のページ閲覧（page_view）**
3. **コンバージョンイベントの発生**

これらのどれにも該当しないセッションが「直帰」です。つまりGA4の直帰は、UAの直帰よりも厳しい条件です。

:::message
GA4では1ページしか見ていなくても、10秒以上滞在すれば「直帰ではない」と判定されます。これがUAと数値が大きく異なる主な理由です。
:::

---

## BigQueryでエンゲージメント情報を取得する

GA4のBigQueryエクスポートデータでは、以下の `event_params` がエンゲージメント判定に関係します。

| パラメータ | 型 | 内容 |
|-----------|-----|------|
| `session_engaged` | string_value | "1" ならエンゲージセッション |
| `engagement_time_msec` | int_value | エンゲージメント時間（ミリ秒） |

`session_engaged` は、セッション内のいずれかのイベントで "1" が記録されます。

```sql
-- エンゲージメント情報の確認
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'session_engaged') AS session_engaged,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 20
```

---

## BigQueryで直帰率を計算するSQL

### 方法1：session_engagedを使う（推奨）

セッション単位で `session_engaged` の最大値を取り、"1" でないセッションを直帰とみなします。

```sql
WITH session_engagement AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(session_engaged != '1' OR session_engaged IS NULL) AS bounced_sessions,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_engagement
```

### 方法2：engagement_time_msecを使う

エンゲージメント時間で直接判定する方法です。10秒未満かつ1ページのみのセッションを直帰とします。

```sql
WITH session_metrics AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    SUM(
      IFNULL(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'engagement_time_msec'), 0)
    ) AS total_engagement_time_msec,
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(
    total_engagement_time_msec < 10000
    AND page_views <= 1
  ) AS bounced_sessions,
  ROUND(
    COUNTIF(
      total_engagement_time_msec < 10000
      AND page_views <= 1
    ) / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_metrics
```

:::message
方法1（`session_engaged`）はGA4の公式定義に最も近い計算です。方法2はカスタム条件で柔軟に定義を変えたい場合に有効です。
:::

---

## ページ別の直帰率を計算する

ランディングページごとの直帰率を出すことで、改善対象のページを特定できます。

```sql
WITH session_landing AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS landing_page,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, landing_page
)
SELECT
  landing_page,
  COUNT(*) AS sessions,
  COUNTIF(session_engaged != '1' OR session_engaged IS NULL) AS bounced,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_landing
GROUP BY landing_page
HAVING sessions >= 10
ORDER BY bounce_rate_percent DESC
LIMIT 20
```

`HAVING sessions >= 10` でサンプルの少ないページを除外しています。セッション数が少ないページの直帰率は統計的に不安定なためです。

---

## チャネル別の直帰率を比較する

流入元別に直帰率を比較すると、質の低いトラフィックを見つけられます。

```sql
WITH session_channel AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, medium
)
SELECT
  IFNULL(medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_channel
GROUP BY medium
ORDER BY sessions DESC
```

---

## UAの直帰率定義をBigQueryで再現する

UAからの移行期で、旧来の定義（1ページのみ＝直帰）で比較したいケースもあります。

```sql
WITH session_pages AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(page_views <= 1) AS single_page_sessions,
  ROUND(
    COUNTIF(page_views <= 1) / COUNT(*) * 100, 2
  ) AS ua_style_bounce_rate_percent
FROM session_pages
```

この値はGA4の直帰率よりも高くなる傾向があります。UAの定義ではエンゲージメント時間を考慮しないためです。

---

## まとめ

GA4の直帰率はUAとは定義が異なり、「エンゲージメントのなかったセッション」を直帰として扱います。
BigQueryでは `session_engaged` パラメータを使えば、GA4の公式定義に沿った直帰率を計算できます。
ページ別・チャネル別に分析することで、改善対象の特定に活用してください。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
