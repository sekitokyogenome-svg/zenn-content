-- 出典: Claude Codeでクロスチャネルアトリビューション分析を自動化した
-- 記事: articles/claude-code-cross-channel-attribution.md（Step 2：線形モデルを実装する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 線形アトリビューション
WITH touchpoints AS (
  -- Step 1のCTEをここに入れる（省略）
),
linear_attribution AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 各タッチポイントに均等配分
    SAFE_DIVIDE(
      MAX(revenue) OVER (PARTITION BY user_pseudo_id),
      total_touchpoints
    ) AS attributed_revenue
  FROM touchpoints
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(attributed_revenue), 0) AS linear_revenue,
  ROUND(AVG(attributed_revenue), 0) AS avg_attributed_revenue
FROM linear_attribution
GROUP BY channel
ORDER BY linear_revenue DESC;
