-- 出典: BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 記事: articles/bigquery-ec-rfm-analysis-email-strategy.md（セグメント分類SQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH rfm_scores AS (
  -- 前述のクエリでr_score, f_score, m_scoreを取得済み
  SELECT *
  FROM user_rfm_scored
)
SELECT
  user_pseudo_id,
  r_score,
  f_score,
  m_score,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP顧客'
    WHEN r_score >= 4 AND f_score >= 3 THEN 'アクティブ優良'
    WHEN r_score >= 4 AND f_score <= 2 THEN '新規・単発'
    WHEN r_score <= 2 AND f_score >= 3 THEN '休眠リスク'
    WHEN r_score <= 2 AND f_score <= 2 THEN '離脱済み'
    ELSE 'その他'
  END AS segment
FROM rfm_scores;
