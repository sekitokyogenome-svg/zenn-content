-- 359. Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した（パーティションとクラスタリング）
-- 用途: パーティションとクラスタリング
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
CLUSTER BY source, medium, device_category
AS
-- (上記と同じSELECT文)
