-- ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した
-- 用途: BigQueryで商品カテゴリ別の返品率を集計するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH
-- 購入イベントをカテゴリ別に集計
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS purchase_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
  GROUP BY
    item_category
),

-- 返品イベントをカテゴリ別に集計
returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS return_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
  GROUP BY
    item_category
)

SELECT
  p.item_category,
  p.purchase_count,
  COALESCE(r.return_count, 0) AS return_count,
  ROUND(SAFE_DIVIDE(COALESCE(r.return_count, 0), p.purchase_count) * 100, 2) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.item_category = r.item_category
WHERE
  p.item_category IS NOT NULL
ORDER BY
  return_rate_pct DESC
;
