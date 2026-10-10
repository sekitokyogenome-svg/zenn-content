---
title: "Looker Studio APIでできること — レポートの棚卸しと権限管理をPythonで自動化する"
emoji: "📈"
type: "tech"
topics: ["lookerstudio", "python", "bigquery", "claudecode"]
published: true
---

:::message
2026-10-10 に、記事の中核を全面的に修正しました。変更点: (1) 旧版で紹介していた「データソースの一覧取得・更新」「フィールド追加」のエンドポイントは公式 API に存在しないため削除し、実在する `assets:search` と `permissions` のコードに差し替えました。(2) 認証をサービスアカウント単体ではなく、ドメイン全体委任が必要な手順に直しました。(3) 「ダッシュボードの最新化」を実現する方法を、BigQuery のスケジュールクエリ・データの鮮度設定・スケジュール配信として整理しました。
:::

## この記事でわかること

- Looker Studio API で実際にできること・できないこと
- レポートの棚卸し（更新が止まったレポートの洗い出し）と、権限の確認・追加を Python で行う流れ
- 「ダッシュボードを自動で最新にしたい」ときの、API ではない正しい手段

## 前提

- 利用できるのは **Google Workspace または Cloud Identity の組織に所属するユーザー**です。個人の Gmail だけでは API の認証が通りません
- ドメイン全体委任の許可には **Workspace 管理者の操作**が必要です
- Python 3.9 以上、`google-auth` と `requests` を使います
- API 自体の利用料金は公式ドキュメントに記載を確認できませんでした。BigQuery 側の費用は後半の表を参照してください

---

## 最初に結論：API でできること・できないこと

公式リファレンスに載っている公開メソッドは次の5つだけです（ベース URL は `https://datastudio.googleapis.com/v1`）。

| 区分 | メソッド | HTTP | できること |
|---|---|---|---|
| 資産 | `assets:search` | GET `/assets:search` | レポート / データソースのメタデータ検索 |
| 権限 | `permissions.get` | GET `/assets/{assetName}/permissions` | 資産の権限の取得 |
| 権限 | `permissions.patch` | PATCH `/assets/{assetName}/permissions` | 権限の更新 |
| 権限 | `permissions:addMembers` | POST `/assets/{assetName}/permissions:addMembers` | ロールへメンバーを追加 |
| 権限 | `permissions:revokeAllPermissions` | POST `/assets/{assetName}/permissions:revokeAllPermissions` | 権限の全削除 |

逆に、次の操作は API では行えません。

| やりたいこと | API | 代わりの手段 |
|---|---|---|
| データソースの作成・更新 | 不可 | GUI、またはコネクタ側の設定 |
| データソースへのフィールド追加 | 不可 | GUI の「フィールドを更新」 |
| チャート・フィルタ・セクションの操作や取得 | 不可（公式も「フィルタ・セクション・ディメンション等は取得できない」と記載） | GUI |
| データの更新タイミングの制御 | 不可 | 後述の「データの鮮度」設定など |

つまり、API が得意なのは「**資産の棚卸し**」と「**権限の管理**」です。ダッシュボードの中身を書き換える用途には使えません。

---

## 認証：ドメイン全体委任が必要

公式の「Data Studio API」ページ（https://developers.google.com/looker-studio/integrate/api ）に書かれている条件は次のとおりです。

- アプリは OAuth 2.0 のアクセストークンを使う
- Workspace 管理者が、Admin コンソールの**ドメイン全体委任**で、アプリの OAuth クライアント ID とスコープを許可する
- 許可が無いユーザーには `Error 400: invalid_scope` が返る

使えるスコープは次のとおりです。

| スコープ | 用途 |
|---|---|
| `https://www.googleapis.com/auth/datastudio.readonly` | 読み取りのみ（検索・権限の取得）。管理しないアプリには公式もこちらを推奨 |
| `https://www.googleapis.com/auth/datastudio` | 資産の管理（`addMembers` はこちらが必要） |

