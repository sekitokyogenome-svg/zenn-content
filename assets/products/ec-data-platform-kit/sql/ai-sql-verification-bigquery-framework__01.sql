-- AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 用途: AIがよく間違えるGA4 SQLのパターン
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY 1, 2
