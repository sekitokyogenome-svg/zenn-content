-- ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する
-- 用途: SQLで差分の差分を計算する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH daily_cvr AS (
  -- 上記クエリの結果をCTEとして再利用するイメージ
  SELECT
    event_date,
    item_id,
    SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
  FROM session_level
  WHERE viewed = 1
  GROUP BY 1, 2
),

grouped AS (
  SELECT
    item_id,
    CASE
      WHEN item_id = 'ITEM_A' THEN 'treated'   -- 価格変更あり
      WHEN item_id = 'ITEM_B' THEN 'control'   -- 価格変更なし
    END AS group_type,
    CASE
      WHEN event_date < '2025-07-01' THEN 'pre'
      ELSE 'post'
    END AS period,
    AVG(cvr) AS avg_cvr
  FROM daily_cvr
  WHERE item_id IN ('ITEM_A', 'ITEM_B')
  GROUP BY 1, 2, 3
),

pivoted AS (
  SELECT
    item_id,
    group_type,
    MAX(IF(period = 'pre',  avg_cvr, NULL)) AS cvr_pre,
    MAX(IF(period = 'post', avg_cvr, NULL)) AS cvr_post
  FROM grouped
  GROUP BY 1, 2
),

diff AS (
  SELECT
    item_id,
    group_type,
    cvr_pre,
    cvr_post,
    cvr_post - cvr_pre AS delta_cvr
  FROM pivoted
)

-- DiD = 処置群のdelta − 対照群のdelta
SELECT
  MAX(IF(group_type = 'treated', delta_cvr, NULL))
    - MAX(IF(group_type = 'control', delta_cvr, NULL)) AS did_estimate,
  MAX(IF(group_type = 'treated', cvr_pre,  NULL)) AS treated_cvr_pre,
  MAX(IF(group_type = 'treated', cvr_post, NULL)) AS treated_cvr_post,
  MAX(IF(group_type = 'control', cvr_pre,  NULL)) AS control_cvr_pre,
  MAX(IF(group_type = 'control', cvr_post, NULL)) AS control_cvr_post
FROM diff