### 手順

1. Google Cloud のプロジェクトで **Data Studio API**（`datastudio.googleapis.com`）を有効にする
2. OAuth 同意画面を設定する（公式の手順では **Internal**）
3. 認証情報で OAuth クライアント ID を作成し、ID を控える
4. Workspace 管理者が Admin コンソールの「ドメイン全体の委任」で、そのクライアント ID とスコープを許可する
5. 実行時に、委任するユーザー（レポートの閲覧・編集権限を持つ人）を指定してトークンを取得する

```bash
# Data Studio API を有効化する
gcloud services enable datastudio.googleapis.com --project=your-project-id
```

サービスアカウントを使う場合は、サービスアカウント自体を作っただけでは動きません。ドメイン全体委任で許可されたうえで、`subject=`（委任ユーザー）を指定する必要があります。許可が無いと `invalid_scope` で失敗します。なお公式ページはサービスアカウントについて記載していません。ここで示す方法は、Google の一般的なドメイン全体委任の仕組みを Data Studio API に当てはめたものです。自分の環境で動くかは、先に読み取り専用スコープで試してください。

:::message
サービスアカウントのキー（`credentials.json`）は `.gitignore` に追加し、リポジトリにコミットしないでください。
:::

---

## レポートの棚卸し：更新が止まったレポートを洗い出す

`assets:search` の公式仕様は次のとおりです。

- `assetTypes`: 必須。**1つだけ**指定（`REPORT` または `DATA_SOURCE`）
- `title`: 任意。タイトルと説明で検索。`owner:` や `creator:` などのフィルタも使える
- `includeTrashed`: 任意。`true` はゴミ箱内だけ、`false`（既定）はゴミ箱外だけ
- `pageSize`: 既定 1000 / `pageToken`: ページ送り
- レスポンスは `assets` 配列と `nextPageToken`
- 資産の要素は `name`（資産 ID）、`title`、`owner`、`creator`、`createTime`、`updateTime`、`assetType`、`trashed` など。`id` という項目は無い

次のコードは、レポートを全件取得し、最終更新が 180 日より前のものを一覧にします。

```python
# レポートを全件取得し、updateTime が古いものを抽出する
import re
from datetime import datetime, timedelta, timezone

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

SCOPES = ["https://www.googleapis.com/auth/datastudio.readonly"]
BASE_URL = "https://datastudio.googleapis.com/v1"


def get_token(key_file: str, delegated_user: str) -> str:
    """ドメイン全体委任で、delegated_user としてのトークンを取得する"""
    creds = service_account.Credentials.from_service_account_file(
        key_file, scopes=SCOPES, subject=delegated_user
    )
    creds.refresh(Request())
    return creds.token


def search_reports(token: str) -> list:
    """assets:search でレポートのメタデータを全ページ分取得する"""
    headers = {"Authorization": f"Bearer {token}"}
    params = {"assetTypes": "REPORT"}
    assets = []
    while True:
        res = requests.get(f"{BASE_URL}/assets:search", headers=headers, params=params)
        res.raise_for_status()
        body = res.json()
        assets.extend(body.get("assets", []))
        next_token = body.get("nextPageToken")
        if not next_token:
            return assets
        params["pageToken"] = next_token


def parse_time(value: str) -> datetime:
    """RFC 3339 形式の時刻を datetime にする（秒未満は6桁に切り詰める）"""
    value = re.sub(r"(\.\d{6})\d+", r"\1", value).replace("Z", "+00:00")
    return datetime.fromisoformat(value)


def find_stale(assets: list, days: int = 180) -> list:
    """updateTime が days 日より前のレポートを返す"""
    limit = datetime.now(timezone.utc) - timedelta(days=days)
    return [a for a in assets if parse_time(a["updateTime"]) < limit]


if __name__ == "__main__":
    token = get_token("credentials.json", "admin@your-domain.example")
    reports = search_reports(token)
    for a in find_stale(reports):
        print(a["name"], a["title"], a["owner"], a["updateTime"])
```

