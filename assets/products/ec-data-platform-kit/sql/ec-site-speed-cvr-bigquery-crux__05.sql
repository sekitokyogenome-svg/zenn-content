-- ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 用途: CrUXとGA4データを組み合わせた分析アプローチ
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  form_factor.name                           AS device_type,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'
  AND form_factor.name = 'phone'
