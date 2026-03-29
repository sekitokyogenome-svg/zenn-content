---
title: "GA4×BigQueryでカスタムディメンションを活用した分析"
emoji: "🏷"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: false
---

## はじめに

GA4では、標準のイベントパラメータだけでは分析が足りないケースが多くあります。会員ランク、プラン種別、ABテストのバリアントなど、ビジネス固有の情報を分析に組み込むには「カスタムディメンション」の活用が不可欠です。

GA4の管理画面では登録したカスタムディメンションしかレポートに表示されませんが、BigQueryにはすべてのパラメータが生データとして入っています。

この記事では、BigQueryで `event_params` と `user_properties` からカスタムディメンションを取得し、分析に活用する方法を解説します。

---

## カスタムディメンションの2つの種類

GA4のカスタムディメンションは、スコープによって格納場所が異なります。

| スコープ | 格納場所 | 用途の例 |
|---|---|---|
| イベントスコープ | `event_params` | ボタンのバリアント、フォームのステップ |
| ユーザースコープ | `user_properties` | 会員ランク、プラン種別、登録日 |

BigQueryでは、どちらも `UNNEST` で展開して取得します。

---

## event_paramsからカスタムディメンションを取得する

イベントスコープのカスタムディメンションは `event_params` に格納されています。

### 基本的な取得パターン

```sql
SELECT
  event_name,
  event_timestamp,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'button_variant') AS button_variant,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'form_step') AS form_step
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'click'
```

:::message
カスタムディメンションの値は `string_value`、`int_value`、`float_value`、`double_value` のいずれかに格納されます。GTMでの設定時にどの型で送っているかを確認してから取得してください。
:::

### 値の型に応じた取得方法

```sql
-- 文字列型
(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'plan_type') AS plan_type

-- 整数型
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'item_count') AS item_count

-- 浮動小数点型
(SELECT value.float_value FROM UNNEST(event_params) WHERE key = 'scroll_depth') AS scroll_depth

-- double型
(SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'score') AS score
```

---

## user_propertiesからカスタムディメンションを取得する

ユーザースコープのカスタムディメンションは `user_properties` に格納されています。`event_params` と同じ `UNNEST` パターンで取得できます。

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'signup_method') AS signup_method
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'session_start'
```

### user_propertiesの注意点

- `user_properties` はイベントごとに記録されるため、同一ユーザーでもイベントごとに値が入っている
- 最新の値を取得したい場合は `set_timestamp_micros` を使って最新のものを選ぶ

```sql
WITH latest_properties AS (
  SELECT
    user_pseudo_id,
    prop.key AS property_key,
    prop.value.string_value AS property_value,
    prop.value.set_timestamp_micros AS set_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id, prop.key
      ORDER BY prop.value.set_timestamp_micros DESC
    ) AS rn
  FROM `beeracle.analytics_263425816.events_*`,
    UNNEST(user_properties) AS prop
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND prop.key = 'membership_tier'
)
SELECT
  user_pseudo_id,
  property_value AS membership_tier
FROM latest_properties
WHERE rn = 1
```

---

## 実践例1：ABテストのバリアント別コンバージョン分析

GTMで `ab_variant` というパラメータを送っている場合の分析例です。

```sql
WITH ab_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant') AS ab_variant,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  ab_variant,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr_pct
FROM ab_sessions
WHERE ab_variant IS NOT NULL
GROUP BY ab_variant
ORDER BY cvr_pct DESC
```

---

## 実践例2：会員ランク別の行動分析

`user_properties` に `membership_tier` を設定している場合の分析です。

```sql
WITH user_tier AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') IS NOT NULL
),

user_events AS (
  SELECT
    e.user_pseudo_id,
    t.membership_tier,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `beeracle.analytics_263425816.events_*` e
  INNER JOIN user_tier t ON e.user_pseudo_id = t.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  membership_tier,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'page_view') AS page_views,
  COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
  COUNTIF(event_name = 'purchase') AS purchases
FROM user_events
GROUP BY membership_tier
ORDER BY users DESC
```

---

## どのカスタムディメンションが入っているか確認する

BigQueryに入っているパラメータ一覧を確認するクエリです。新しいプロジェクトを引き継いだ際などに役立ちます。

### event_paramsのキー一覧

```sql
SELECT
  ep.key,
  COUNT(*) AS occurrences,
  COUNTIF(ep.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(ep.value.int_value IS NOT NULL) AS has_int,
  COUNTIF(ep.value.float_value IS NOT NULL) AS has_float
FROM `beeracle.analytics_263425816.events_*`,
  UNNEST(event_params) AS ep
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY ep.key
ORDER BY occurrences DESC
```

### user_propertiesのキー一覧

```sql
SELECT
  prop.key,
  COUNT(*) AS occurrences,
  COUNTIF(prop.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(prop.value.int_value IS NOT NULL) AS has_int
FROM `beeracle.analytics_263425816.events_*`,
  UNNEST(user_properties) AS prop
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY prop.key
ORDER BY occurrences DESC
```

:::message
1日分のデータに絞ることでスキャン量を最小限に抑えつつ、どのパラメータが入っているかを把握できます。
:::

---

## まとめ

カスタムディメンションを活用することで、ビジネス固有の切り口での分析が可能になります。`event_params` と `user_properties` の違いを理解し、`UNNEST` パターンを押さえておけば、GA4の標準レポートではできない深い分析ができます。

自分としては、まず「どのキーが入っているか」を確認するクエリを実行してから分析を設計するのが、手戻りが少ない進め方だと感じています。

皆さんはどのようなカスタムディメンションを設定していますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
