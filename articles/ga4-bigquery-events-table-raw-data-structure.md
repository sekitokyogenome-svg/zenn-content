---
title: "BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】"
emoji: "🗂️"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: false
---

## はじめに

GA4のデータをBigQueryにエクスポートしたものの、テーブルを開いてみて「カラムが多すぎて何から見ればいいかわからない」と感じていませんか？

GA4のBigQueryエクスポートは、1イベント1行のフラットなCSVではありません。`event_params` や `user_properties` といったネスト構造を含んでおり、従来のリレーショナルDBに慣れた方にとっては戸惑いやすいポイントです。

この記事では、GA4のBigQueryエクスポートテーブル `events_YYYYMMDD` の主要カラムを整理し、実際にデータを取り出すSQLまで解説します。

---

## eventsテーブルの全体像

GA4のBigQueryエクスポートでは、`analytics_XXXXXXXXX` データセットの中に日付別のテーブルが自動生成されます。

```text
analytics_263425816.events_20260101
analytics_263425816.events_20260102
analytics_263425816.events_20260103
...
```

各テーブルは同じスキーマで、1行が1イベント（page_view, session_start, purchase など）に対応します。

---

## 主要カラムの分類

eventsテーブルのカラムは、大きく以下のカテゴリに分けられます。

### イベント基本情報

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `event_date` | STRING | イベント発生日（YYYYMMDD形式） |
| `event_timestamp` | INTEGER | イベント発生時刻（マイクロ秒） |
| `event_name` | STRING | イベント名（page_view, purchase等） |
| `event_previous_timestamp` | INTEGER | 前回イベントのタイムスタンプ |

### ユーザー識別情報

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `user_pseudo_id` | STRING | クライアントID（ブラウザ単位の匿名ID） |
| `user_id` | STRING | 自社で設定したユーザーID（未設定ならNULL） |

### ネスト構造カラム（RECORD型）

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `event_params` | RECORD (REPEATED) | イベントパラメータの配列 |
| `user_properties` | RECORD (REPEATED) | ユーザープロパティの配列 |
| `items` | RECORD (REPEATED) | eコマース商品情報の配列 |

### デバイス・地域情報

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `device.category` | STRING | desktop / mobile / tablet |
| `device.mobile_brand_name` | STRING | 端末メーカー名 |
| `device.operating_system` | STRING | OS名 |
| `device.web_info.browser` | STRING | ブラウザ名 |
| `geo.country` | STRING | 国 |
| `geo.region` | STRING | 地域（都道府県等） |
| `geo.city` | STRING | 市区町村 |

### 流入元情報

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `collected_traffic_source.manual_source` | STRING | utm_source（流入元） |
| `collected_traffic_source.manual_medium` | STRING | utm_medium（メディア） |
| `collected_traffic_source.manual_campaign_name` | STRING | utm_campaign（キャンペーン名） |

:::message
`traffic_source.source` や `traffic_source.medium` は**ユーザーの初回流入時**の情報です。セッション単位の流入分析には `collected_traffic_source` を使ってください。この違いを知らないと、流入元の分析結果が大きくずれます。
:::

---

## event_paramsのUNNEST展開

`event_params` はキー・バリュー形式の配列です。中身を取り出すには `UNNEST` が必要です。

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'page_location') AS page_location,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'page_view'
LIMIT 100
```

`event_params` の値は型ごとに別フィールドに格納されています。

| フィールド | 対応する型 |
|-----------|-----------|
| `value.string_value` | 文字列（page_location, page_title等） |
| `value.int_value` | 整数（ga_session_id, engagement_time_msec等） |
| `value.double_value` | 小数（score等） |

---

## user_propertiesの展開

ユーザープロパティも同じくUNNESTで取り出します。

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(user_properties)
   WHERE key = 'membership_level') AS membership_level
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

:::message
`user_properties` はGA4の管理画面でカスタム設定した値が入ります。デフォルトでは空の場合が多いため、まずは `event_params` の理解を優先してください。
:::

---

## itemsの展開（eコマースの場合）

eコマースイベント（`add_to_cart`, `purchase`等）には `items` 配列が含まれます。

```sql
SELECT
  event_date,
  user_pseudo_id,
  items.item_id,
  items.item_name,
  items.item_category,
  items.price,
  items.quantity
FROM `beeracle.analytics_263425816.events_*`,
  UNNEST(items) AS items
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'purchase'
```

`items` は1イベントに複数商品が含まれるため、`UNNEST` すると行が展開されます。購入金額の合計を出すときは `SUM(items.price * items.quantity)` でGROUP BYと組み合わせてください。

---

## よく使うevent_paramsキーの一覧

GA4が自動で収集するパラメータのうち、分析で特に重要なものをまとめます。

| key | 型 | 内容 |
|-----|-----|------|
| `ga_session_id` | int_value | セッション識別子 |
| `ga_session_number` | int_value | ユーザーのセッション通番 |
| `page_location` | string_value | ページURL |
| `page_title` | string_value | ページタイトル |
| `page_referrer` | string_value | リファラーURL |
| `engagement_time_msec` | int_value | エンゲージメント時間（ミリ秒） |
| `session_engaged` | string_value | エンゲージセッションかどうか（"1" or NULL） |
| `entrances` | int_value | ランディングページかどうか（1 or NULL） |

---

## 日付フィルタの書き方

日付別テーブルの場合、`_TABLE_SUFFIX` で対象期間を絞ることがコスト管理の基本です。

```sql
-- 2026年3月のデータだけをスキャン
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
```

`_TABLE_SUFFIX` を使わないと、全期間のテーブルをスキャンしてしまい、クエリコストが不必要に膨らみます。

---

## まとめ

GA4のBigQueryエクスポートデータは、ネスト構造を理解すれば柔軟な分析が可能になります。まずは `event_params` のUNNEST展開に慣れることが第一歩です。主要カラムの構造を把握しておけば、セッション分析・ファネル分析・eコマース分析へとスムーズに進められます。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
