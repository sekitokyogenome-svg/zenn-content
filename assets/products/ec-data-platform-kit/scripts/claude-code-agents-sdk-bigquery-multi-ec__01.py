"""Claude CodeのAgents SDK × BigQueryで複数ECサイトを一括監視する

出典記事: articles/claude-code-agents-sdk-bigquery-multi-ec.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: tools/bigquery_tool.py
目的: Agents SDKのツールとしてBigQueryクエリを実行する
作成日: 2026-03-30
依存: google-cloud-bigquery, claude-agent-sdk
"""

from google.cloud import bigquery

def query_bigquery(
    project: str, dataset: str, query_template: str
) -> list:
    """BigQueryクエリを実行して結果を返す"""
    client = bigquery.Client(project=project)

    query = query_template.replace("{dataset}", f"{project}.{dataset}")
    result = client.query(query).to_dataframe()
    return result.to_dict(orient="records")

# 日次KPIクエリテンプレート
DAILY_KPI_QUERY = """
WITH today AS (
  SELECT
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `{dataset}.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE(
    '%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
prev_week AS (
  SELECT
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `{dataset}.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE(
    '%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY))
)
SELECT
  t.sessions AS today_sessions,
  p.sessions AS prev_sessions,
  SAFE_DIVIDE(t.sessions - p.sessions, p.sessions) * 100
    AS session_change_pct,
  t.purchases AS today_purchases,
  SAFE_DIVIDE(t.purchases, t.sessions) * 100 AS today_cvr,
  SAFE_DIVIDE(p.purchases, p.sessions) * 100 AS prev_cvr,
  t.revenue AS today_revenue,
  p.revenue AS prev_revenue,
  SAFE_DIVIDE(t.revenue - p.revenue, p.revenue) * 100
    AS revenue_change_pct
FROM today t, prev_week p;
"""
