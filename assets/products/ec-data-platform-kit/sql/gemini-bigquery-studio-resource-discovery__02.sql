-- Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する
-- 用途: 流入元分析への応用
-- 必要テーブル: (なし)
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchases DESC
LIMIT 20;
