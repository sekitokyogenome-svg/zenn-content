-- ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した
-- 出典: articles/ec-return-rate-ga4-bigquery-category.md

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_return_rate_by_category` AS
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
GROUP BY
  month, item_category
;
