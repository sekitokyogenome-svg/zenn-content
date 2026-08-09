-- 出典: Shopify×GTM×GA4でカスタムピクセルを使った高精度エコマース計測を実装する
-- 記事: articles/shopify-gtm-ga4-custom-pixel-tracking.md（GA4でのデータ確認とBigQueryでの分析クエリ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- BigQuery: 流入元チャネル別の購入金額集計（GA4エクスポートテーブル）
SELECT
  s.manual_medium AS medium,
  s.manual_source AS source,
  COUNT(DISTINCT ep_session.value.int_value) AS sessions,
  COUNT(DISTINCT CASE WHEN e.event_name = 'purchase' THEN e.user_pseudo_id END) AS purchasers,
  SUM(
    CASE WHEN e.event_name = 'purchase'
    THEN (
      SELECT ep.value.double_value
      FROM UNNEST(e.event_params) AS ep
      WHERE ep.key = 'value'
    )
    END
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*` AS e,
  UNNEST(e.event_params) AS ep_session,
  UNNEST([e.collected_traffic_source]) AS s
WHERE
  ep_session.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC;
