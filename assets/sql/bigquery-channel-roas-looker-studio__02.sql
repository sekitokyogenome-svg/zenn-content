-- 出典: チャネル別ROASをBigQueryで集計してLooker Studioに可視化する
-- 記事: articles/bigquery-channel-roas-looker-studio.md（Step 2：広告費データを用意する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 広告費テーブルの作成
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ad_spend` (
  month STRING,        -- '2025-01' 形式
  medium STRING,       -- 'cpc', 'display', 'social' など
  source STRING,       -- 'google', 'meta', 'line' など
  spend INT64          -- 広告費（円）
);
