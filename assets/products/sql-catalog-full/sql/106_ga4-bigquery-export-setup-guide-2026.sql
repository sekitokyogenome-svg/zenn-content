-- 106. GA4のBigQueryエクスポート完全設定ガイド【2026年版】（流入元（メディア）を取得するクエリ例）
-- 用途: 流入元（メディア）を取得するクエリ例
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_20260328`
WHERE
  event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  event_count DESC
