-- 出典: GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する
-- 記事: articles/ga4-bigquery-google-ads-keyword-cvr.md（gclidの仕組みと取得方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- gclidマッピングテーブルの想定スキーマ
-- このテーブルはGoogle Ads APIまたはBigQueryデータ転送で取得する
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ads_click_keyword` (
  gclid STRING,
  campaign_name STRING,
  ad_group_name STRING,
  keyword STRING,
  match_type STRING,
  click_date DATE
);
