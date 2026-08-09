-- AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 用途: ステップ2: 既知の値と突き合わせる論理チェック
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
