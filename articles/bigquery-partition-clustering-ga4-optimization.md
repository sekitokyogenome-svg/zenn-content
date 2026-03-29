---
title: "BigQueryのパーティション・クラスタリングでGA4クエリを高速化する"
emoji: "⚡"
type: "tech"
topics: ["bigquery", "googleanalytics", "performance"]
published: false
---

## はじめに

GA4のBigQueryエクスポートテーブルに対してクエリを実行すると、データ量が増えるにつれてスキャン量と課金額が膨らんでいきます。

「1クエリで数GB処理されている」「月末になるとコストが気になる」という状況は、パーティションとクラスタリングを適切に設定した集計テーブルを用意することで改善できます。

この記事では、GA4データに対するパーティションとクラスタリングの設計方針と、コスト削減の具体的な手法を解説します。

---

## GA4エクスポートテーブルの構造を理解する

GA4からBigQueryにエクスポートされるデータは、日付別のシャードテーブルとして保存されます。

```
analytics_263425816.events_20250301
analytics_263425816.events_20250302
analytics_263425816.events_20250303
...
```

クエリ時は `events_*` というワイルドカードテーブルを使い、`_TABLE_SUFFIX` で日付を絞ります。

```sql
SELECT COUNT(*) AS event_count
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
```

:::message
`_TABLE_SUFFIX` のフィルタを忘れると、全期間のデータがスキャンされます。GA4のエクスポートテーブルに対しては、`_TABLE_SUFFIX` の指定を習慣にしてください。
:::

---

## _TABLE_SUFFIXがパーティションの代わりになる

GA4のシャードテーブル（`events_YYYYMMDD`）は、日付でテーブルが分割されているため、`_TABLE_SUFFIX` で日付を絞ることで実質的にパーティショニングと同じ効果が得られます。

| 比較 | シャードテーブル（GA4デフォルト） | パーティションテーブル |
|---|---|---|
| テーブル構造 | 日付ごとに別テーブル | 1テーブル内で日付パーティション |
| 絞り込み方法 | `_TABLE_SUFFIX` | `WHERE event_date = ...` |
| スキャン量の削減 | 対象日のテーブルのみスキャン | 対象パーティションのみスキャン |
| 追加設定 | 不要（GA4がデフォルトで作成） | 自分でテーブルを作成する必要あり |

GA4のエクスポートテーブルをそのまま使う場合は、`_TABLE_SUFFIX` で日付を絞ることが最も基本的なコスト削減策です。

---

## 集計テーブルにパーティションを設定する

staging層やmart層に集計テーブルを作成する場合は、パーティションを設定することでクエリ効率が大きく改善します。

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category,
  geo.country AS country
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
```

### パーティションキーの選び方

| 候補 | 適性 | 理由 |
|---|---|---|
| `event_date` | 高 | 日付でフィルタするクエリが多い |
| `event_timestamp` | 中 | 時間単位の分析が必要な場合のみ |
| `user_pseudo_id` | 低 | カーディナリティが高すぎて効果が薄い |

GA4データの場合、`event_date` をパーティションキーにするのが最も汎用的です。

---

## クラスタリングキーの選定

クラスタリングは、パーティション内でデータをさらに物理的に整列させる仕組みです。最大4つのカラムを指定できます。

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category, country
AS
...
```

### クラスタリングキー選定のポイント

1. **WHERE句で頻繁に使うカラム**を優先する
2. **カーディナリティが中程度**のカラムが効果的（例：medium、device_category）
3. **指定順序が重要**：左から順にフィルタ効果が高い

| カラム | カーディナリティ | クラスタリング適性 |
|---|---|---|
| `session_medium` | 低〜中（10種程度） | 高 |
| `device_category` | 低（3種：desktop/mobile/tablet） | 高 |
| `country` | 中（数十種） | 中 |
| `page_location` | 高（数千種） | 低 |
| `user_pseudo_id` | 非常に高 | 低 |

---

## コスト削減効果を確認する

BigQueryではクエリ実行前にスキャン量の見積もりが表示されます。パーティション・クラスタリングの前後で比較してみましょう。

### 確認方法1：ドライランで比較

```sql
-- BigQueryコンソールで「ドライラン」を有効にして実行
-- パーティションなしテーブル
SELECT COUNT(*) FROM `beeracle.beeracle_mart.mart_daily_sessions_no_partition`
WHERE event_date BETWEEN '2025-03-01' AND '2025-03-07'
  AND session_medium = 'organic'

-- パーティション＋クラスタリングありテーブル
SELECT COUNT(*) FROM `beeracle.beeracle_mart.mart_daily_sessions`
WHERE event_date BETWEEN '2025-03-01' AND '2025-03-07'
  AND session_medium = 'organic'
```

### 確認方法2：INFORMATION_SCHEMAで確認

```sql
SELECT
  table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 3) AS size_gb,
  ROUND(total_physical_bytes / POW(1024, 3), 3) AS physical_size_gb
FROM `beeracle.beeracle_mart.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'mart_daily%'
```

:::message
クラスタリングの効果はデータ量が大きいほど顕著になります。数百MB以下のテーブルでは効果が限定的な場合があります。
:::

---

## 実践的な設計パターン

GA4データの集計テーブルで使いやすい設計パターンをまとめます。

### パターン1：セッション集計テーブル

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_mart.mart_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
```

### パターン2：ページビュー集計テーブル

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_mart.mart_page_views`
PARTITION BY event_date
CLUSTER BY page_path, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  REGEXP_EXTRACT(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
    r'^https?://[^/]+(/.*)') AS page_path,
  device.category AS device_category
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'page_view'
```

---

## コスト削減のためのその他のTips

パーティション・クラスタリング以外にもコスト削減に効果的な方法があります。

1. **SELECT * を避ける**：必要なカラムだけ指定する
2. **ビューよりマテリアライズドビュー**を検討する（クエリ結果をキャッシュ）
3. **スケジュールクエリで集計テーブルを事前作成**し、rawテーブルへの直接クエリを減らす
4. **BigQuery Sandboxの無料枠**（毎月1TBのクエリ処理）を活用する

---

## まとめ

GA4データをBigQueryで運用するなら、パーティションとクラスタリングの設計は避けて通れません。

自分としては、まず `_TABLE_SUFFIX` での日付絞り込みを徹底した上で、頻繁に使うクエリパターンに合わせた集計テーブルを作成し、そこにパーティション＋クラスタリングを設定するのが実務的なアプローチだと感じています。

皆さんはBigQueryのコスト管理、どのような工夫をしていますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
