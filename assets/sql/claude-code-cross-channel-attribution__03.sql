-- 出典: Claude Codeでクロスチャネルアトリビューション分析を自動化した
-- 記事: articles/claude-code-cross-channel-attribution.md（Step 3：時間減衰モデルを実装する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 時間減衰アトリビューション
WITH touchpoints AS (
  -- Step 1のCTEをここに入れる（省略）
),
time_decay AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 指数関数的に重みを増やす（半減期7日）
    EXP(
      -0.693 * TIMESTAMP_DIFF(
        MAX(session_start) OVER (PARTITION BY user_pseudo_id),
        session_start,
        DAY
      ) / 7.0
    ) AS decay_weight
  FROM touchpoints
),
weighted AS (
  SELECT
    *,
    SAFE_DIVIDE(
      decay_weight,
      SUM(decay_weight) OVER (PARTITION BY user_pseudo_id)
    ) AS normalized_weight,
    MAX(revenue) OVER (PARTITION BY user_pseudo_id) AS total_revenue
  FROM time_decay
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(normalized_weight * total_revenue), 0) AS decay_revenue
FROM weighted
GROUP BY channel
ORDER BY decay_revenue DESC;
