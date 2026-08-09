-- 出典: BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する
-- 記事: articles/bigquery-labels-cross-project-cost.md（クエリジョブへのラベル付与方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ジョブラベルを設定してからクエリを実行する例（BigQuery Console）
-- ※BigQuery ConsoleではジョブラベルはAPIまたはbqコマンド経由で付与します
-- 以下はbqコマンドでラベル付きジョブとして実行する例のイメージです

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
