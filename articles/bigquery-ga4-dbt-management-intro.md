---
title: "BigQueryでGA4データをdbtで管理する入門"
emoji: "🔧"
type: "tech"
topics: ["bigquery", "dbt", "dataengineering"]
published: false
---

## はじめに

GA4のデータをBigQueryに連携して分析を始めると、SQLファイルが増え、どのクエリがどのテーブルに依存しているかが分かりにくくなってきます。

「このビューを変更したら、あのダッシュボードが壊れた」「SQLが属人化して自分以外触れない」という状況は、dbt（data build tool）を導入することで解消できます。

この記事では、GA4データをBigQueryで運用する際のdbtの基本的な使い方と、staging / martモデルの構成について解説します。

---

## dbtとは

dbtは、SQLベースでデータ変換パイプラインを管理するツールです。

| 特徴 | 内容 |
|------|------|
| SQLで完結 | Python不要。SELECT文を書くだけでテーブル/ビューを生成 |
| 依存関係の管理 | `ref()` 関数でモデル間の依存を自動追跡 |
| テスト機能 | NULLチェック、ユニーク性チェックなどをYAMLで定義 |
| ドキュメント生成 | モデルの説明・依存グラフを自動生成 |
| CI/CD対応 | Git連携でPR時に自動テスト実行 |

:::message
dbtには「dbt Core」（OSS / CLI）と「dbt Cloud」（SaaS）があります。この記事ではdbt Coreを使った方法を解説します。個人や小規模チームではdbt Coreで十分対応できます。
:::

---

## dbtのセットアップ

### インストール

```bash
pip install dbt-bigquery
```

### プロジェクト初期化

```bash
dbt init ga4_analytics
cd ga4_analytics
```

### profiles.ymlの設定

`~/.dbt/profiles.yml` にBigQueryへの接続情報を記載します。

```yaml
ga4_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: beeracle
      dataset: beeracle_staging
      location: asia-northeast1
      threads: 4
```

:::message
認証方法は `oauth`（ブラウザ認証）か `service-account`（JSONキー）を選択できます。ローカル開発では `oauth` が手軽です。
:::

---

## ディレクトリ構成

GA4データの3層設計に合わせたdbtのディレクトリ構成です。

```
ga4_analytics/
├── dbt_project.yml
├── models/
│   ├── staging/
│   │   ├── _staging_sources.yml
│   │   ├── stg_events.sql
│   │   ├── stg_sessions.sql
│   │   └── stg_purchases.sql
│   ├── mart/
│   │   ├── mart_traffic.sql
│   │   ├── mart_funnel.sql
│   │   └── mart_cohort.sql
│   └── schema.yml
├── tests/
└── macros/
```

---

## stagingモデルの作成

### ソース定義（_staging_sources.yml）

まず、GA4のエクスポートテーブルをdbtの「ソース」として定義します。

```yaml
version: 2

sources:
  - name: ga4_raw
    database: beeracle
    schema: analytics_263425816
    tables:
      - name: events
        identifier: "events_*"
        description: "GA4のイベント生データ（日付シャードテーブル）"
```

### stg_events.sql

イベントの生データをフラット化するstagingモデルです。

```sql
-- models/staging/stg_events.sql

{{ config(materialized='view') }}

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  collected_traffic_source.manual_source AS session_source,
  collected_traffic_source.manual_medium AS session_medium,
  device.category AS device_category,
  geo.country AS country
FROM {{ source('ga4_raw', 'events') }}
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
```

### stg_sessions.sql

セッション単位に集約するstagingモデルです。

