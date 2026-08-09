-- 256. チャネル別ROASをBigQueryで集計してLooker Studioに可視化する（Step 2：広告費データを用意する）
-- 用途: Step 2：広告費データを用意する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ad_spend` (
  month STRING,        -- '2025-01' 形式
  medium STRING,       -- 'cpc', 'display', 'social' など
  source STRING,       -- 'google', 'meta', 'line' など
  spend INT64          -- 広告費（円）
);
