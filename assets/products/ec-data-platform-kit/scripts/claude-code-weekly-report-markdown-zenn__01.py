"""Claude Codeに週次レポートをMarkdownで生成させてそのままZennに投稿する

出典記事: articles/claude-code-weekly-report-markdown-zenn.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: weekly_data_fetcher.py
目的: 週次レポート用のデータをBigQueryから取得する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
import json
from pathlib import Path

def fetch_weekly_metrics(client: bigquery.Client, project_id: str, dataset: str) -> dict:
    """直近7日間の主要指標を取得する"""
    query = f"""
    WITH weekly_data AS (
      SELECT
        PARSE_DATE('%Y%m%d', event_date) AS date,
        COUNT(DISTINCT
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        ) AS sessions,
        COUNTIF(event_name = 'purchase') AS purchases,
        SUM(ecommerce.purchase_revenue) AS revenue,
        COUNT(DISTINCT user_pseudo_id) AS users
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
      GROUP BY date
    ),
    prev_week AS (
      SELECT
        COUNT(DISTINCT
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        ) AS sessions,
        COUNTIF(event_name = 'purchase') AS purchases,
        SUM(ecommerce.purchase_revenue) AS revenue,
        COUNT(DISTINCT user_pseudo_id) AS users
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    )
    SELECT
      'current' AS period,
      SUM(sessions) AS sessions,
      SUM(purchases) AS purchases,
      SUM(revenue) AS revenue,
      SUM(users) AS users
    FROM weekly_data
    UNION ALL
    SELECT
      'previous' AS period,
      sessions, purchases, revenue, users
    FROM prev_week
    """
    df = client.query(query).to_dataframe()

    current = df[df['period'] == 'current'].iloc[0]
    previous = df[df['period'] == 'previous'].iloc[0]

    return {
        'current': {
            'sessions': int(current['sessions']),
            'purchases': int(current['purchases']),
            'revenue': float(current['revenue'] or 0),
            'users': int(current['users']),
        },
        'previous': {
            'sessions': int(previous['sessions']),
            'purchases': int(previous['purchases']),
            'revenue': float(previous['revenue'] or 0),
            'users': int(previous['users']),
        }
    }

def fetch_channel_breakdown(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """チャネル別の内訳を取得する"""
    query = f"""
    SELECT
      IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
      COUNT(DISTINCT
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases,
      SUM(ecommerce.purchase_revenue) AS revenue
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY medium
    ORDER BY revenue DESC
    """
    return client.query(query).to_dataframe()
