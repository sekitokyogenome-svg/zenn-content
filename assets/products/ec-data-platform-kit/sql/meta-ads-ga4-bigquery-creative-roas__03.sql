-- Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする
-- 用途: 広告費データとの結合
-- 必要テーブル: meta_ads_cost
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH ga4_revenue AS (
  -- 前述のクエリ結果
  SELECT
    creative_name,
    total_revenue,
    sessions,
    purchases
  FROM session_summary
),
meta_cost AS (
  -- Meta広告費用テーブル（API or CSVインポート）
  SELECT
    ad_name AS creative_name,
    SUM(spend) AS total_spend,
    SUM(impressions) AS total_impressions,
    SUM(clicks) AS total_clicks
  FROM `${PROJECT}.${DATASET}.meta_ads_cost`
  WHERE date BETWEEN '2026-03-01' AND '2026-03-31'
  GROUP BY ad_name
)
SELECT
  g.creative_name,
  g.sessions,
  g.purchases,
  g.total_revenue,
  m.total_spend,
  m.total_clicks,
  ROUND(SAFE_DIVIDE(g.total_revenue, m.total_spend), 2) AS roas,
  ROUND(SAFE_DIVIDE(m.total_spend, g.purchases), 0) AS cpa
FROM ga4_revenue g
JOIN meta_cost m
  ON g.creative_name = m.creative_name
ORDER BY roas DESC;
