-- Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した
-- 用途: パーティションとクラスタリング
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
CLUSTER BY source, medium, device_category
AS
-- (上記と同じSELECT文)
