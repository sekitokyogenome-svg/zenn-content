-- 出典: BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った
-- 記事: articles/bigquery-ec-product-profit-cvr-dashboard.md（4象限マトリクスで優先度を整理する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  item_id,
  item_name,
  cvr,
  gross_margin_pct,
  CASE
    WHEN cvr >= 3.0 AND gross_margin_pct >= 40 THEN '最優先投資'
    WHEN cvr >= 3.0 AND gross_margin_pct < 40 THEN '改善不要（維持）'
    WHEN cvr < 3.0 AND gross_margin_pct >= 40 THEN 'CVR改善'
    ELSE '撤退検討'
  END AS quadrant
FROM product_profit
ORDER BY quadrant, gross_profit DESC;
