"""Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み

出典記事: articles/claude-code-ga4-event-tracking-gap-detection.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import anthropic
from google.cloud import bigquery
import json

# BigQueryからイベントデータを取得
bq_client = bigquery.Client(project="your_project")
query = """
SELECT
  event_date,
  event_name,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date,
  event_name
ORDER BY
  event_date, event_name
"""
df = bq_client.query(query).to_dataframe()
event_json = df.to_json(orient="records", force_ascii=False)

# Claude Codeで分析・提案
client = anthropic.Anthropic()
message = client.messages.create(
    model="claude-opus-5",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": f"""
以下はGA4のイベント発火データ（直近14日間）です。
計測漏れや異常な減少がないか分析し、原因の仮説と修正提案を日本語で出力してください。

{event_json}
"""
        }
    ]
)
print(message.content[0].text)
