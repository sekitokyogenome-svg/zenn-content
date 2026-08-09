-- 384. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（ラベル別コストを集計するSQL）
-- 用途: ラベル別コストを集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  (SELECT value FROM UNNEST(labels) WHERE key = 'team') AS team,
  (SELECT value FROM UNNEST(labels) WHERE key = 'purpose') AS purpose,
  SUM(cost) AS total_cost_usd,
  SUM(cost) * 150 AS total_cost_jpy_approx  -- 概算換算（為替レートは適宜変更）
FROM
  `your_billing_project.billing_dataset.gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX`
WHERE
  service.description = 'BigQuery'
  AND DATE(_PARTITIONTIME) BETWEEN '2024-06-01' AND '2024-06-30'
GROUP BY
  team, purpose
ORDER BY
  total_cost_usd DESC
