-- 出典: 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略
-- 記事: articles/small-ec-bigquery-free-tier-strategy.md（GA4データを活用する際のSQL設計パターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchase_count DESC;
