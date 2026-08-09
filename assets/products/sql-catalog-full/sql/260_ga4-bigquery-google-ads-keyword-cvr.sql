-- 260. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する（gclidの仕組みと取得方法）
-- 用途: gclidの仕組みと取得方法
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ads_click_keyword` (
  gclid STRING,
  campaign_name STRING,
  ad_group_name STRING,
  keyword STRING,
  match_type STRING,
  click_date DATE
);
