-- BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した
-- 用途: ユーザーを購入回数で分類するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  CASE
    WHEN purchase_count = 1 THEN 'one_time'
    ELSE 'repeat'
  END AS buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(purchase_count), 1) AS avg_purchases
FROM purchase_counts
GROUP BY buyer_type
