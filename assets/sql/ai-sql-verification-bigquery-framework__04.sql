-- 出典: AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 記事: articles/ai-sql-verification-bigquery-framework.md（ステップ2: 既知の値と突き合わせる論理チェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション数を集計して既知の値と照合する
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS STRING
    )
  )) AS total_sessions
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
