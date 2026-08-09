-- 出典: BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】
-- 記事: articles/bigquery-claude-code-anomaly-detection-alert.md（閾値チューニングで誤検知を減らす）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 曜日別移動平均にする場合のウィンドウ関数
AVG(sessions) OVER (
  PARTITION BY EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d', event_date))
  ORDER BY event_date
  ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
) AS avg_sessions_same_dow
