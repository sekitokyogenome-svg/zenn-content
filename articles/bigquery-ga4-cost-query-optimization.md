---
title: "BigQueryでGA4データのコスト管理・クエリ最適化入門"
emoji: "💰"
type: "tech"
topics: ["bigquery", "googleanalytics", "cost"]
published: false
---

## はじめに

BigQueryでGA4データの分析を始めたものの、「請求額が思ったより高い」「クエリのスキャン量が大きすぎる」と不安を感じていませんか？

BigQueryは従量課金制（オンデマンド）の場合、クエリがスキャンしたデータ量に応じて課金されます。GA4のBigQueryエクスポートデータは1日あたり数十MB〜数GBになることもあり、無意識にクエリを実行すると月額が予想外に膨らむことがあります。

この記事では、BigQuery×GA4のコスト構造を理解し、実務で使えるクエリ最適化テクニックを解説します。

---

## BigQueryの料金体系を理解する

BigQueryの主なコストは2つです。

| 種類 | 内容 | 料金（東京リージョン） |
|------|------|----------------------|
| ストレージ | 保存しているデータ量 | 約$0.023/GB/月（アクティブ） |
| クエリ | スキャンしたデータ量 | $6.25/TB（オンデマンド） |

GA4のデータを1年分蓄積した場合のストレージコストは、サイト規模によりますが月数百円程度です。コストの大部分はクエリ（分析時のスキャン量）で発生します。

:::message
BigQueryには毎月1TBの無料クエリ枠があります。個人サイトや中小規模のECであれば、この枠内で十分に分析できるケースも多いです。
:::

---

## コストが膨らむ典型パターン

### パターン1：_TABLE_SUFFIXを使わない

```sql
-- 悪い例：全期間のテーブルをスキャン
SELECT event_date, COUNT(*) AS events
FROM `beeracle.analytics_263425816.events_*`
GROUP BY event_date
ORDER BY event_date
```

`_TABLE_SUFFIX` で期間を指定しないと、エクスポート開始日から現在まで全テーブルをスキャンします。1年分のデータがあれば、365テーブル分の課金が発生します。

```sql
-- 良い例：必要な期間だけスキャン
SELECT event_date, COUNT(*) AS events
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
```

### パターン2：SELECT * を使う

```sql
-- 悪い例：全カラムをスキャン
SELECT *
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
```

BigQueryはカラム指向ストレージです。`SELECT *` は使わないカラムも含めてスキャンするため、コストが数倍に膨れます。

```sql
-- 良い例：必要なカラムだけ指定
SELECT event_date, event_name, user_pseudo_id
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
```

### パターン3：同じクエリを何度も実行する

開発中にSQLを微修正しながら繰り返し実行すると、そのたびにスキャンが発生します。

---

## クエリ最適化テクニック

### テクニック1：_TABLE_SUFFIXで期間を絞る

最も効果が大きい最適化です。分析対象の期間を限定してスキャン量を削減します。

```sql
-- 直近7日間だけスキャン
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
  AND FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
```

### テクニック2：必要なカラムだけSELECTする

GA4のeventsテーブルには数十カラムあります。使わないカラムは指定しないでください。

```sql
-- event_paramsのサブクエリも、必要なキーだけ取り出す
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX = '20260330'
```

### テクニック3：中間テーブルやビューを活用する

頻繁に使うクエリは、結果をテーブルとして保存することでスキャンの重複を防げます。

```sql
-- 中間テーブルとして保存
CREATE OR REPLACE TABLE `beeracle.beeracle_staging.sessions_202603` AS
SELECT
  event_date,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

以降は `sessions_202603` テーブルに対してクエリすれば、生データの再スキャンが不要です。

:::message
中間テーブルにはストレージコストがかかりますが、クエリコストの削減効果のほうが大きいケースがほとんどです。90日以上更新されないテーブルは長期保存ストレージに移行し、料金が半額になります。
:::

### テクニック4：ドライランで事前にスキャン量を確認する

BigQueryコンソールでは、クエリを実行する前にスキャン量の見積もりが右上に表示されます。API経由の場合は `--dry_run` フラグを使います。

```sql
-- bqコマンドでドライラン
-- bq query --dry_run --use_legacy_sql=false 'SELECT ...'
```

実行前にスキャン量を確認する習慣をつけると、想定外の課金を防げます。

---

## パーティションとクラスタリング

GA4のエクスポートテーブルは日付別テーブル（シャーディング）ですが、自分で作成する中間テーブルにはパーティションとクラスタリングを設定できます。

### パーティション

テーブルを特定のカラム（通常は日付）で物理的に分割します。クエリ時にパーティションフィルタを使えば、該当パーティションだけがスキャンされます。

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_staging.sessions_partitioned`
PARTITION BY event_date_parsed
CLUSTER BY medium
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date_parsed,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260330'
  AND event_name = 'session_start'
```

### クラスタリング

パーティション内のデータを特定のカラムでソートして格納します。そのカラムでフィルタするクエリのスキャン量が削減されます。

上の例では `medium` でクラスタリングしているため、`WHERE medium = 'organic'` のようなクエリが効率化されます。

---

## 月額コストの見積もり方

以下の手順でおおよその月額コストを見積もれます。

1. **1日のデータ量を確認する**

```sql
SELECT
  _TABLE_SUFFIX AS table_date,
  COUNT(*) AS row_count,
  SUM(OCTET_LENGTH(TO_JSON_STRING(t))) / 1024 / 1024 AS approx_mb
FROM `beeracle.analytics_263425816.events_*` t
WHERE _TABLE_SUFFIX = '20260330'
GROUP BY table_date
```

2. **月間スキャン量を推定する**
   - 1日あたりのテーブルサイズ × 分析で使う日数 × 1日の実行回数
   - 例：100MB/日 × 30日 × 5回 = 15GB/月

3. **料金を計算する**
   - 15GB × $6.25/TB = 約$0.09/月（約15円）
   - 無料枠1TB/月で十分カバーできる範囲

---

## コスト管理のベストプラクティス

| 対策 | 効果 |
|------|------|
| `_TABLE_SUFFIX` で期間を絞る | スキャン量を大幅削減 |
| `SELECT *` を避ける | 不要なカラムスキャンを防止 |
| 中間テーブルを活用する | 同じデータの再スキャンを防止 |
| ドライランで事前確認 | 想定外の課金を防止 |
| BigQueryのカスタムコストコントロールを設定 | 月額上限を設定して超過を防止 |
| スケジュールクエリの実行頻度を最適化 | 不要な定期実行を削減 |

---

## まとめ

BigQuery×GA4のコスト管理は、`_TABLE_SUFFIX` による期間絞り込みと `SELECT *` の回避が基本です。中間テーブルの活用やパーティション設定を組み合わせることで、分析の自由度を保ちながらコストを抑えられます。月1TBの無料枠を意識すれば、中小規模のサイトであれば実質無料で運用できるケースも多いです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
