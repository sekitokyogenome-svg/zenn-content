"""Claude CodeのAgentモードでEC売上データを自動分析させた結果

出典記事: articles/claude-code-agent-mode-ec-sales-analysis.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: ec_sales_report.py
目的: BigQueryからEC売上データを取得し月次レポートを生成する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
from datetime import datetime, timedelta

def fetch_sales_data(client: bigquery.Client, project_id: str, dataset: str, days: int = 30) -> pd.DataFrame:
    """直近N日間の売上データをBigQueryから取得する"""
    query = f"""
    SELECT
      PARSE_DATE('%Y%m%d', event_date) AS date,
      collected_traffic_source.manual_medium AS medium,
      COUNT(DISTINCT
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases,
      SUM(ecommerce.purchase_revenue) AS revenue
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL {days} DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY
      date, medium
    ORDER BY
      date DESC, revenue DESC
    """
    return client.query(query).to_dataframe()

def generate_markdown_report(df: pd.DataFrame) -> str:
    """DataFrameからMarkdownレポートを生成する"""
    total_revenue = df['revenue'].sum()
    total_purchases = df['purchases'].sum()
    total_sessions = df['sessions'].sum()
    cvr = (total_purchases / total_sessions * 100) if total_sessions > 0 else 0

    report = f"""# EC売上レポート（直近30日間）

## サマリー
- 売上合計: ¥{total_revenue:,.0f}
- 購入数: {total_purchases}件
- セッション数: {total_sessions:,}
- CVR: {cvr:.1f}%

## チャネル別内訳
| チャネル | セッション | 売上 | CVR |
|----------|-----------|------|-----|
"""
    channel_data = df.groupby('medium').agg({
        'sessions': 'sum',
        'revenue': 'sum',
        'purchases': 'sum'
    }).reset_index()

    for _, row in channel_data.iterrows():
        ch_cvr = (row['purchases'] / row['sessions'] * 100) if row['sessions'] > 0 else 0
        report += f"| {row['medium']} | {row['sessions']:,} | ¥{row['revenue']:,.0f} | {ch_cvr:.1f}% |\n"

    return report
