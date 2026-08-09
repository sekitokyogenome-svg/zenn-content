-- 出典: 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル
-- 記事: articles/subscription-ec-churn-bigquery-model.md（GA4×BigQueryエクスポートの基本構造を理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4イベントログの基本集計（直近30日）
SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  event_name,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  event_date
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
