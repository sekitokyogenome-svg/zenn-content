---
title: "BigQueryでGA4の日次・週次・月次集計テーブルをスケジュール実行する"
emoji: "📅"
type: "tech"
topics: ["bigquery", "googleanalytics", "automation"]
published: false
---

## はじめに

GA4のBigQueryエクスポートデータに対して、毎回rawテーブルからクエリを実行していると、スキャン量とコストが増え続けます。

「毎朝ダッシュボードを開くたびに数GBスキャンされている」「同じ集計を何度も実行している」という状況は、Scheduled Queriesで集計テーブルを自動作成することで改善できます。

この記事では、BigQueryのScheduled Queriesを使って日次・週次・月次の集計テーブルを自動生成する方法を解説します。

---

## Scheduled Queriesとは

BigQueryのScheduled Queriesは、SQLクエリを定期的に自動実行する機能です。

| 項目 | 内容 |
|------|------|
| 実行頻度 | 毎時 / 毎日 / 毎週 / 毎月 / カスタムcron |
| 結果の保存先 | テーブルへの上書き or 追記 |
| 通知 | メール / Pub/Sub（Slack連携可能） |
| 料金 | クエリ実行分のみ（Scheduled Queries自体は無料） |

:::message
Scheduled Queriesを使うには、BigQuery Data Transfer APIの有効化が必要です。初回利用時にGCPコンソールから有効化できます。
:::

---

## 日次集計テーブルの設計

### 日次セッション集計

前日分のデータを集計して、集計テーブルに追記する設計です。

```sql
-- 日次実行：前日分のセッション集計をmart_daily_sessionsに追記
DECLARE target_date STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

CREATE TABLE IF NOT EXISTS `beeracle.beeracle_mart.mart_daily_sessions` (
  event_date DATE,
  medium STRING,
  device_category STRING,
  sessions INT64,
  users INT64,
  page_views INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY event_date
CLUSTER BY medium, device_category;

MERGE `beeracle.beeracle_mart.mart_daily_sessions` AS target
USING (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    device.category AS device_category,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'page_view') AS page_views,
    COUNTIF(event_name = 'purchase') AS purchases,
    ROUND(
      SAFE_DIVIDE(
        COUNTIF(event_name = 'purchase'),
        COUNT(DISTINCT
          CONCAT(user_pseudo_id, '-',
          CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
        )
      ) * 100, 2
    ) AS cvr_pct
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX = target_date
    AND event_name IN ('session_start', 'page_view', 'purchase')
  GROUP BY event_date, medium, device_category
) AS source
ON target.event_date = source.event_date
  AND target.medium = source.medium
  AND target.device_category = source.device_category
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    page_views = source.page_views,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (event_date, medium, device_category, sessions, users, page_views, purchases, cvr_pct)
  VALUES (source.event_date, source.medium, source.device_category, source.sessions, source.users, source.page_views, source.purchases, source.cvr_pct)
```

### ポイント

- `MERGE` 文を使うことで、再実行しても重複が発生しません（冪等性の確保）
- パーティション＋クラスタリングを設定しているため、ダッシュボードからのクエリが高速です
- `DECLARE` で対象日を変数化しているため、手動での再実行も容易です

---

## 週次集計テーブルの設計

週次集計は、毎週月曜日に前週分（月曜〜日曜）を集計するパターンです。

```sql
-- 毎週月曜日に実行：前週分の週次集計
DECLARE week_start DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), WEEK(MONDAY));
DECLARE week_end DATE DEFAULT DATE_ADD(week_start, INTERVAL 6 DAY);

CREATE TABLE IF NOT EXISTS `beeracle.beeracle_mart.mart_weekly_summary` (
  week_start_date DATE,
  medium STRING,
  sessions INT64,
  users INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY week_start_date
CLUSTER BY medium;

MERGE `beeracle.beeracle_mart.mart_weekly_summary` AS target
USING (
  SELECT
    week_start AS week_start_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases,
    ROUND(
      SAFE_DIVIDE(
        COUNTIF(event_name = 'purchase'),
        COUNT(DISTINCT
          CONCAT(user_pseudo_id, '-',
          CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
        )
      ) * 100, 2
    ) AS cvr_pct
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', week_start) AND FORMAT_DATE('%Y%m%d', week_end)
    AND event_name IN ('session_start', 'page_view', 'purchase')
  GROUP BY medium
) AS source
ON target.week_start_date = source.week_start_date
  AND target.medium = source.medium
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (week_start_date, medium, sessions, users, purchases, cvr_pct)
  VALUES (source.week_start_date, source.medium, source.sessions, source.users, source.purchases, source.cvr_pct)
```

