-- 出典: Claude Codeで競合ECサイトのSEO戦略をGA4×Search Consoleデータから逆算する
-- 記事: articles/claude-code-ec-seo-ga4-search-console-reverse.md（Search Consoleデータから検索キーワードの傾向を把握するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- Search Console データ集計（クリック率の低いインプレッション多数キーワードを抽出）
SELECT
  query,
  SUM(impressions)                          AS total_impressions,
  SUM(clicks)                               AS total_clicks,
  ROUND(SUM(clicks) / SUM(impressions) * 100, 2) AS ctr_pct,
  ROUND(AVG(position), 1)                   AS avg_position
FROM
  `your_project.search_console_dataset.searchdata_site_impression`
WHERE
  data_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
  AND impressions > 100
GROUP BY
  query
HAVING
  ctr_pct < 2.0            -- CTR 2%未満に絞る
  AND avg_position <= 20   -- 検索結果2ページ目以内
ORDER BY
  total_impressions DESC
LIMIT 100;
