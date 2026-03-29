---
title: "Claude Code × Looker Studio APIでダッシュボードを自動更新する"
emoji: "📈"
type: "tech"
topics: ["claudecode", "lookerstudio", "automation"]
published: false
---

## はじめに

「Looker Studioのダッシュボード、データソースの更新を手動でやっていて面倒」

Looker Studioはノーコードで美しいダッシュボードを作れる便利なツールです。しかし、データソースの追加・変更やフィルタの更新を手動で行っている方は多いのではないでしょうか。

この記事では、Looker Studio APIの概要と、Claude Codeを組み合わせてデータソースの更新を自動化する方法を紹介します。

---

## Looker Studio APIの現状

2026年3月時点で、Looker StudioにはREST APIが提供されています。主に以下の操作が可能です。

- **データソースの一覧取得・作成・更新**
- **レポートの一覧取得・メタデータの参照**
- **権限の管理**

:::message
Looker Studio APIはまだ機能が限られており、レポート内のチャートやフィルタの操作はAPIではサポートされていません。データソースレベルでの自動化が現実的なアプローチです。
:::

---

## なぜClaude Codeを組み合わせるのか

Looker Studio API単体では「データソースの設定を更新する」ことしかできません。しかし、Claude Codeと組み合わせることで、以下のワークフローが実現できます。

1. BigQueryのテーブル構造変更を検知する
2. 変更に応じたデータソース更新コードを自動生成する
3. API経由でLooker Studioのデータソースを更新する
4. 更新結果をSlackに通知する

---

## Step 1：Looker Studio API のセットアップ

### GCPプロジェクトでAPIを有効化

```bash
# Looker Studio APIを有効化
gcloud services enable datastudio.googleapis.com \
  --project=your-project-id
```

### サービスアカウントの作成

```bash
# サービスアカウントを作成
gcloud iam service-accounts create looker-studio-updater \
  --display-name="Looker Studio自動更新用"

# キーを生成
gcloud iam service-accounts keys create credentials.json \
  --iam-account=looker-studio-updater@your-project-id.iam.gserviceaccount.com
```

:::message
`credentials.json` は `.gitignore` に追加し、リポジトリにコミットしないでください。
:::

---

## Step 2：データソースの一覧を取得する

PythonでLooker Studio APIにアクセスし、既存のデータソースを確認します。

```python
"""
モジュール名: looker_studio_datasources.py
目的: Looker Studioのデータソース一覧を取得する
作成日: 2026-03-30
依存: google-auth, requests
"""

from google.oauth2 import service_account
from google.auth.transport.requests import Request
import requests

SCOPES = ["https://www.googleapis.com/auth/datastudio"]

def get_credentials():
    """サービスアカウント認証情報を取得する"""
    credentials = service_account.Credentials.from_service_account_file(
        "credentials.json", scopes=SCOPES
    )
    credentials.refresh(Request())
    return credentials

def list_datasources():
    """データソース一覧を取得する"""
    creds = get_credentials()
    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json"
    }

    url = "https://datastudio.googleapis.com/v1/datasources"
    response = requests.get(url, headers=headers)
    response.raise_for_status()

    datasources = response.json().get("datasources", [])
    for ds in datasources:
        print(f"ID: {ds['id']}, Name: {ds.get('name', 'N/A')}")
    return datasources

if __name__ == "__main__":
    list_datasources()
```

---

## Step 3：BigQueryテーブル変更を検知する

BigQueryの`INFORMATION_SCHEMA`を使い、テーブルのカラム変更を検知します。

```sql
-- テーブルのカラム情報を取得
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM `project.dataset.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'your_table'
ORDER BY ordinal_position;
```

Pythonスクリプトで前回と今回のスキーマを比較します。

```python
from google.cloud import bigquery

