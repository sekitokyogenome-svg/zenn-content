"""Claude Code × Google Sheets APIでBigQueryレポートを自動更新する

出典記事: articles/claude-code-sheets-api-bigquery-report.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: bq_to_sheets.py
目的: BigQueryの集計結果をGoogle Sheetsに自動書き込みする
作成日: 2026-03-30
依存: google-cloud-bigquery, gspread, pandas, python-dotenv
"""

import os
import gspread
import pandas as pd
from google.cloud import bigquery
from google.oauth2.service_account import Credentials
from dotenv import load_dotenv
from datetime import datetime

load_dotenv()

# 定数
SCOPES = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive',
    'https://www.googleapis.com/auth/bigquery.readonly',
]

def get_bq_client() -> bigquery.Client:
    """BigQueryクライアントを初期化する"""
    return bigquery.Client(project=os.getenv('BQ_PROJECT_ID'))

def get_sheets_client() -> gspread.Client:
    """Google Sheetsクライアントを初期化する"""
    creds = Credentials.from_service_account_file(
        os.getenv('GOOGLE_APPLICATION_CREDENTIALS'),
        scopes=SCOPES
    )
    return gspread.authorize(creds)

def fetch_weekly_sales(client: bigquery.Client) -> pd.DataFrame:
    """直近7日間の売上データをBigQueryから取得する"""
    project_id = os.getenv('BQ_PROJECT_ID')
    dataset = os.getenv('BQ_DATASET')

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
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY
      date, medium
    ORDER BY
      date DESC, revenue DESC
    """
    return client.query(query).to_dataframe()

def write_to_sheets(sheets_client: gspread.Client, df: pd.DataFrame, sheet_name: str = "週次レポート"):
    """DataFrameの内容をGoogle Sheetsに書き込む"""
    spreadsheet_id = os.getenv('SPREADSHEET_ID')
    spreadsheet = sheets_client.open_by_key(spreadsheet_id)

    # シートが存在しなければ作成
    try:
        worksheet = spreadsheet.worksheet(sheet_name)
    except gspread.exceptions.WorksheetNotFound:
        worksheet = spreadsheet.add_worksheet(
            title=sheet_name, rows=1000, cols=20
        )

    # 既存データをクリア
    worksheet.clear()

    # ヘッダー行を書き込み
    headers = df.columns.tolist()
    worksheet.update(range_name='A1', values=[headers])

    # データ行を書き込み
    # 日付型をstr変換（gspreadはdatetime非対応）
    df_str = df.copy()
    for col in df_str.select_dtypes(include=['datetime64', 'dbdate']).columns:
        df_str[col] = df_str[col].astype(str)

    values = df_str.values.tolist()
    if values:
        worksheet.update(
            range_name=f'A2:{ chr(64 + len(headers)) }{len(values) + 1}',
            values=values
        )

    # 更新日時をメタ情報として記録
    meta_row = len(values) + 3
    worksheet.update(
        range_name=f'A{meta_row}',
        values=[[f'最終更新: {datetime.now().strftime("%Y-%m-%d %H:%M")}']]
    )

    print(f"シート '{sheet_name}' に {len(values)} 行を書き込みました")

def main():
    try:
        bq_client = get_bq_client()
        sheets_client = get_sheets_client()

        df = fetch_weekly_sales(bq_client)

        if df.empty:
            print("データが取得できませんでした")
            return

        write_to_sheets(sheets_client, df)
        print("レポート更新完了")

    except Exception as e:
        print(f"エラーが発生しました: {e}")
        raise

if __name__ == "__main__":
    main()
