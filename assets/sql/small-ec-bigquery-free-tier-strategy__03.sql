-- 出典: 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略
-- 記事: articles/small-ec-bigquery-free-tier-strategy.md（ストレージコストを抑えるテーブル管理の工夫）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 月次売上サマリーを集計テーブルとして保存する例
CREATE OR REPLACE TABLE `your_project.ec_summary.monthly_revenue_202506` AS
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT ep.value.double_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source;
