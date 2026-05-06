---
title: "GA4×BigQueryでリピーターと新規ユーザーを分離して分析する"
emoji: "👥"
type: "tech"
topics: ["bigquery", "googleanalytics", "dataanalytics"]
published: false
---

## はじめに

「新規ユーザーとリピーターで、どれくらい行動が違うのか？」

ECサイトの運営では、この問いへの答えが施策の方向性を大きく左右します。GA4の標準レポートでも新規/リピーターの分割は見られますが、購入率やページ別の行動まで深掘りするにはBigQueryが必要です。

この記事では、`first_visit` イベントと `user_pseudo_id` を使って、新規ユーザーとリピーターを正確に分類するSQLを解説します。

---

## GA4における新規ユーザーの定義

GA4では、ユーザーが初めてサイトを訪問すると `first_visit` イベントが記録されます。

| 項目 | 内容 |
|------|------|
| イベント名 | `first_visit` |
| 発火条件 | そのデバイス・ブラウザで初めてサイトを訪問したとき |
| 識別子 | `user_pseudo_id`（Cookieベース） |

注意すべき点として、GA4の「新規ユーザー」はCookieベースです。同じ人でもデバイスやブラウザが異なれば別のユーザーとして計測されます。この制約はBigQueryでも同じです。

---

## 新規/リピーターを分類するSQL

### 基本パターン：first_visitイベントの有無で判定

対象期間内に `first_visit` イベントがあるユーザーを「新規」、ないユーザーを「リピーター」とする方法です。

```sql
WITH user_type AS (
  SELECT
    user_pseudo_id,
    MAX(CASE WHEN event_name = 'first_visit' THEN 1 ELSE 0 END) AS is_new_user
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE WHEN is_new_user = 1 THEN '新規' ELSE 'リピーター' END AS user_type,
  COUNT(*) AS users
FROM user_type
GROUP BY user_type
```

:::message
この方法は「対象期間内に初めて訪問したかどうか」を判定しています。過去データを含めた厳密な判定が必要な場合は、後述する方法を使ってください。
:::

---

### 応用パターン：初回訪問日を特定して分類する

より正確な分類をするには、ユーザーの初回訪問日を全期間から特定し、分析対象期間と照合します。

```sql
WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

target_users AS (
  SELECT DISTINCT
    user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  COUNT(DISTINCT t.user_pseudo_id) AS users
FROM target_users t
LEFT JOIN first_visit_date f ON t.user_pseudo_id = f.user_pseudo_id
GROUP BY user_type
```

この方法では、2025年3月に初回訪問した人を「新規」、それ以前に訪問歴がある人を「リピーター」として分類しています。

---

## 新規/リピーター別のセッション指標を比較する

分類だけでなく、行動指標の比較まで行うのが実用的です。

```sql
WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    CASE
      WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
      THEN '新規'
      ELSE 'リピーター'
    END AS user_type,
    e.event_name
  FROM `beeracle.analytics_263425816.events_*` e
  LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  user_type,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    / COUNT(DISTINCT user_pseudo_id), 2
  ) AS sessions_per_user,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    ) * 100, 2
  ) AS purchase_rate_pct
FROM sessions
GROUP BY user_type
ORDER BY user_type
```

結果例：

| user_type | users | sessions | sessions_per_user | purchases | purchase_rate_pct |
|---|---|---|---|---|---|
| 新規 | 5,200 | 5,400 | 1.04 | 45 | 0.83 |
| リピーター | 1,800 | 4,200 | 2.33 | 120 | 2.86 |

リピーターの購入率が新規の3倍以上、というのはECではよくあるパターンです。

---

## 新規/リピーター別のチャネル分析

どのチャネルから新規が多く来ているか、リピーターはどのチャネルで戻ってくるかを把握します。

```sql
WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  IFNULL(e.collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(DISTINCT e.user_pseudo_id) AS users,
  COUNT(DISTINCT
    CONCAT(e.user_pseudo_id, '-',
    CAST((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions
FROM `beeracle.analytics_263425816.events_*` e
LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND e.event_name = 'session_start'
GROUP BY user_type, medium
ORDER BY user_type, sessions DESC
```

この結果から、「新規はOrganicが多いが、リピーターはDirectとEmailが多い」といった傾向が読み取れます。

---

## 注意点：Cookieベースの限界

BigQueryでの新規/リピーター分類は `user_pseudo_id`（Cookieベース）に依存しています。

- Cookie削除で同じ人が「新規」と判定される
- デバイスまたぎは別ユーザーとして扱われる
- Google Signalsを有効にしていても、BigQueryエクスポートには反映されない

この制約を踏まえた上で、「傾向を把握する」ための指標として活用するのが現実的です。

---

## まとめ

新規とリピーターでは行動パターンが大きく異なるため、分離して分析することで施策の精度が上がります。

自分としては、`first_visit` イベントだけで判定する簡易版から始めて、分析が深まってきたら初回訪問日ベースの厳密な方法に切り替えるのが良い進め方だと感じています。

皆さんのサイトでは、新規とリピーターの行動差はどれくらいありますか？コメントで共有いただけると参考になります。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
