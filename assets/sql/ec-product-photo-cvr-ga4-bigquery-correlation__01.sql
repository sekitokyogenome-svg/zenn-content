-- 出典: ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した
-- 記事: articles/ec-product-photo-cvr-ga4-bigquery-correlation.md（BigQueryでのセッションCVR集計SQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH
-- セッションIDをUNNESTで取得し、商品ページのセッションを抽出
product_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'page_view'
    AND (SELECT value.string_value
         FROM UNNEST(event_params)
         WHERE key = 'page_location') LIKE '%/products/%'
),

-- 購入が発生したセッションを抽出
purchase_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'purchase'
)

-- 商品URLごとにセッションCVRを算出
SELECT
  ps.page_location,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))) AS total_sessions,
  COUNT(DISTINCT
    CASE WHEN pur.session_id IS NOT NULL
    THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
    END
  ) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT
        CASE WHEN pur.session_id IS NOT NULL
        THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
        END
      ),
      COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING)))
    ) * 100, 2
  ) AS cvr_pct
FROM
  product_sessions ps
LEFT JOIN
  purchase_sessions pur
  ON ps.user_pseudo_id = pur.user_pseudo_id
  AND ps.session_id = pur.session_id
GROUP BY
  ps.page_location
ORDER BY
  total_sessions DESC
