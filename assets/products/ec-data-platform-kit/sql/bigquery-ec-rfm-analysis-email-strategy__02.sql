-- BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 用途: セグメント分類SQL
-- 必要テーブル: (なし)
-- コスト: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
