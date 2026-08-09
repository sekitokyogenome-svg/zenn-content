-- 出典: 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル
-- 記事: articles/subscription-ec-churn-bigquery-model.md（解約予兆スコアをSQLで算出する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 解約予兆スコアの算出
WITH behavior_signals AS (
  -- （前述のCTEを再利用）
  SELECT
    user_pseudo_id,
    COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
      AS cancel_page_views,
    COUNTIF(page_location LIKE '%/mypage%')
      AS mypage_views,
    COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
      AS help_page_views,
    COUNT(DISTINCT event_date) AS active_days
  FROM (
    SELECT
      user_pseudo_id,
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location') AS page_location,
      event_date
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
      AND event_name = 'page_view'
  )
  GROUP BY user_pseudo_id
)

SELECT
  user_pseudo_id,
  cancel_page_views,
  mypage_views,
  help_page_views,
  active_days,
  -- スコアリング（重みは要チューニング）
  ROUND(
    (cancel_page_views * 40)
    + (GREATEST(0, 5 - active_days) * 5)
    + (help_page_views * 3)
    + (GREATEST(0, 10 - mypage_views) * 2)
  , 1) AS churn_risk_score
FROM behavior_signals
ORDER BY churn_risk_score DESC
