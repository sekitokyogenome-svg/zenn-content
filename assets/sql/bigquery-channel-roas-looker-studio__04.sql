-- 出典: チャネル別ROASをBigQueryで集計してLooker Studioに可視化する
-- 記事: articles/bigquery-channel-roas-looker-studio.md（Step 4：マートテーブルに保存する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- マートビューとして作成
CREATE OR REPLACE VIEW `project.dataset_mart.mart_channel_roas` AS
WITH channel_revenue AS (
  -- （上記のchannel_revenue CTEと同じ内容）
  ...
),
channel_spend AS (
  SELECT month, medium, source, spend
  FROM `${PROJECT}.${DATASET}.ad_spend`
)
SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  COALESCE(s.spend, 0) AS spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source;