```sql
-- models/staging/stg_sessions.sql

{{ config(materialized='view') }}

WITH events AS (
  SELECT * FROM {{ ref('stg_events') }}
)

SELECT
  user_pseudo_id,
  ga_session_id,
  MIN(event_date) AS session_date,
  MIN(event_timestamp) AS session_start_timestamp,
  session_source,
  session_medium,
  device_category,
  country,
  COUNTIF(event_name = 'page_view') AS page_views,
  SUM(COALESCE(engagement_time_msec, 0)) AS total_engagement_msec,
  MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
FROM events
GROUP BY
  user_pseudo_id,
  ga_session_id,
  session_source,
  session_medium,
  device_category,
  country
```

ここで `{{ ref('stg_events') }}` を使うことで、dbtが依存関係を自動で認識します。

---

## martモデルの作成

### mart_traffic.sql

日別×チャネル別のトラフィック集計です。

```sql
-- models/mart/mart_traffic.sql

{{ config(materialized='table') }}

WITH sessions AS (
  SELECT * FROM {{ ref('stg_sessions') }}
)

SELECT
  session_date AS event_date,
  IFNULL(session_medium, '(none)') AS medium,
  device_category,
  COUNT(*) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  SUM(page_views) AS page_views,
  ROUND(AVG(total_engagement_msec) / 1000, 1) AS avg_engagement_sec,
  SUM(has_purchase) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_pct
FROM sessions
GROUP BY event_date, medium, device_category
```

:::message
stagingモデルは `materialized='view'`（ビュー）、martモデルは `materialized='table'`（テーブル）にするのが一般的です。martはダッシュボードから参照されるため、テーブルにすることでクエリ速度が安定します。
:::

---

## ref()による依存管理のメリット

dbtの `ref()` 関数を使うと、以下のメリットがあります。

1. **依存グラフの自動生成**：`dbt docs generate` でDAG（有向非巡回グラフ）が可視化される
2. **実行順序の自動制御**：`dbt run` で依存順にモデルが実行される
3. **環境の切り替え**：dev / prod でデータセットを切り替えても `ref()` は追従する

```
stg_events → stg_sessions → mart_traffic
                           → mart_funnel
                           → mart_cohort
```

この依存関係を手作業で管理していた場合と比べて、変更の影響範囲が一目でわかります。

---

## テストの設定

`schema.yml` にテスト定義を追加します。

```yaml
version: 2

models:
  - name: stg_sessions
    description: "セッション単位に集約したGA4データ"
    columns:
      - name: user_pseudo_id
        tests:
          - not_null
      - name: ga_session_id
        tests:
          - not_null
      - name: session_date
        tests:
          - not_null

  - name: mart_traffic
    description: "日別×チャネル別のトラフィック集計"
    columns:
      - name: event_date
        tests:
          - not_null
      - name: sessions
        tests:
          - not_null
```

テスト実行：

```bash
dbt test
```

---

## CI/CDへの組み込み

GitHub Actionsでdbtのテストを自動実行する例です。

```yaml
# .github/workflows/dbt-ci.yml
name: dbt CI

on:
  pull_request:
    paths:
      - 'models/**'
      - 'tests/**'

jobs:
  dbt-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install dbt-bigquery
      - run: dbt deps
      - run: dbt compile
      - run: dbt test
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY_PATH }}
```

PRにモデル変更が含まれる場合に自動テストが走るため、壊れた状態でのデプロイを防げます。

---

## 日常的な運用コマンド

```bash
# 全モデルの実行
dbt run

# 特定モデルのみ実行
dbt run --select mart_traffic

# 特定モデルとその上流をすべて実行
dbt run --select +mart_traffic

# テスト実行
dbt test

# ドキュメント生成・表示
dbt docs generate
dbt docs serve
```

---

## まとめ

dbtを導入することで、GA4のBigQuery分析基盤に「再現性」「テスト」「ドキュメント」が加わります。

自分としては、SQLファイルが5本を超えたあたりでdbtの導入を検討するのが良いタイミングだと感じています。最初はstagingモデル2〜3本から始めて、徐々にmartモデルを追加していく進め方がスムーズです。

皆さんはGA4データの管理にdbtを使っていますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
