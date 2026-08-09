-- 出典: GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 記事: articles/ga4-bigquery-streaming-vs-daily-export.md（日次テーブルとイントラデイを組み合わせる方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 過去6日分（確定済み）＋本日分（ストリーミング）を合わせて参照する
SELECT
  event_date,
  event_name,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM (
  -- 確定済みの日次テーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 6 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))

  UNION ALL

  -- 本日のストリーミングテーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_intraday_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
)
GROUP BY
  event_date,
  event_name
ORDER BY
  event_date DESC,
  users DESC;
