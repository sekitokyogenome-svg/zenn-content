-- 出典: BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する
-- 記事: articles/bigquery-google-ads-ga4-keyword-roas.md（GA4のBigQueryエクスポートを理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4イベントからセッションIDと流入情報を抽出するCTE
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはUNNEST経由で取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
)