出力されるのは `name`（資産 ID）・`title`・`owner`・`updateTime` です。`updateTime` は「誰かが最後に更新した時刻」で、**閲覧されたかどうかではありません**。「更新されていない」と「使われていない」は別なので、削除の判断材料にはなりません。

### Claude Code の使いどころ

この棚卸し結果（数十〜数百行の一覧）を Claude Code に渡して、「オーナー別に整理して」「タイトルの命名規則から用途を推定して」と要約させる使い方は現実的です。ただし、Claude Code が API を呼んでダッシュボードを更新してくれるわけではありません。自分は、上のようなスクリプトのたたき台の生成と、出力の要約に使っています。生成されたコードは、必ず公式リファレンスの署名と照らして確認してください。

---

## 権限の確認と追加

### 閲覧権限を確認する

`permissions.get` は `GET /assets/{assetName}/permissions` です。`assetName` には、`assets:search` で得た `name` を入れます。公式の型定義では、レスポンスは「ロール → メンバー」のマップと `etag` です。

```json
{
  "permissions": {
    "VIEWER": { "members": ["user:..."] }
  },
  "etag": "..."
}
```

ロールは `VIEWER` / `EDITOR` / `OWNER` / `LINK_VIEWER` / `LINK_EDITOR`。メンバーは `user:` `group:` `domain:` `serviceAccount:` のプレフィックス付き文字列です。`LINK_VIEWER` と `LINK_EDITOR` の値は `allUsers` か `domain:<名前>` で、`allUsers` が入っていればリンクを知る全員が見られる状態です。

```python
# 1つのレポートの権限を取得し、リンク共有の設定を警告する
import requests


def get_permissions(token: str, asset_name: str) -> dict:
    """permissions.get で権限を取得する"""
    res = requests.get(
        f"https://datastudio.googleapis.com/v1/assets/{asset_name}/permissions",
        headers={"Authorization": f"Bearer {token}"},
    )
    res.raise_for_status()
    return res.json()


def has_public_link(permissions: dict) -> bool:
    """allUsers がリンク共有ロールに入っているかを返す"""
    roles = permissions.get("permissions", {})
    for role in ("LINK_VIEWER", "LINK_EDITOR"):
        if "allUsers" in roles.get(role, {}).get("members", []):
            return True
    return False
```

### 閲覧者を追加する

`permissions:addMembers` は **POST** で、スコープは `datastudio`（読み取り専用では不可）。公式のリクエストボディの例は次のとおりです（公式の例。追加先メンバーは Gmail でもよいが、API を呼ぶ側は Workspace / Cloud Identity の組織のユーザーが必要）。

```json
{
  "role": "VIEWER",
  "members": ["user:gus@gmail.com", "user:jen@gmail.com"]
}
```

`OWNER` ロールへの追加はできません。成功時は更新後の Permissions オブジェクトが返ります。呼び出すユーザーに、その資産へメンバーを追加する権限が必要です。

```python
# レポートに閲覧者を追加する（スコープは datastudio が必要）
import requests


def add_viewers(token: str, asset_name: str, emails: list) -> dict:
    """permissions:addMembers で VIEWER を追加する"""
    res = requests.post(
        f"https://datastudio.googleapis.com/v1/assets/{asset_name}/permissions:addMembers",
        headers={"Authorization": f"Bearer {token}"},
        json={"role": "VIEWER", "members": [f"user:{e}" for e in emails]},
    )
    res.raise_for_status()
    return res.json()
```

`permissions.patch` と `revokeAllPermissions` のリクエスト形は、この記事では確認できた範囲を超えるため扱いません。使う場合は公式リファレンス（https://developers.google.com/data-studio/integrate/api/reference/permissions/patch ）を参照してください。権限を一括で書き換える前に、`get` で取った `etag` と現状をログに残しておく運用をおすすめします。

