---
title: "Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った"
emoji: "📬"
type: "tech"
topics: ["claudecode", "bigquery", "slack"]
published: false
---

## はじめに

「毎朝GA4のダッシュボードを開いて、昨日のセッション数やCV数を目視で確認している」

この作業、地味に面倒ではないでしょうか。数字を見るだけなら数分で終わりますが、前日比を計算したり、チャネル別の変化を把握したりすると、気づけば15分以上かかっていることもあります。

この記事では、**BigQuery MCP × Claude Code × Slack Webhook** を組み合わせて、GA4の主要指標を毎朝Slackに自動通知する仕組みを構築した手順を紹介します。

---

## アーキテクチャ概要

全体の流れはシンプルです。

```text
BigQuery（GA4生データ）
    ↓  MCP経由でクエリ実行
Claude Code / Claude API
    ↓  クエリ結果を自然言語で要約
Slack Webhook
    ↓  フォーマット済みメッセージを投稿
cron / Cloud Scheduler で毎朝自動実行
```

ポイントは、BigQuery MCPサーバーを使うことで、Pythonスクリプトから直接BigQueryクライアントを叩く方法と比べて、**クエリ結果の解釈・要約までAIに任せられる**点です。

---

## BigQuery MCPサーバーのセットアップ

Claude Codeの設定ファイル（`~/.claude/settings.json`）にBigQuery MCPサーバーを追加します。

```json
{
  "mcpServers": {
    "bigquery": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/bigquery-mcp-server",
        "--project-id",
        "your-gcp-project-id",
        "--location",
        "asia-northeast1"
      ]
    }
  }
}
```

:::message
事前に `gcloud auth application-default login` でGCP認証を済ませておく必要があります。サービスアカウントを使う場合は `GOOGLE_APPLICATION_CREDENTIALS` 環境変数にJSONキーのパスを指定してください。
:::

設定後、Claude Codeを再起動すれば、BigQueryへのクエリ実行が可能になります。

---

## 日次レポート用SQLクエリ

毎朝Slackに通知したい指標として、以下を取得するクエリを用意しました。

- セッション数（前日比）
- コンバージョン数（前日比）
- 売上金額（前日比）
- チャネル別セッション数

```sql
WITH yesterday AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  GROUP BY channel
),
day_before AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 2 DAY)
  GROUP BY channel
)
SELECT
  y.channel,
  y.sessions,
  y.conversions,
  y.revenue,
  SAFE_DIVIDE(y.sessions - d.sessions, d.sessions) * 100 AS sessions_change_pct,
  SAFE_DIVIDE(y.conversions - d.conversions, d.conversions) * 100 AS conversions_change_pct
FROM yesterday y
LEFT JOIN day_before d USING (channel)
ORDER BY y.sessions DESC
```

このクエリはstaging層の `stg_sessions` ビューを参照しています。raw層のイベントデータを直接触らないため、メンテナンスが容易です。

---

## Claude APIで自然言語サマリーを生成

クエリ結果をそのまま数字で送っても、毎朝読むのは疲れます。Claude APIに結果を渡して、ビジネス視点の要約を生成させます。

```python
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
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text
```

:::message alert
Claude APIキー（`ANTHROPIC_API_KEY`）は `.env` ファイルに保存し、コードにハードコードしないでください。
:::

---

## Slack Webhookで通知を送信

Slack Appを作成し、Incoming Webhookを有効化してWebhook URLを取得します。

```python
def send_to_slack(summary: str, data: list[dict]):
    """Slack Webhookでレポートを送信する"""
    webhook_url = os.environ["SLACK_WEBHOOK_URL"]
    yesterday = (date.today() - timedelta(days=1)).strftime("%Y-%m-%d")

    # チャネル別サマリーをテーブル形式で作成
    table_lines = ["チャネル | セッション | CV | 前日比"]
    table_lines.append("--- | --- | --- | ---")
    for row in data:
        change = row.get("sessions_change_pct")
        change_str = f"{change:+.1f}%" if change is not None else "-"
        table_lines.append(
            f"{row['channel']} | {row['sessions']} | {row['conversions']} | {change_str}"
        )

    payload = {
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": f"📊 GA4日次レポート（{yesterday}）"}
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": summary}
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": "```\n" + "\n".join(table_lines) + "\n```"}
            }
        ]
    }

    try:
        resp = requests.post(webhook_url, json=payload, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"Slack送信エラー: {e}")
        raise

if __name__ == "__main__":
    data = fetch_daily_data()
    summary = generate_summary(data)
    send_to_slack(summary, data)
    print("レポート送信完了")
```

---

## cron / Cloud Schedulerで毎朝自動実行

### ローカル（cron）の場合

```bash
# crontab -e で以下を追加（毎朝7:00 JST）
0 7 * * * cd /path/to/project && /path/to/venv/bin/python daily_ga4_report.py >> /path/to/logs/daily_report.log 2>&1
```

### Cloud Schedulerの場合

Cloud RunやCloud Functionsにデプロイし、Cloud Schedulerからトリガーする構成が安定します。

```bash
# Cloud Schedulerジョブの作成例
gcloud scheduler jobs create http ga4-daily-report \
  --schedule="0 7 * * *" \
  --time-zone="Asia/Tokyo" \
  --uri="https://your-cloud-run-service-url/report" \
  --http-method=POST \
  --oidc-service-account-email="your-sa@project.iam.gserviceaccount.com"
```

:::message
ローカルPCのcronはマシンが起動していないと実行されません。安定運用にはCloud Schedulerの利用を推奨します。
:::

---

## Slack通知の出力例

実際にSlackに届くメッセージは以下のようなイメージです。

```text
📊 GA4日次レポート（2026-03-28）

昨日のセッション数は342で、前日比+12.5%と増加しています。
Organic Searchが主な増加要因で、前日比+23%でした。
CVは5件で横ばいですが、Directチャネルからの
CV率がやや低下傾向にあるため注視が必要です。

チャネル       | セッション | CV | 前日比
------------- | -------- | -- | ------
Organic Search | 185      | 3  | +23.0%
Direct         | 87       | 1  | -5.4%
Referral       | 42       | 1  | +10.5%
Social         | 28       | 0  | +7.7%
```

チーム全員が同じ数字を毎朝目にすることで、異変への気づきが早くなります。

---

## まとめ

BigQuery MCP × Claude API × Slack Webhookの組み合わせで、GA4の日次レポートを自動化しました。

- **BigQuery MCP**でClaude Codeから直接GA4データにアクセス
- **Claude API**で数字の羅列をビジネス視点の要約に変換
- **Slack Webhook**でチームに毎朝自動配信
- **Cloud Scheduler**で安定した定期実行

ダッシュボードを開く手間がなくなるだけでなく、AIが前日比の変化点を自動でハイライトしてくれるため、異常検知としても機能します。

GA4×BigQueryの基盤構築やレポート自動化のご依頼は、以下のサービスページからお気軽にご相談ください。

https://coconala.com/services/554778
