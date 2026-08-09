-- BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 用途: 特徴量テーブルを作成する（GA4エクスポートデータの加工）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source  AS traffic_source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
features AS (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT ga_session_id)                             AS session_count,
    COUNTIF(event_name = 'page_view')                        AS page_view_count,
    COUNTIF(event_name = 'view_item')                        AS view_item_count,
    COUNTIF(event_name = 'add_to_cart')                      AS add_to_cart_count,
    COUNTIF(event_name = 'begin_checkout')                   AS begin_checkout_count,
    MAX(CASE WHEN traffic_medium = 'email'   THEN 1 ELSE 0 END) AS has_email_session,
    MAX(CASE WHEN traffic_medium = 'cpc'     THEN 1 ELSE 0 END) AS has_paid_search_session,
    MAX(CASE WHEN event_name = 'purchase'    THEN 1 ELSE 0 END) AS label
  FROM base
  GROUP BY user_pseudo_id
)
SELECT * FROM features;
