-- 出典: BigQueryでGA4の日次・週次・月次集計テーブルをスケジュール実行する
-- 記事: articles/bigquery-ga4-scheduled-aggregation-tables.md（1. GA4エクスポートの遅延に対応する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テーブルの存在チェックを入れる
DECLARE target_date STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

-- テーブルが存在するか確認
IF (SELECT COUNT(*) FROM `${PROJECT}.${DATASET}.__TABLES__` WHERE table_id = CONCAT('events_', target_date)) = 0 THEN
  SELECT ERROR(CONCAT('テーブル events_', target_date, ' が存在しません'));
END IF;

-- 以下、集計処理
