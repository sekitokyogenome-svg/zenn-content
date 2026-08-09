-- ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 用途: BigQueryでCrUXデータを取得するSQL
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  origin,
  -- LCP（良好・要改善・不良の割合）
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start < 2500 LIMIT 1), 4
  ) AS lcp_good_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 2500 AND start < 4000 LIMIT 1), 4
  ) AS lcp_needs_improvement_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 4000 LIMIT 1), 4
  ) AS lcp_poor_ratio,
  -- LCP中央値
  largest_contentful_paint.percentiles.p75 AS lcp_p75_ms,
  -- FCP中央値
  first_contentful_paint.percentiles.p75 AS fcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'  -- 自社ドメインに変更
