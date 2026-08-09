-- 出典: BigQueryのアクセス制御をIAMで適切に設計する【チーム運用編】
-- 記事: articles/bigquery-iam-access-control-team.md（GA4データへの閲覧権限を安全に設計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4エクスポートデータを使った流入元別セッション集計
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  session_count DESC
LIMIT 20;
