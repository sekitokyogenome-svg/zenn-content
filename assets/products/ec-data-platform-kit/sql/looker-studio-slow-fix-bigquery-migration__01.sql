-- Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した
-- 用途: マートテーブルの作り方：日別サマリーの例
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,

  -- セッション数
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,

  -- ユーザー数
  COUNT(DISTINCT user_pseudo_id) AS users,

  -- PV数
  COUNTIF(event_name = 'page_view') AS page_views,

  -- コンバージョン数
  COUNTIF(event_name = 'purchase') AS conversions,

  -- 収益
  SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS revenue

FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1, 2, 3, 4
