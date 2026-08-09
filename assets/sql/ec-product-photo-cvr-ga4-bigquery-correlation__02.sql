-- 出典: ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した
-- 記事: articles/ec-product-photo-cvr-ga4-bigquery-correlation.md（写真枚数データとのJOIN：相関を可視化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 写真枚数マスタ（別テーブルやサブクエリとして用意）
WITH photo_master AS (
  SELECT
    product_url,
    photo_count
  FROM
    `${PROJECT}.${DATASET}.photo_master`
),

-- ここから cvr_base：前セクションのCVR集計をそのまま取り込む
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
),

cvr_base AS (
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
)

SELECT
  pm.photo_count,
  COUNT(*) AS product_count,
  ROUND(AVG(cb.cvr_pct), 2) AS avg_cvr_pct,
  ROUND(MIN(cb.cvr_pct), 2) AS min_cvr_pct,
  ROUND(MAX(cb.cvr_pct), 2) AS max_cvr_pct
FROM
  cvr_base cb
LEFT JOIN
  photo_master pm
  ON cb.page_location LIKE CONCAT('%', pm.product_url, '%')
WHERE
  pm.photo_count IS NOT NULL
  AND cb.total_sessions >= 30  -- 統計的に意味のある最低セッション数
GROUP BY
  pm.photo_count
ORDER BY
  pm.photo_count ASC