---

## 「ダッシュボードの最新化」を実現する本当の方法

データを新しくしたいなら、API ではなく次の3つを組み合わせます。

| 手段 | 何をする | できること | できないこと |
|---|---|---|---|
| BigQuery のスケジュールクエリ | 定期的に SQL を実行してマート（集計テーブル）を更新 | 最短5分間隔の定期実行。`WRITE_TRUNCATE`（上書き）/ `WRITE_APPEND`（追記）。通常クエリと同じ料金・クォータ | Looker Studio 側への反映（次項の鮮度設定に依存）。毎時ちょうどの実行は重複実行の可能性があり、公式は 08:58 のように時刻をずらすことを勧めている |
| Looker Studio の「データの鮮度」 | キャッシュを使う期間を設定 | BigQuery は 1〜50 分、または 1〜12 時間（既定 12 時間）。手動の「データを更新」は1分のクールダウン | キャッシュが期間中ずっと使われる保証は無い。Google 広告・GA4 などの Google 系コネクタは 12 時間ごとで変更不可。BigQuery の通常課金は発生する |
| スケジュール配信 | レポートの PDF を定期送信 | メールに PDF 添付（先頭ページのプレビューと全体へのリンク）。無料版は1日1回まで、1レポート1スケジュール、宛先は50件まで | ダッシュボード自体の更新ではない。Chat / Slack 配信と、1時間ごとの配信は Pro 機能。数値や日付の書式は US English になる |

### 実際の流れ

1. BigQuery のスケジュールクエリで、マートテーブルを毎朝更新する
2. Looker Studio のデータソースで「データの鮮度」を、マートの更新頻度に合わせる（毎朝更新なら 12 時間か、それより短く）
3. 見る人へ届けたい場合は、スケジュール配信で PDF を送る

新しいカラムが BigQuery に増えた場合の Looker Studio への反映は、API ではできません。データソースの編集画面で「フィールドを更新」を行います。

### 公式ドキュメント

- BigQuery スケジュールクエリ: https://docs.cloud.google.com/bigquery/docs/scheduling-queries
- データの鮮度: https://docs.cloud.google.com/looker/docs/studio/manage-data-freshness
- スケジュール配信: https://docs.cloud.google.com/looker/docs/studio/schedule-automatic-report-delivery

料金・クォータ・上限は変更されることがあるため、実装前に必ず公式ページで確認してください。

---

## 費用・制約・やらなくてよい場合

### 費用と制約

- Looker Studio API の利用料金は、確認できた公式ページに記載がありませんでした。
- BigQuery のスケジュールクエリは「手動クエリと同じ料金」です。スキャン量が増えれば費用も増えます。マートを小さく作るほど安くなります。
- Looker Studio がキャッシュを使わず BigQuery に問い合わせた場合も、通常のクエリ料金がかかります。
- API を使えるのは Workspace / Cloud Identity の組織だけで、導入には管理者の作業が要ります。

### やらなくてよい場合

- レポートが数本から十数本なら、API で棚卸しするより、Looker Studio の画面で一覧を見るほうが早いです
- 権限を付けたい相手が少数なら、GUI の共有設定で足ります。API が効くのは、数十本以上のレポートに同じ権限を繰り返し付ける場合です
- 「ダッシュボードが古い」という悩みは、API ではなく BigQuery 側のマートの更新と鮮度設定で解決することがほとんどです
- 個人の Gmail アカウントしか無い場合、この API は使えません

---

## まとめ

- Looker Studio API でできるのは、資産の検索と権限の管理だけ。チャートやデータソースの変更はできません
- 認証には Workspace 管理者によるドメイン全体委任が必要です。まず `datastudio.readonly` で `assets:search` を試すのが安全です
- 「最新化」は、BigQuery のスケジュールクエリ + データの鮮度設定 + 必要ならスケジュール配信で組みます

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
[データ分析スポットプラン](https://coconala.com/services/554778)
:::

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::
