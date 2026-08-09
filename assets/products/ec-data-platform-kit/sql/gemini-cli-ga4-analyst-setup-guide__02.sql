-- Gemini CLIをGA4データアナリストとして使う具体的な設定と活用例
-- 用途: 活用例②：購入完了ファネルのドロップオフ分析
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH funnel AS (
  SELECT
    user_pseudo_id,
    MAX(IF(event_name = 'view_item', 1, 0))   AS viewed,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added,
    MAX(IF(event_name = 'purchase', 1, 0))    AS purchased
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  GROUP BY
    user_pseudo_id
)
SELECT
  SUM(viewed)    AS view_item_users,
  SUM(added)     AS add_to_cart_users,
  SUM(purchased) AS purchase_users,
  ROUND(SUM(added)     / NULLIF(SUM(viewed), 0) * 100, 1) AS add_rate_pct,
  ROUND(SUM(purchased) / NULLIF(SUM(added), 0)  * 100, 1) AS purchase_rate_pct
FROM funnel;
