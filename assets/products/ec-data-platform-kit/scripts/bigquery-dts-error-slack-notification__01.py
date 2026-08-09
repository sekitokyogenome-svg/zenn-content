"""BigQuery Data Transfer Serviceの転送エラーを自動検知してSlack通知する

出典記事: articles/bigquery-dts-error-slack-notification.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import base64
import json
import os
import requests
import functions_framework

SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL")

@functions_framework.cloud_event
def notify_dts_error(cloud_event):
    """Pub/SubメッセージからDTSエラー情報を取り出しSlackへ通知する"""

    # Pub/SubメッセージをデコードしてJSONとして取得
    raw_data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    log_entry = json.loads(raw_data)

    # ログエントリからエラー詳細を取得
    payload = log_entry.get("jsonPayload", {})
    resource = log_entry.get("resource", {}).get("labels", {})

    config_id = resource.get("config_id", "不明")
    project_id = resource.get("project_id", "不明")
    error_message = payload.get("errorStatus", {}).get("message", "エラー詳細なし")
    data_source = payload.get("dataSourceId", "不明")
    run_time = log_entry.get("timestamp", "不明")

    # Slackへ送るメッセージを組み立てる
    slack_message = {
        "text": "BigQuery DTS 転送エラーが発生しました",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "BigQuery DTS 転送エラー"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*プロジェクト*\n{project_id}"},
                    {"type": "mrkdwn", "text": f"*データソース*\n{data_source}"},
                    {"type": "mrkdwn", "text": f"*設定ID*\n{config_id}"},
                    {"type": "mrkdwn", "text": f"*発生時刻*\n{run_time}"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*エラー内容*\n```{error_message}```"
                }
            }
        ]
    }

    response = requests.post(
        SLACK_WEBHOOK_URL,
        json=slack_message,
        headers={"Content-Type": "application/json"}
    )

    if response.status_code != 200:
        raise RuntimeError(f"Slack通知に失敗しました: {response.status_code} {response.text}")
