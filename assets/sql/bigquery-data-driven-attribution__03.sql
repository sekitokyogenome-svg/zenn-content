-- 出典: BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する
-- 記事: articles/bigquery-data-driven-attribution.md（分析結果をLooker Studioで可視化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 分析用ビューの作成例
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_linear_attribution` AS
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*) AS total_touchpoints
FROM (
  -- ※上記SQLのuser_touchサブクエリをここに展開
  SELECT 'placeholder' AS channel, 1 AS touch_count  -- 実際はuser_touchの内容を展開
) t
GROUP BY channel;
