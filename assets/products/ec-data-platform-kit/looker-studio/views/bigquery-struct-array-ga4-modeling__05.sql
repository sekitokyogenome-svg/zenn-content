-- BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 出典: articles/bigquery-struct-array-ga4-modeling.md

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.session_mart` AS

WITH base AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    geo.country AS country
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
)

SELECT
  event_date,
  user_pseudo_id,
  ga_session_id,
  MAX(source) AS source,
  MAX(medium) AS medium,
  MAX(device_category) AS device_category,
  MAX(country) AS country,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM
  base
WHERE
  ga_session_id IS NOT NULL
GROUP BY
  event_date,
  user_pseudo_id,
  ga_session_id
