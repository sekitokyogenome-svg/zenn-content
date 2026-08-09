"""Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った

出典記事: articles/claude-code-mcp-ga4-slack-daily-report.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
