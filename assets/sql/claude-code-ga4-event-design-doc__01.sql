-- 出典: Claude CodeでGA4のイベント設計書を自動生成する方法
-- 記事: articles/claude-code-ga4-event-design-doc.md（イベント名とパラメータの一覧を取得するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- イベント名一覧と発生件数
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_seen,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_seen
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
