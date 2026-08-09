-- BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した
-- 用途: BigQueryでCRMデータと統合するSQL例
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
