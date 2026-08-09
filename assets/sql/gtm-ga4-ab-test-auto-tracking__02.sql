-- 出典: GTM × GA4でA/Bテスト結果を自動計測する仕組みを作る
-- 記事: articles/gtm-ga4-ab-test-auto-tracking.md（統計的有意差の検証（Z検定））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH stats AS (
  -- 上記のクエリ結果を使用
  SELECT
    variant,
    COUNT(DISTINCT t.user_pseudo_id) AS n,
    COUNT(DISTINCT c.user_pseudo_id) AS x
  FROM test_users t
  LEFT JOIN conversions c ON t.user_pseudo_id = c.user_pseudo_id
  GROUP BY variant
),
ab AS (
  SELECT
    MAX(IF(variant = 'A', n, 0)) AS n_a,
    MAX(IF(variant = 'A', x, 0)) AS x_a,
    MAX(IF(variant = 'B', n, 0)) AS n_b,
    MAX(IF(variant = 'B', x, 0)) AS x_b
  FROM stats
)
SELECT
  x_a / n_a AS rate_a,
  x_b / n_b AS rate_b,
  (x_a + x_b) / (n_a + n_b) AS pooled_rate,
  (x_b / n_b - x_a / n_a) /
    SQRT(
      ((x_a + x_b) / (n_a + n_b)) *
      (1 - (x_a + x_b) / (n_a + n_b)) *
      (1.0 / n_a + 1.0 / n_b)
    ) AS z_score
FROM ab
