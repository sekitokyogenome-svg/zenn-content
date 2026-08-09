-- 出典: ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 記事: articles/ec-site-speed-cvr-bigquery-crux.md（CrUXデータとは何か）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 日本向けCrUXデータ（月次集計）
`chrome-ux-report.country_jp.YYYYMM`

-- グローバルデータ
`chrome-ux-report.all.YYYYMM`
