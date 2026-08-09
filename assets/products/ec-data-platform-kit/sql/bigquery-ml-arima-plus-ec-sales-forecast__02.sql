-- BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する
-- 用途: ステップ1: GA4データから週次売上を集計する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(
    (SELECT COALESCE(ep.value.double_value, ep.value.int_value)
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS weekly_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  week_start, medium, source
ORDER BY
  week_start ASC;
