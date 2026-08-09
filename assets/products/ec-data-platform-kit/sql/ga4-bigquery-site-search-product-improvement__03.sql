-- ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した
-- 用途: 検索後の行動を詳細に追う
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH search_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
    event_timestamp AS search_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

post_search_actions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    e.event_timestamp
  FROM `${PROJECT}.${DATASET}.events_*` e
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)

SELECT
  se.search_term,
  COUNT(DISTINCT se.user_pseudo_id) AS searchers,
  -- 検索後に商品詳細を見た割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'view_item', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS view_item_rate,
  -- 検索後にカート追加した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'add_to_cart', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS add_to_cart_rate,
  -- 検索後に購入した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'purchase', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS purchase_rate
FROM search_events se
LEFT JOIN post_search_actions psa
  ON se.user_pseudo_id = psa.user_pseudo_id
  AND se.session_id = psa.session_id
  AND psa.event_timestamp > se.search_timestamp
WHERE se.search_term IS NOT NULL
GROUP BY se.search_term
HAVING searchers >= 10
ORDER BY searchers DESC
LIMIT 30
