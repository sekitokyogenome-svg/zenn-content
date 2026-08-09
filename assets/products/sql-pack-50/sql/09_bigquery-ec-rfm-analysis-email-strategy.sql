-- 09. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 用途: RFMスコアを算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20250401' AND '20260331'
    AND ecommerce.purchase_revenue > 0
),
user_rfm AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(CURRENT_DATE(), MAX(purchase_date), DAY) AS recency,
    COUNT(DISTINCT CONCAT(CAST(purchase_date AS STRING), '-', CAST(ga_session_id AS STRING))) AS frequency,
    SUM(revenue) AS monetary
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  recency,
  frequency,
  monetary,
  NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
  NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
  NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
FROM user_rfm;
