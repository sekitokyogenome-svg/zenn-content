-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（1. items配列のUNNESTを忘れる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- NG: UNNESTなしでは参照できない
SELECT items.item_name FROM `${PROJECT}.${DATASET}.events_*`

-- OK: UNNESTで展開する
SELECT item.item_name
FROM `${PROJECT}.${DATASET}.events_*`, UNNEST(items) AS item
