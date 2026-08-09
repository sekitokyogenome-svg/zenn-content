-- 378. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（日次テーブルとイントラデイを組み合わせる方法）
-- 用途: 日次テーブルとイントラデイを組み合わせる方法
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
