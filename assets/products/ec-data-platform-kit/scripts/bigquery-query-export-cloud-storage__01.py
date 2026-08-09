"""BigQueryのクエリ結果をCloud Storageに自動エクスポートして外部ツール連携する

出典記事: articles/bigquery-query-export-cloud-storage.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

from google.cloud import bigquery
from datetime import datetime

PROJECT_ID = "your_project"
DATASET_ID = "temp_dataset"
TABLE_ID = "session_report"
GCS_BUCKET = "your-bucket"
GCS_PREFIX = "reports"

def export_bq_to_gcs():
    client = bigquery.Client(project=PROJECT_ID)

    # 集計クエリ
    query = """
    SELECT
      collected_traffic_source.manual_medium AS medium,
      collected_traffic_source.manual_source AS source,
      COUNT(DISTINCT
        (SELECT ep.value.int_value
         FROM UNNEST(event_params) AS ep
         WHERE ep.key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases
    FROM
      `your_project.analytics_XXXXXXXXX.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    GROUP BY medium, source
    ORDER BY sessions DESC
    """

    # クエリ結果を一時テーブルへ保存
    dest_table = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"
    job_config = bigquery.QueryJobConfig(
        destination=dest_table,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    query_job = client.query(query, job_config=job_config)
    query_job.result()  # 完了まで待機
    print(f"クエリ完了: {dest_table} にデータを書き込みました")

    # GCSへエクスポート
    today = datetime.today().strftime("%Y%m%d")
    gcs_uri = f"gs://{GCS_BUCKET}/{GCS_PREFIX}/session_report_{today}.csv"
    extract_config = bigquery.ExtractJobConfig(
        field_delimiter=",",
        print_header=True,
    )
    extract_job = client.extract_table(
        dest_table,
        gcs_uri,
        job_config=extract_config,
    )
    extract_job.result()
    print(f"GCSエクスポート完了: {gcs_uri}")

if __name__ == "__main__":
    export_bq_to_gcs()
