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

-- （前のSQLのCVR集計部分をcvr_baseとして定義）
cvr_base AS (
  -- 上記のCVR集計SQLをここに入れる
  SELECT
    page_location,
    total_sessions,
    purchase_sessions,
    cvr_pct
  FROM ... -- 省略
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
