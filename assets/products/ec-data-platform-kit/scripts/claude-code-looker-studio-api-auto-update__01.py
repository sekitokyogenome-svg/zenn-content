"""Claude Code × Looker Studio APIでダッシュボードを自動更新する

出典記事: articles/claude-code-looker-studio-api-auto-update.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
