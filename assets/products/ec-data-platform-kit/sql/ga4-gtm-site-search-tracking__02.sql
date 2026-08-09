-- GA4×GTMでサイト内検索キーワードを正しく計測する設定
-- 用途: 検索後のコンバージョン率
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH search_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'view_search_results'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  COUNT(s.user_pseudo_id) AS search_users,
  COUNT(p.user_pseudo_id) AS search_and_purchase_users,
  ROUND(COUNT(p.user_pseudo_id) / COUNT(s.user_pseudo_id) * 100, 2) AS conversion_rate
FROM search_users s
LEFT JOIN purchase_users p ON s.user_pseudo_id = p.user_pseudo_id
