"""BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】

出典記事: articles/bigquery-claude-code-anomaly-detection-alert.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: anomaly_alert.py
目的: BigQueryから日次メトリクスを取得し異常検知アラートを送信する
作成日: 2026-03-29
依存: google-cloud-bigquery, anthropic, slack_sdk, python-dotenv
"""

import os
from datetime import datetime
from google.cloud import bigquery
from slack_sdk import WebClient
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()

DEVIATION_THRESHOLD = float(os.getenv("ANOMALY_THRESHOLD", "-30"))

def run_anomaly_query():
    """BigQueryで異常検知クエリを実行し結果を返す"""
    client = bigquery.Client(project="your_project")

    query = """
    WITH daily_metrics AS (
      SELECT
        event_date,
        COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        )) AS sessions,
        IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
      FROM `your_project.analytics_XXXXXXXXX.events_*`
      WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      GROUP BY event_date
    ),
    with_moving_avg AS (
      SELECT *,
        AVG(sessions) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_sessions_7d,
        AVG(revenue) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_revenue_7d
      FROM daily_metrics
    )
    SELECT
      event_date, sessions, revenue,
      avg_sessions_7d, avg_revenue_7d,
      SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 AS session_deviation_pct,
      SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 AS revenue_deviation_pct
    FROM with_moving_avg
    WHERE event_date = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    """

    result = client.query(query).to_dataframe()
    return result

def check_anomaly(row):
    """閾値と比較して異常かどうか判定する"""
    alerts = []
    if row["session_deviation_pct"] < DEVIATION_THRESHOLD:
        alerts.append(f"セッション数が7日平均比 {row['session_deviation_pct']:.1f}% 減少")
    if row["revenue_deviation_pct"] < DEVIATION_THRESHOLD:
        alerts.append(f"売上が7日平均比 {row['revenue_deviation_pct']:.1f}% 減少")
    return alerts

def generate_alert_message(row, alerts):
    """Claude APIで人が読みやすいアラートメッセージを生成する"""
    client = Anthropic()

    prompt = f"""以下のEC売上異常データについて、日本語で簡潔なアラートメッセージを作成してください。
考えられる原因候補を3つ挙げてください。

日付: {row['event_date']}
セッション数: {row['sessions']}（7日平均: {row['avg_sessions_7d']:.0f}）
売上: ¥{row['revenue']:,.0f}（7日平均: ¥{row['avg_revenue_7d']:,.0f}）
検出された異常: {', '.join(alerts)}

フォーマット:
- 1行目にサマリ
- 箇条書きで原因候補
- 最後に推奨アクション"""

    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text

def send_slack_alert(text):
    """Slackにアラートを送信する"""
    client = WebClient(token=os.getenv("SLACK_BOT_TOKEN"))
    client.chat_postMessage(
        channel=os.getenv("SLACK_ALERT_CHANNEL", "#活動ログ"),
        text=f"🚨 売上異常検知アラート\n\n{text}"
    )

def main():
    df = run_anomaly_query()
    if df.empty:
        print("データなし。スキップします。")
        return

    row = df.iloc[0]
    alerts = check_anomaly(row)

    if not alerts:
        print(f"{row['event_date']}: 異常なし")
        return

    print(f"{row['event_date']}: 異常検知 - {alerts}")
    message = generate_alert_message(row, alerts)
    send_slack_alert(message)
    print("アラート送信完了")

if __name__ == "__main__":
    main()
