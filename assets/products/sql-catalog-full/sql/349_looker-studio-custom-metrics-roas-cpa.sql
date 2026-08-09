-- 349. Looker Studioのカスタム指標でROAS・CPAを自動計算する設定（BigQueryでROASを事前計算する方法）
-- 用途: BigQueryでROASを事前計算する方法
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
