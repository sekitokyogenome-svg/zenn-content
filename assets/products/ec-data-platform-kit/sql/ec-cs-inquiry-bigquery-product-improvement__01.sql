-- ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法
-- 用途: 問い合わせカテゴリ別・商品別の集計SQL
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  product_sku,
  category,
  COUNT(*) AS inquiry_count,
  COUNTIF(LOWER(category) LIKE '%return%' OR LOWER(category) LIKE '%返品%') AS return_count,
  COUNTIF(LOWER(category) LIKE '%defect%' OR LOWER(category) LIKE '%不良%') AS defect_count
FROM
  `your_project.cs_dataset.tickets`
WHERE
  DATE(created_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
GROUP BY
  product_sku,
  category
ORDER BY
  inquiry_count DESC
LIMIT 50
