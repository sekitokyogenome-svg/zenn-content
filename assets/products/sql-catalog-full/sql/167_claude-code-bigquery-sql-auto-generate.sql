-- 167. Claude CodeでBigQueryのSQLを自然言語から自動生成する（LIMIT句で結果を確認）
-- 用途: LIMIT句で結果を確認
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  event_name,
  user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260301'
LIMIT 10
