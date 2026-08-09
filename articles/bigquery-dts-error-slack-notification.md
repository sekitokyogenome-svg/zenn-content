---
title: "BigQuery Data Transfer Serviceの転送エラーを自動検知してSlack通知する"
emoji: "🔔"
type: "tech"
topics: ["bigquery","googlecloud","dataengineering","python","slack"]
published: false
---

## はじめに

BigQuery Data Transfer Service（以下、DTS）を使ってGA4やGoogle広告のデータを定期的にBigQueryへ転送しているチームは多いと思います。しかし「昨日の転送が失敗していたことに気づかず、レポートが古いデータのまま共有されていた」という経験はないでしょうか。

DTSの転送ジョブは基本的に夜間や早朝に自動実行されるため、エラーが発生してもすぐに気づくことができません。Google Cloud Consoleを毎朝確認する運用は現実的ではなく、問題に気づくのが翌日以降になるケースも珍しくありません。

本記事では、DTSの転送ログをCloud Loggingで捕捉し、エラー発生時にSlackへ自動通知する仕組みを構築する手順を解説します。Python製のCloud Functionsと合わせて活用することで、ノーコードに近い形でアラート体制を整えることができます。非エンジニアの方でも手順に沿って進めれば実装できるよう、できるだけ丁寧に説明しています。

---

## BigQuery DTSのエラーログの仕組みを理解する

DTSがデータ転送ジョブを実行すると、その結果はCloud Loggingに自動的に記録されます。ログの種類には成功（SUCCESS）・警告（WARNING）・失敗（FAILED）があり、FAILEDのログが記録されたタイミングでSlackへ通知を送ることが今回の目標です。

ログのリソースタイプは `bigquery_dts_config` となっており、以下のようなフィルタでCloud Loggingから絞り込めます。

```
resource.type="bigquery_dts_config"
jsonPayload.state="FAILED"
```

Cloud Loggingのログエクスプローラでこのフィルタを試すと、失敗した転送ジョブのエントリが一覧表示されます。まずはコンソールで確認し、自分の環境で正しく記録されているかどうかを確認しておきましょう。

ログエントリには転送設定名（displayName）・転送先データセット・エラーメッセージなどが含まれており、Slack通知の本文として活用できます。

---

## Cloud Pub/SubとLog Sinkで転送エラーをトリガーする

エラーログを検知するには、Cloud LoggingのログシンクをPub/Subトピックと連携させます。ログシンクは特定の条件にマッチしたログエントリをリアルタイムでPub/Subへ転送する機能で、これによってCloud Functionsをトリガーできます。

### Pub/Subトピックの作成

```bash
gcloud pubsub topics create dts-error-alert
```

### ログシンクの作成

```bash
gcloud logging sinks create dts-error-sink \
  pubsub.googleapis.com/projects/YOUR_PROJECT_ID/topics/dts-error-alert \
  --log-filter='resource.type="bigquery_dts_config" jsonPayload.state="FAILED"'
```

`YOUR_PROJECT_ID` はご自身のGoogle CloudプロジェクトIDに置き換えてください。

シンクを作成すると、Pub/Subトピックへの書き込み権限をログシンク用のサービスアカウントに付与する必要があります。コマンド実行後に表示される `serviceAccount:` のメールアドレスをコピーし、Pub/SubトピックのIAM設定で「Pub/Sub パブリッシャー」ロールを付与してください。

:::message
ログシンクのサービスアカウントへのIAM付与を忘れると、ログがPub/Subに届かず通知が届きません。シンク作成直後にIAM設定まで済ませておきましょう。
:::

---

## Cloud FunctionsでSlackへ通知するPythonコードを書く

Pub/Subトピックにメッセージが届いたタイミングでCloud Functionsが起動し、Slack Incoming Webhookへ通知を送る実装を作成します。

### ディレクトリ構成

```
dts-alert/
├── main.py
└── requirements.txt
```

### requirements.txt

```
functions-framework==3.*
requests==2.*
```

### main.py

```python
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
```

### Cloud Functionsへのデプロイ

```bash
gcloud functions deploy notify-dts-error \
  --gen2 \
  --runtime=python311 \
  --region=asia-northeast1 \
  --source=./dts-alert \
  --entry-point=notify_dts_error \
  --trigger-topic=dts-error-alert \
  --set-env-vars=SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

`SLACK_WEBHOOK_URL` にはSlackアプリのIncoming Webhook URLを設定してください。

:::message
Slack Incoming WebhookのURLは外部に漏れると第三者がメッセージを送れてしまいます。本番環境ではSecret Managerを使って環境変数として安全に管理することをお勧めします。
:::

---

## Slack Incoming Webhookの設定方法

Slackへの通知を送るには、事前にIncoming Webhookを設定しておく必要があります。

1. [Slack API](https://api.slack.com/apps) にアクセスし、「Create New App」→「From scratch」を選択します。
2. アプリ名（例：`BQ DTS Alert`）とワークスペースを選択して作成します。
3. 左メニューから「Incoming Webhooks」を選択し、「Activate Incoming Webhooks」をオンにします。
4. 「Add New Webhook to Workspace」をクリックし、通知を受け取りたいチャンネルを選択します。
5. 発行されたWebhook URLをコピーし、Cloud Functionsのデプロイコマンドに貼り付けます。

無料プランのSlackでも利用可能で、特別な権限なくチャンネルへの通知が設定できます。

---

## 動作確認とよくあるトラブルシュート

実装が完了したら、意図的にエラーを発生させて通知が届くか確認しましょう。DTSの転送設定で「今すぐ転送」を実行し、その後Cloud Loggingでエラーログが記録されることを確認してから、Slackに通知が届くかどうかを確認します。

通知が届かない場合は、以下の点を順番に確認してください。

| 確認項目 | 確認方法 |
|---|---|
| ログシンクのIAM設定 | Pub/SubトピックのIAMにシンクのサービスアカウントが登録されているか |
| Cloud Functionsのログ | Cloud ConsoleでFunctionsのログを確認し、エラーが出ていないか |
| Webhook URLの正確性 | 環境変数のURLが正しくコピーされているか |
| ログフィルタの一致 | ログエクスプローラで対象ログが実際に表示されるか |

Cloud Functionsのログは `gcloud functions logs read notify-dts-error --gen2 --region=asia-northeast1` で確認できます。

---

## まとめ

本記事では、BigQuery Data Transfer Serviceの転送エラーを自動的に検知してSlackへ通知する仕組みを構築する手順を解説しました。要点を整理します。

- DTSのエラーログはCloud Loggingに自動記録されるため、ログシンクで捕捉できる
- ログシンク→Pub/Sub→Cloud Functionsの連携によりリアルタイムなアラートが実現する
- PythonのCloud Functionsは比較的少ないコードで実装でき、メンテナンスも容易
- Slack Incoming Webhookは無料で利用でき、既存のチャンネルへ通知を送れる

この仕組みを導入すると、転送エラーに気づかずレポートが止まったままになるリスクを大幅に低減できます。次のステップとして、エラーの種類に応じて通知チャンネルを分ける・エラーが続く場合はPagerDutyと連携するといった発展的な構成も検討してみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
