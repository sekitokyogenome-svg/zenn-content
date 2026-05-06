---
title: "GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googleanalytics", "marketing"]
published: false
---

## はじめに

マーケティング分析で「ユーザーが最初に来たチャネルはどこか」「コンバージョン直前のチャネルはどこか」を知りたい場面は多いです。

GA4の標準レポートでは「デフォルトチャネルグループ」しか見られず、ファーストタッチとラストタッチを比較する機能がありません。BigQueryにエクスポートしたデータを使えば、ウィンドウ関数で柔軟にアトリビューション分析ができます。

この記事では、`FIRST_VALUE` / `LAST_VALUE` を使ったファーストタッチ・ラストタッチの取得方法と、`collected_traffic_source` の活用について解説します。

---

## ファーストタッチ・ラストタッチとは

| アトリビューション | 意味 | 活用場面 |
|---|---|---|
| ファーストタッチ | ユーザーが最初にサイトを訪問した際の流入元 | 認知チャネルの評価 |
| ラストタッチ | コンバージョン直前の訪問時の流入元 | 刈り取りチャネルの評価 |

たとえば、「最初はブログ記事（Organic Search）で知って、最終的にリスティング広告（Paid Search）で購入した」というユーザーの場合、ファーストタッチはOrganic Search、ラストタッチはPaid Searchになります。

---

## collected_traffic_sourceを理解する

GA4のBigQueryエクスポートには、流入元を取得できるフィールドが複数あります。

| フィールド | 内容 | 注意点 |
|---|---|---|
| `traffic_source.source` | ユーザーの初回流入元 | 初回のみ。変わらない |
| `traffic_source.medium` | ユーザーの初回メディア | 初回のみ。変わらない |
| `collected_traffic_source.manual_source` | そのセッションの流入元 | セッションごとに変わる |
| `collected_traffic_source.manual_medium` | そのセッションのメディア | セッションごとに変わる |

:::message
`traffic_source` はユーザーの「初回流入」情報のみを保持しています。セッションごとの流入元を取得するには `collected_traffic_source.manual_source` / `collected_traffic_source.manual_medium` を使います。`traffic_source.medium` をセッション単位の分析に使うと、すべてのセッションで同じ値が返ってしまうので注意してください。
:::

---

## ファーストタッチを取得するSQL

`FIRST_VALUE` ウィンドウ関数を使って、ユーザーごとの最初の流入元を取得します。

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
),

first_touch AS (
  SELECT DISTINCT
    user_pseudo_id,
    FIRST_VALUE(session_source) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_source,
    FIRST_VALUE(session_medium) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_medium
  FROM sessions
  WHERE session_source IS NOT NULL
)

SELECT
  IFNULL(first_touch_source, '(direct)') AS first_touch_source,
  IFNULL(first_touch_medium, '(none)') AS first_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM first_touch
GROUP BY first_touch_source, first_touch_medium
ORDER BY users DESC
LIMIT 20
```

### ポイント

- `session_start` イベントに絞ることで、セッションの開始時点の流入元を取得しています
- `FIRST_VALUE` の `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` で、パーティション内の最初の値を取得しています
- `collected_traffic_source.manual_source` が `NULL` のケースは `(direct)` として扱います

---

## ラストタッチを取得するSQL

`LAST_VALUE` を使って、コンバージョン直前の流入元を取得します。

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source IS NOT NULL
),

converters AS (
  SELECT DISTINCT
    user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
),

last_touch AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    LAST_VALUE(s.session_source) OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_touch_source,
    LAST_VALUE(s.session_medium) OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_touch_medium
  FROM sessions s
  INNER JOIN converters c ON s.user_pseudo_id = c.user_pseudo_id
)

SELECT
  last_touch_source,
  last_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS converting_users
FROM last_touch
GROUP BY last_touch_source, last_touch_medium
ORDER BY converting_users DESC
LIMIT 20
```

:::message
`LAST_VALUE` を使う際は `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` を指定しないと、デフォルトのウィンドウフレーム（RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW）が適用され、意図した結果にならないことがあります。
:::

---

## ファーストタッチとラストタッチを並べて比較する

実務では両方を並べて、チャネルの役割を把握するのが有用です。

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source IS NOT NULL
),

converters AS (
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
),

attribution AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    FIRST_VALUE(s.session_source) OVER w AS first_touch_source,
    FIRST_VALUE(s.session_medium) OVER w AS first_touch_medium,
    LAST_VALUE(s.session_source) OVER w AS last_touch_source,
    LAST_VALUE(s.session_medium) OVER w AS last_touch_medium
  FROM sessions s
  INNER JOIN converters c ON s.user_pseudo_id = c.user_pseudo_id
  WINDOW w AS (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.event_timestamp
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  )
)

SELECT
  first_touch_source,
  first_touch_medium,
  last_touch_source,
  last_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS converting_users
FROM attribution
GROUP BY 1, 2, 3, 4
ORDER BY converting_users DESC
LIMIT 30
```

この結果を見ると、「Organic Searchで認知されて、Directで購入する」パターンが多い、といったチャネル間の連携が見えてきます。

---

## traffic_sourceとcollected_traffic_sourceの使い分け

最後に、フィールドの使い分けをまとめます。

| やりたいこと | 使うフィールド |
|---|---|
| ユーザーの初回流入元を知りたい | `traffic_source.source` / `traffic_source.medium` |
| セッションごとの流入元を知りたい | `collected_traffic_source.manual_source` / `collected_traffic_source.manual_medium` |
| ファーストタッチの流入元 | `FIRST_VALUE` + `collected_traffic_source` |
| ラストタッチの流入元 | `LAST_VALUE` + `collected_traffic_source` |

`traffic_source` はユーザーレベルの初回情報なので、ファーストタッチの簡易的な代替として使えます。ただし、セッション単位の分析やラストタッチの取得には `collected_traffic_source` を使う必要があります。

---

## まとめ

ファーストタッチとラストタッチを比較することで、「認知に貢献しているチャネル」と「刈り取りに貢献しているチャネル」を切り分けて評価できるようになります。

自分としては、まずこの2つを並べるだけでも広告予算の配分に対する解像度がかなり上がると感じています。

GA4のアトリビューション分析、皆さんはどのモデルを使っていますか？コメントで共有いただけると参考になります。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
