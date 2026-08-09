-- 203. GA4×BigQueryでSNS流入の質を測定してInstagramとTikTokを比較した（SNS流入のアシストコンバージョンを確認する）
-- 用途: SNS流入のアシストコンバージョンを確認する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sns_users AS (
  -- SNS経由で訪問したことがあるユーザー
  SELECT DISTINCT user_pseudo_id, collected_traffic_source.manual_source AS first_sns
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
    AND event_name = 'session_start'
),

purchasers AS (
  -- 購入したユーザー
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  s.first_sns,
  COUNT(DISTINCT s.user_pseudo_id) AS sns_visitors,
  COUNT(DISTINCT p.user_pseudo_id) AS eventual_purchasers,
  ROUND(COUNT(DISTINCT p.user_pseudo_id) / COUNT(DISTINCT s.user_pseudo_id) * 100, 2) AS eventual_cvr
FROM sns_users s
LEFT JOIN purchasers p ON s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.first_sns
ORDER BY sns_visitors DESC
