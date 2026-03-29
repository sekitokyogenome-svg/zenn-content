---
title: "BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】"
emoji: "🛒"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「GA4のeコマースデータをBigQueryでちゃんと分析したいのに、items配列のUNNESTがうまくいかない」「purchaseイベントから商品別の売上を出したいけど、クエリが複雑すぎて手が止まる」――こんな悩みを抱えているEC担当者やデータアナリストは多いのではないでしょうか。

GA4のeコマーストラッキングは、BigQueryにエクスポートすると**ネストされたRECORD型**として格納されます。通常のフラットなテーブルとは扱いが異なるため、SQLの書き方にコツが必要です。

本記事では、GA4のeコマースイベント（`view_item`、`add_to_cart`、`begin_checkout`、`purchase`）をBigQueryで分析するための実践的なSQLパターンを紹介します。ファネル分析やカゴ落ち分析など、EC運用で求められる定番の分析手法をカバーしています。

## GA4 eコマースイベントの全体像

GA4のeコマーストラッキングでは、ユーザーの購買プロセスに沿って以下のイベントが記録されます。

| イベント名 | 発火タイミング | 主な用途 |
|---|---|---|
| `view_item` | 商品詳細ページの表示 | 閲覧分析 |
| `add_to_cart` | カートに商品を追加 | カゴ落ち分析 |
| `begin_checkout` | チェックアウト開始 | 離脱ポイント分析 |
| `purchase` | 購入完了 | 売上・収益分析 |

これらのイベントには共通して**items配列**が含まれており、商品ID・商品名・カテゴリ・価格・数量などの情報が格納されます。

## BigQueryにおけるitems配列の構造

GA4のBigQueryエクスポートテーブル（`analytics_XXXXXX.events_*`）では、`items`カラムは**REPEATED RECORD型**（配列型）です。1つのイベントに複数の商品情報が紐づく構造になっています。

主なフィールドは以下の通りです。

| フィールド | 型 | 説明 |
|---|---|---|
| `items.item_id` | STRING | 商品ID |
| `items.item_name` | STRING | 商品名 |
| `items.item_category` | STRING | 商品カテゴリ（第1階層） |
| `items.item_category2` ~ `item_category5` | STRING | カテゴリ階層 |
| `items.price` | FLOAT | 商品単価 |
| `items.quantity` | INTEGER | 数量 |
| `items.item_revenue` | FLOAT | 商品売上（purchaseイベント時） |

:::message
items配列を展開するには`UNNEST`が必須です。`CROSS JOIN UNNEST(items)`または`,UNNEST(items)`の構文を使います。これを忘れると商品単位のデータにアクセスできません。
:::

## purchaseイベントから商品別売上を抽出するSQL

まずは基本となる、purchaseイベントのitems配列を展開して商品別の売上を取得するクエリです。

```sql
SELECT
  item.item_id,
  item.item_name,
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transaction_count,
  SUM(item.quantity) AS total_quantity,
  SUM(item.item_revenue) AS total_revenue
FROM
  `project.analytics_XXXXXX.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  item.item_id, item.item_name, item.item_category
ORDER BY
  total_revenue DESC
```

`ga_session_id`と組み合わせてセッション単位で分析する場合は、`event_params`からの抽出も必要です。

```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  user_pseudo_id,
  ecommerce.transaction_id,
  item.item_name,
  item.item_revenue
FROM
  `project.analytics_XXXXXX.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
```

## add_to_cart分析：カートに入れたが購入されなかった商品

EC運用で重要な「カゴ落ち分析」です。カートに追加されたが購入に至らなかった商品を特定します。

```sql
WITH cart_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id,
    item.item_name
  FROM
    `project.analytics_XXXXXX.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'add_to_cart'
),

purchased_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id
  FROM
    `project.analytics_XXXXXX.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'purchase'
)

SELECT
  c.item_id,
  c.item_name,
  COUNT(*) AS cart_add_count,
  COUNTIF(p.item_id IS NOT NULL) AS purchase_count,
  COUNTIF(p.item_id IS NULL) AS abandoned_count,
  ROUND(
    SAFE_DIVIDE(COUNTIF(p.item_id IS NULL), COUNT(*)) * 100, 1
  ) AS abandonment_rate
FROM
  cart_items c
LEFT JOIN
  purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.ga_session_id = p.ga_session_id
  AND c.item_id = p.item_id
GROUP BY
  c.item_id, c.item_name
ORDER BY
  abandoned_count DESC
```

:::message alert
`ga_session_id`は`event_params`のネスト内にあるため、`UNNEST(event_params)`でサブクエリ抽出する必要があります。直接`event_params.ga_session_id`のようには参照できません。
:::

## ファネル分析：view_item → add_to_cart → purchase の転換率

商品閲覧から購入までの各ステップのコンバージョン率を算出します。

