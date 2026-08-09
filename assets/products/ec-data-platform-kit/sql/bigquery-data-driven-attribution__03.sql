-- BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する
-- 用途: 分析結果をLooker Studioで可視化する
-- 必要テーブル: v_linear_attribution
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
