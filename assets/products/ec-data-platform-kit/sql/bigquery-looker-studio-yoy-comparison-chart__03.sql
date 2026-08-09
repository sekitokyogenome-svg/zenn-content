-- BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 用途: パターン3: スコアカードで前年比を大きく表示
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END) AS revenue_ytd,
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END) AS revenue_ytd_ly,
  SAFE_DIVIDE(
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END)
    - SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END),
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END)
  ) * 100 AS ytd_yoy_pct
FROM monthly_data
WHERE month_num <= EXTRACT(MONTH FROM CURRENT_DATE())
