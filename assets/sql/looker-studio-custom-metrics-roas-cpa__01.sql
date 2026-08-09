-- 出典: Looker Studioのカスタム指標でROAS・CPAを自動計算する設定
-- 記事: articles/looker-studio-custom-metrics-roas-cpa.md（BigQueryでROASを事前計算する方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  date,
  campaign_name,
  SUM(revenue) AS revenue,
  SUM(ad_cost) AS ad_cost,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_cost)) AS roas
FROM
  `${PROJECT}.${DATASET}.campaign_performance`
GROUP BY
  date, campaign_name