---

## 月次集計テーブルの設計

月次集計は、毎月1日に前月分を集計するパターンです。

```sql
-- 毎月1日に実行：前月分の月次集計
DECLARE month_start DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH);
DECLARE month_end DATE DEFAULT LAST_DAY(month_start);

CREATE TABLE IF NOT EXISTS `beeracle.beeracle_mart.mart_monthly_summary` (
  month_start_date DATE,
  medium STRING,
  sessions INT64,
  users INT64,
  new_users INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY month_start_date
CLUSTER BY medium;

MERGE `beeracle.beeracle_mart.mart_monthly_summary` AS target
USING (
  SELECT
    month_start AS month_start_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT CASE WHEN event_name = 'first_visit' THEN user_pseudo_id END) AS new_users,
    COUNTIF(event_name = 'purchase') AS purchases,
    ROUND(
      SAFE_DIVIDE(
        COUNTIF(event_name = 'purchase'),
        COUNT(DISTINCT
          CONCAT(user_pseudo_id, '-',
          CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
        )
      ) * 100, 2
    ) AS cvr_pct
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', month_start) AND FORMAT_DATE('%Y%m%d', month_end)
    AND event_name IN ('session_start', 'page_view', 'purchase', 'first_visit')
  GROUP BY medium
) AS source
ON target.month_start_date = source.month_start_date
  AND target.medium = source.medium
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    new_users = source.new_users,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (month_start_date, medium, sessions, users, new_users, purchases, cvr_pct)
  VALUES (source.month_start_date, source.medium, source.sessions, source.users, source.new_users, source.purchases, source.cvr_pct)
```

---

## Scheduled Queryの設定手順

### GCPコンソールから設定する場合

1. BigQueryコンソール →「スケジュールされたクエリ」→「スケジュールされたクエリを作成」
2. クエリを入力
3. スケジュールを設定
   - 日次：`every day 06:00` （JST = UTC+9なので、UTC 21:00 = JST 06:00）
   - 週次：`every monday 06:00`
   - 月次：`1 of month 06:00`
4. リージョンを `asia-northeast1` に設定
5. 通知先を設定（メール or Pub/Sub）

### bqコマンドから設定する場合

```bash
bq mk --transfer_config \
  --project_id=beeracle \
  --data_source=scheduled_query \
  --target_dataset=beeracle_mart \
  --display_name="日次セッション集計" \
  --schedule="every day 21:00" \
  --params='{"query":"<SQL文>","write_disposition":"WRITE_APPEND"}'
```

:::message
スケジュールの時刻はUTCで指定します。JST 06:00に実行したい場合は、UTC 21:00（前日の21:00）を指定してください。GA4の日次エクスポートは通常翌日に完了するため、JST 06:00〜08:00頃の実行がおすすめです。
:::

---

## 運用上の注意点

### 1. GA4エクスポートの遅延に対応する

GA4の日次エクスポートが遅延すると、スケジュールクエリが空のテーブルを対象に実行される可能性があります。

```sql
-- テーブルの存在チェックを入れる
DECLARE target_date STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

-- テーブルが存在するか確認
IF (SELECT COUNT(*) FROM `beeracle.analytics_263425816.__TABLES__` WHERE table_id = CONCAT('events_', target_date)) = 0 THEN
  SELECT ERROR(CONCAT('テーブル events_', target_date, ' が存在しません'));
END IF;

-- 以下、集計処理
```

### 2. 失敗時の通知設定

Pub/Subと連携してSlackに失敗通知を送る構成がおすすめです。

### 3. バックフィルの実行

過去分を一括で集計し直したい場合は、`DECLARE` の日付を変更して手動実行できます。

---

## まとめ

Scheduled Queriesで集計テーブルを自動生成する仕組みを作ると、ダッシュボードのクエリ速度が上がり、BigQueryのコストも削減できます。

自分としては、まず日次集計から始めて、運用が安定してから週次・月次を追加していく進め方がリスクが少ないと感じています。

皆さんはBigQueryのスケジュール実行、どのような頻度・構成で運用していますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
