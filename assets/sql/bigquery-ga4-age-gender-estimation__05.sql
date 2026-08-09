-- 出典: BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した
-- 記事: articles/bigquery-ga4-age-gender-estimation.md（BigQueryでCRMデータと統合するSQL例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  ga.user_pseudo_id,
  crm.age,
  crm.gender,
  crm.prefecture,
  COUNT(DISTINCT CASE WHEN ga.event_name = 'purchase' THEN ga.event_bundle_sequence_id END) AS purchases,
  SUM(CASE WHEN ga.event_name = 'purchase' THEN ga.ecommerce.purchase_revenue END) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*` ga
INNER JOIN
  `your-project.crm.members` crm
  ON ga.user_id = crm.user_id
WHERE
  ga._TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  ga.user_pseudo_id, crm.age, crm.gender, crm.prefecture