```sql
WITH funnel AS (
  SELECT
    event_name,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      (SELECT CAST(value.int_value AS STRING) FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )) AS unique_sessions
  FROM
    `project.analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
  GROUP BY
    event_name
)

SELECT
  event_name,
  unique_sessions,
  ROUND(
    SAFE_DIVIDE(
      unique_sessions,
      MAX(unique_sessions) OVER ()
    ) * 100, 1
  ) AS rate_from_top
FROM funnel
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
  END
```

このクエリにより、たとえば以下のようなファネルが可視化できます。

| ステップ | セッション数 | ファネル上部からの率 |
|---|---|---|
| view_item | 50,000 | 100.0% |
| add_to_cart | 8,000 | 16.0% |
| begin_checkout | 4,500 | 9.0% |
| purchase | 2,000 | 4.0% |

## カテゴリ別・商品別の売上集計

`item_category`と`item_name`を使って売上を多角的に集計します。

```sql
-- カテゴリ別売上
SELECT
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  SUM(item.quantity) AS total_quantity,
  ROUND(SUM(item.item_revenue), 0) AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(item.item_revenue), SUM(item.quantity)), 0) AS avg_unit_price
FROM
  `project.analytics_XXXXXX.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
  AND item.item_category IS NOT NULL
GROUP BY
  item.item_category
ORDER BY
  total_revenue DESC
```

流入チャネル別に売上を分けたい場合は、`collected_traffic_source`を活用します。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  ROUND(SUM(ecommerce.purchase_revenue), 0) AS total_revenue
FROM
  `project.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
```

## よくあるミスと注意点

GA4のeコマースデータをBigQueryで扱う際に、つまずきやすいポイントをまとめます。

### 1. items配列のUNNESTを忘れる

`items`はREPEATED RECORD型です。`UNNEST`せずに`items.item_name`と書くとエラーになります。

```sql
-- NG: UNNESTなしでは参照できない
SELECT items.item_name FROM `project.analytics_XXXXXX.events_*`

-- OK: UNNESTで展開する
SELECT item.item_name
FROM `project.analytics_XXXXXX.events_*`, UNNEST(items) AS item
```

### 2. event_paramsのkey名を間違える

`ga_session_id`を取得するとき、keyの文字列を正しく指定しないとNULLが返ります。

```sql
-- NG: keyの名前が違う
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_id')

-- OK: 正しいkey名
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
```

### 3. ecommerce.purchase_revenueとitem.item_revenueの違い

- `ecommerce.purchase_revenue`：トランザクション全体の売上
- `item.item_revenue`：商品単位の売上

商品別に集計するなら`item.item_revenue`、トランザクション単位なら`ecommerce.purchase_revenue`を使い分けてください。

### 4. _TABLE_SUFFIXの指定漏れ

`events_*`のワイルドカードテーブルで`_TABLE_SUFFIX`を指定しないと、全期間のデータをスキャンしてしまい、コストが膨らみます。

## eコマーストラッキングの検証Tips

データ分析の前提として、GA4側のeコマーストラッキングが正しく実装されていることが重要です。

:::message
BigQuery上で以下のチェックを行うと、トラッキングの異常を早期に発見できます。
:::

- **items配列が空のpurchaseイベントがないか**：`WHERE event_name = 'purchase' AND ARRAY_LENGTH(items) = 0`で確認
- **item_revenueがNULLの商品がないか**：計測漏れの可能性あり
- **transaction_idの重複がないか**：同一トランザクションが二重計測されていないか確認
- **quantityが0や負の値になっていないか**：実装ミスの兆候
- **日次のpurchaseイベント数に急な増減がないか**：タグの欠落やサイト障害の検出に有効

```sql
-- トラッキング健全性チェック
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(*) AS purchase_events,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions,
  COUNTIF(ARRAY_LENGTH(items) = 0) AS empty_items_count,
  ROUND(AVG(ecommerce.purchase_revenue), 0) AS avg_revenue
FROM
  `project.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  date
```

## まとめ

| 分析テーマ | ポイント |
|---|---|
| 商品別売上 | `CROSS JOIN UNNEST(items)`でitems配列を展開 |
| カゴ落ち分析 | `add_to_cart`と`purchase`をセッション+商品IDでLEFT JOIN |
| ファネル分析 | イベント別のユニークセッション数を集計して転換率を算出 |
| カテゴリ別売上 | `item.item_category`でGROUP BY |
| チャネル別売上 | `collected_traffic_source.manual_medium`を活用 |
| トラッキング検証 | items配列の空チェック・transaction_id重複チェックを定期実施 |

GA4のeコマースデータは、BigQueryで適切にUNNESTして扱えば、GA4の管理画面では得られない柔軟な分析が可能になります。商品単位・カテゴリ単位・チャネル単位を自在に組み合わせて、ECサイトの改善に活かしてみてください。

---

GA4 × BigQueryの分析でお困りの方は、お気軽にご相談ください。
[ココナラで分析サポートを見る](https://coconala.com/services/1791205)
