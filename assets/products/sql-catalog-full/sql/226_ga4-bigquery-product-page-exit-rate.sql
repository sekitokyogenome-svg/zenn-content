-- 226. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例（流入元別に商品ページ離脱率を比較する）
-- 用途: 流入元別に商品ページ離脱率を比較する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_exits AS (
  -- 前述のクエリで算出した商品ページ別の離脱フラグを使う
  SELECT
    user_pseudo_id,
    ga_session_id,
    is_exit
  FROM product_page_views
)
SELECT
  IFNULL(ss.source, '(direct)') AS source,
  IFNULL(ss.medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  SUM(pe.is_exit) AS exit_sessions,
  ROUND(SUM(pe.is_exit) / COUNT(*) * 100, 1) AS exit_rate
FROM product_exits pe
JOIN session_source ss
  ON pe.user_pseudo_id = ss.user_pseudo_id
  AND pe.ga_session_id = ss.ga_session_id
GROUP BY source, medium
ORDER BY sessions DESC;
