-- 131. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（クラスタリングキーの選定）
-- 用途: クラスタリングキーの選定
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category, country
AS
...
