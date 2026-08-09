"""Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った

出典記事: articles/claude-code-mcp-ga4-slack-daily-report.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: daily_ga4_report.py
目的: GA4日次レポートをClaude APIで要約しSlackに送信する
作成日: 2026-03-29
依存: anthropic, google-cloud-bigquery, requests
"""

import os
import json
import requests
from datetime import date, timedelta
from google.cloud import bigquery
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()

def fetch_daily_data() -> list[dict]:
    """BigQueryから日次データを取得する"""
    client = bigquery.Client(project="your_project")
    query = open("queries/daily_report.sql").read()
    rows = client.query(query).result()
    return [dict(row) for row in rows]

def generate_summary(data: list[dict]) -> str:
    """Claude APIでデータを自然言語に要約する"""
    client = Anthropic()
    yesterday = (date.today() - timedelta(days=1)).strftime("%Y-%m-%d")

    prompt = f"""以下はGA4の日次レポート（{yesterday}分）です。
経営者向けに、3〜5行で要点を日本語でまとめてください。
特に前日比で大きな変化があれば強調してください。

データ:
{json.dumps(data, ensure_ascii=False, indent=2, default=str)}
"""
    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text
