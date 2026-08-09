-- 390. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック1：パーティション絞り込みで読み取りデータ量を減らす）
-- 用途: テクニック1：パーティション絞り込みで読み取りデータ量を減らす
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
