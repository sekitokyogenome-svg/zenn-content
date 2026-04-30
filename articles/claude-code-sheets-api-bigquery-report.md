---
title: "Claude Code × Google Sheets APIでBigQueryレポートを自動更新する"
emoji: "📝"
type: "tech"
topics: ["claudecode","bigquery","googlesheets"]
published: true
---

## はじめに

「BigQueryで分析した結果を、毎回手動でスプレッドシートに貼り付けている」

この作業、意外と多くの現場で発生しています。経営者やマーケティング担当者はスプレッドシートでデータを確認したい。でも分析担当者はBigQueryで集計したい。この橋渡しを手作業で行うのは非効率です。

本記事では、Claude Codeを使ってBigQueryの集計結果をGoogle Sheetsに自動書き込みするPythonスクリプトを構築した方法を紹介します。

## 前提条件

- Google Cloud Projectが作成済みであること
- BigQueryにGA4のエクスポートデータが存在すること
- Google Sheets APIとGoogle Drive APIが有効化されていること
- サービスアカウントの認証情報（JSONキー）が準備されていること

## Step 1: Google Sheets API の認証設定

### サービスアカウントの作成

Google Cloud Consoleから以下の手順で設定します。

1. 「IAMと管理」→「サービスアカウント」からアカウントを作成
2. 「キー」タブからJSONキーをダウンロード
3. ダウンロードしたJSONファイルをプロジェクトの安全な場所に配置

:::message
サービスアカウントのJSONキーは絶対にGitにコミットしないでください。`.gitignore` に追加し、パスは `.env` ファイルで管理します。
:::

### 環境変数の設定

`.env` ファイルに以下を追加します。

```bash
GOOGLE_APPLICATION_CREDENTIALS=path/to/service-account-key.json
BQ_PROJECT_ID=your-project-id
BQ_DATASET=analytics_123456789
SPREADSHEET_ID=your-spreadsheet-id
```

### スプレッドシートの共有設定

作成したサービスアカウントのメールアドレス（`xxx@project.iam.gserviceaccount.com`）に対して、対象のスプレッドシートを「編集者」として共有します。これを忘れると書き込み時にPermission Errorが発生します。

## Step 2: BigQueryからデータを取得するSQL

日次の売上サマリーをBigQueryから取得するSQLを用意します。

```sql
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
```

:::message
`_TABLE_SUFFIX` によるパーティションフィルタは、BigQueryのクエリコスト削減に直結します。全期間スキャンを避けるため、分析対象期間に合わせたフィルタを入れることを推奨します。
:::

## Step 3: Pythonスクリプトの実装

Claude Codeに以下のように指示してスクリプトを生成しました。

```bash
claude "BigQueryから週次売上データを取得して、
Google Sheetsの指定シートに自動で書き込むPythonスクリプトを作って。
gspreadライブラリを使って。"
```

生成されたスクリプト：

```python
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
```

## Step 4: 複数シートへの書き分け

実運用では、サマリーシート・チャネル別シート・日別詳細シートなど複数のシートにデータを書き分けたいケースがあります。

```python
def update_all_sheets(bq_client: bigquery.Client, sheets_client: gspread.Client):
    """複数のシートを一括更新する"""
    df = fetch_weekly_sales(bq_client)

    if df.empty:
        print("データなし")
        return

    # サマリーシート
    summary = df.groupby('medium').agg({
        'sessions': 'sum',
        'purchases': 'sum',
        'revenue': 'sum'
    }).reset_index()
    summary['cvr'] = (summary['purchases'] / summary['sessions'] * 100).round(2)
    write_to_sheets(sheets_client, summary, sheet_name="チャネル別サマリー")

    # 日別詳細シート
    daily = df.groupby('date').agg({
        'sessions': 'sum',
        'purchases': 'sum',
        'revenue': 'sum'
    }).reset_index()
    write_to_sheets(sheets_client, daily, sheet_name="日別詳細")

    # 全データシート
    write_to_sheets(sheets_client, df, sheet_name="RAWデータ")
```

## Step 5: 定期実行の設定

スクリプトが完成したら、定期実行を設定します。

### cronで実行する場合（Linux/Mac）

```bash
# 毎週月曜 9:00に実行
0 9 * * 1 cd /path/to/project && python scripts/bq_to_sheets.py >> logs/sheets_update.log 2>&1
```

### タスクスケジューラで実行する場合（Windows）

```bash
# PowerShellでタスクを登録
schtasks /create /tn "BQ_to_Sheets" /tr "python C:\path\to\bq_to_sheets.py" /sc weekly /d MON /st 09:00
```

### Cloud Schedulerで実行する場合

Cloud Functions化してCloud Schedulerからトリガーする方法もあります。ローカルPCが起動していなくても実行できるため、運用の安定性が向上します。

## エラーハンドリングの強化

本番運用では、API呼び出しの失敗に備えたリトライ処理を追加しておきます。

```python
import time

def write_with_retry(sheets_client, df, sheet_name, max_retries=3):
    """リトライ付きのシート書き込み"""
    for attempt in range(max_retries):
        try:
            write_to_sheets(sheets_client, df, sheet_name)
            return
        except gspread.exceptions.APIError as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt * 10  # 10秒, 20秒, 40秒
                print(f"API制限エラー。{wait_time}秒後にリトライします（{attempt + 1}/{max_retries}）")
                time.sleep(wait_time)
            else:
                print(f"リトライ上限に達しました: {e}")
                raise
```

:::message
Google Sheets APIには1分あたり60リクエストの制限があります。大量のデータを書き込む場合は、バッチ更新（`batch_update`）を使うか、書き込み間隔を調整してください。
:::

## まとめ

BigQueryの分析結果をGoogle Sheetsに自動反映する仕組みは、以下のステップで構築できます。

1. サービスアカウントの認証を設定する
2. BigQueryから集計データを取得するSQLを用意する
3. gspreadライブラリでシートへの書き込み処理を実装する
4. 定期実行とエラーハンドリングを設定する

「分析結果を見たい人」と「分析を行う人」の間の手作業を排除することで、データの鮮度が上がり、意思決定のスピードも向上します。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
