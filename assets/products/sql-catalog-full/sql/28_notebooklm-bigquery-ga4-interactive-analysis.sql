-- 28. NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する（複数のクエリ結果を組み合わせてより深い分析を行う）
-- 用途: 複数のクエリ結果を組み合わせてより深い分析を行う
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_events,
  SUM(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  item_category
ORDER BY
  purchase_events DESC;