def detect_schema_changes(
    project: str, dataset: str, table: str
) -> list:
    """テーブルのスキーマ変更を検知する"""
    client = bigquery.Client()

    # 現在のスキーマを取得
    table_ref = client.get_table(f"{project}.{dataset}.{table}")
    current_schema = [
        {"name": field.name, "type": field.field_type}
        for field in table_ref.schema
    ]

    # 前回のスキーマを読み込む（JSONファイルに保存しておく）
    import json
    schema_file = f"schemas/{dataset}_{table}.json"
    try:
        with open(schema_file, "r") as f:
            previous_schema = json.load(f)
    except FileNotFoundError:
        previous_schema = []

    # 差分を検出
    current_names = {col["name"] for col in current_schema}
    previous_names = {col["name"] for col in previous_schema}

    added = current_names - previous_names
    removed = previous_names - current_names

    # 現在のスキーマを保存
    with open(schema_file, "w") as f:
        json.dump(current_schema, f, indent=2)

    changes = []
    if added:
        changes.append(f"追加カラム: {', '.join(added)}")
    if removed:
        changes.append(f"削除カラム: {', '.join(removed)}")

    return changes
```

---

## Step 4：Claude Codeでデータソース更新コードを生成する

スキーマ変更が検知された場合、Claude Codeに対応するデータソース更新の方法を生成させます。

```text
BigQueryテーブル `project.dataset.mart_traffic` に
以下のカラムが追加されました:
- bounce_rate (FLOAT64)
- avg_session_duration (FLOAT64)

Looker Studioのデータソース（ID: xxxx）を更新して、
新しいカラムをダッシュボードで使えるようにする
Pythonコードを書いてください。
```

Claude Codeが生成するコード例:

```python
def update_datasource_fields(
    datasource_id: str,
    new_fields: list
) -> dict:
    """データソースにフィールドを追加する"""
    creds = get_credentials()
    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json"
    }

    url = f"https://datastudio.googleapis.com/v1/datasources/{datasource_id}"

    # 現在のデータソース情報を取得
    current = requests.get(url, headers=headers).json()

    # フィールドを追加
    fields = current.get("fields", [])
    for field in new_fields:
        fields.append({
            "name": field["name"],
            "type": field["type"],
            "description": field.get("description", "")
        })

    # 更新リクエスト
    payload = {"fields": fields}
    response = requests.patch(url, headers=headers, json=payload)
    response.raise_for_status()
    return response.json()
```

---

## Step 5：Slack通知で完了を知らせる

データソースの更新が完了したら、Slackに通知します。

```python
def notify_update_result(
    changes: list, success: bool
) -> None:
    """データソース更新結果をSlackに通知する"""
    webhook_url = os.getenv("SLACK_WEBHOOK_URL")
    status = "成功" if success else "失敗"
    emoji = "✅" if success else "❌"

    text = f"{emoji} Looker Studioデータソース更新: {status}\n"
    text += "\n".join(f"- {change}" for change in changes)

    requests.post(webhook_url, json={"text": text})
```

---

## 全体をつなげる自動化スクリプト

```python
def main():
    """メインフロー"""
    # 1. スキーマ変更を検知
    changes = detect_schema_changes(
        "your-project", "your_dataset", "mart_traffic"
    )

    if not changes:
        print("スキーマに変更はありません")
        return

    print(f"変更を検知: {changes}")

    # 2. データソースを更新
    try:
        update_datasource_fields(
            datasource_id="your-datasource-id",
            new_fields=[
                {"name": "bounce_rate", "type": "NUMBER"},
                {"name": "avg_session_duration", "type": "NUMBER"}
            ]
        )
        notify_update_result(changes, success=True)
    except Exception as e:
        print(f"更新エラー: {e}")
        notify_update_result(changes, success=False)

if __name__ == "__main__":
    main()
```

---

## 運用上の注意点

### APIの制限を理解しておく

Looker Studio APIにはレート制限があります。大量のデータソースを一度に更新する場合は、リクエスト間に適切な間隔を設けてください。

### 手動確認は残す

自動更新後は、Looker Studio上で実際にダッシュボードが正しく表示されているかを目視確認する運用を推奨します。

### テスト環境での検証

本番のダッシュボードに影響が出ないよう、テスト用のデータソースで動作確認をしてから本番に適用してください。

---

## まとめ

Looker Studio API × Claude Codeで、データソースの更新を自動化する方法を紹介しました。

1. BigQueryのスキーマ変更を検知する
2. Claude Codeでデータソース更新コードを生成する
3. API経由で自動更新し、Slackに通知する

ダッシュボードの運用保守にかかる手間を減らし、分析に集中できる環境を作りましょう。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
