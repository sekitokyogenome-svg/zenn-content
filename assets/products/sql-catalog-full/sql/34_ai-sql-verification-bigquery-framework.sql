-- 34. AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った（AIがよく間違えるGA4 SQLのパターン） その2
-- 用途: AIがよく間違えるGA4 SQLのパターン
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY 1, 2
