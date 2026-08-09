"""Cloud Scheduler × Cloud Functions × BigQueryで完全サーバーレスなETLを構築する

出典記事: articles/cloud-scheduler-functions-bigquery-etl.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import functions_framework
from google.cloud import bigquery
from datetime import date, timedelta

PROJECT_ID = "your-project-id"
DATASET_ID = "your_dataset"
GA4_TABLE  = f"{PROJECT_ID}.analytics_XXXXXXXX.events_*"
DEST_TABLE = f"{PROJECT_ID}.{DATASET_ID}.daily_session_summary"

@functions_framework.http
def run_etl(request):
    """HTTP Cloud Function: 前日のGA4データを集計してサマリーテーブルへ書き込む"""
    client = bigquery.Client(project=PROJECT_ID)

    yesterday = (date.today() - timedelta(days=1)).strftime("%Y%m%d")

    query = f"""
    SELECT
      event_date,
      collected_traffic_source.manual_medium AS medium,
      collected_traffic_source.manual_source AS source,
      COUNT(DISTINCT
        (SELECT value.string_value
         FROM UNNEST(event_params) AS ep
         WHERE ep.key = 'ga_session_id')
      ) AS sessions
    FROM `{GA4_TABLE}`
    WHERE _TABLE_SUFFIX = '{yesterday}'
      AND event_name = 'session_start'
    GROUP BY 1, 2, 3
    """

    job_config = bigquery.QueryJobConfig(
        destination=DEST_TABLE,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )

    job = client.query(query, job_config=job_config)
    job.result()  # 完了まで待機

    return f"ETL completed for {yesterday}", 200
