---
title: "BigQuery MCPサーバーをつなぐ — エージェントからBigQueryを操作する"
emoji: "🔌"
type: "tech"
topics: ["BigQuery", "MCP", "Claude", "Agent", "GCP"]
published: true
---

## AIエージェントとBigQueryの間にある壁

BigQueryのAI機能（K-01〜K-24で解説したAI関数群）はSQL内でGeminiを呼び出す方向だが、逆向きの連携もある。ClaudeやGPTなどのAIエージェントをクライアント側に置き、エージェントがBigQueryを操作するパターンだ。

この逆向き連携を実現するのがMCP（Model Context Protocol）だ。MCPを使うと、AIエージェントはBigQueryに対してクエリ実行・スキーマ確認・テーブル一覧取得などを直接行える。

本記事ではBigQuery MCPサーバーのセットアップと、Claude Codeからの基本操作を解説する。

## MCPとは何か

MCP（Model Context Protocol）はAnthropicが策定したオープンプロトコルで、AIアシスタントと外部ツール・データソースを接続するための標準仕様だ。

MCPの基本構造は以下のとおりだ。

| 役割 | 説明 |
|---|---|
| MCPホスト | AIエージェントを動かすアプリ（Claude Code、Claude Desktopなど） |
| MCPクライアント | ホストに組み込まれたプロトコル処理層 |
| MCPサーバー | 特定のツール・データソースを外部に公開するサービス |

BigQuery MCPサーバーはBigQueryの操作をMCPプロトコルで公開するサーバーだ。Claude Codeなどのホストがこのサーバーを経由してBigQueryへのクエリ実行やメタデータ取得を行える。

## BigQuery MCPサーバーの種類

BigQueryをMCPで操作する方法は複数ある。

### 1. MCP Toolbox for Databases（推奨）

GoogleがOSSとして提供するMCPサーバー群で、BigQueryを含む複数のデータベースに対応する。エンタープライズ利用を想定した設計で、接続管理・認証・リソース制御が充実している。

```
https://github.com/googleapis/genai-toolbox
```

### 2. コミュニティ製BigQuery MCPサーバー

軽量な実装が多く、個人利用や検証目的に向く。GitHubで複数の実装が公開されている。

### 3. Claude Code内蔵MCP

Claude Code（バージョン1.0以降）はBigQueryへの直接接続機能を持つ。MCP Toolboxとの組み合わせが公式推奨構成だ。

本記事ではMCP Toolbox for Databasesを使った構成を解説する。

## 事前準備

### 必要な権限

エージェントがBigQueryを操作するには以下のIAMロールが必要だ。

- `roles/bigquery.dataViewer`（テーブル・スキーマの参照）
- `roles/bigquery.jobUser`（クエリ実行）
- `roles/bigquery.dataEditor`（テーブルへの書き込みが必要な場合）

最小権限の原則に従い、参照のみの用途なら`dataViewer`と`jobUser`だけで十分だ。

### サービスアカウントの作成

MCPサーバーが使用するサービスアカウントをGCPで作成する。

```bash
# サービスアカウントの作成
gcloud iam service-accounts create bigquery-mcp-agent \
  --display-name="BigQuery MCP Agent"

# 権限の付与
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:bigquery-mcp-agent@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:bigquery-mcp-agent@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# キーファイルの発行
gcloud iam service-accounts keys create bigquery-mcp-key.json \
  --iam-account=bigquery-mcp-agent@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

:::message
キーファイルは`.gitignore`への追記を忘れずに。誤ってリポジトリにコミットしないよう注意が必要だ。
:::

## MCP Toolboxのセットアップ

### インストール

```bash
# Go 1.21以上が必要
go install github.com/googleapis/genai-toolbox@latest
```

または公式ドキュメントに従ってDockerイメージを使う方法もある。

### 設定ファイルの作成

`toolbox.yaml`を作成してBigQueryへの接続情報を定義する。

```yaml
sources:
  - name: bigquery-prod
    type: bigquery
    project: your-gcp-project-id
    credentials_file: /path/to/bigquery-mcp-key.json

tools:
  - name: run_query
    description: BigQueryでSQLクエリを実行して結果を返す
    source: bigquery-prod
    kind: bigquery-query
    parameters:
      - name: sql
        type: string
        description: 実行するSQLクエリ

  - name: list_datasets
    description: プロジェクト内のデータセット一覧を取得する
    source: bigquery-prod
    kind: bigquery-list-datasets

  - name: list_tables
    description: 指定データセット内のテーブル一覧を取得する
    source: bigquery-prod
    kind: bigquery-list-tables
    parameters:
      - name: dataset_id
        type: string
        description: データセットID

  - name: get_table_schema
    description: テーブルのスキーマ（カラム定義）を取得する
    source: bigquery-prod
    kind: bigquery-get-table
    parameters:
      - name: dataset_id
        type: string
        description: データセットID
      - name: table_id
        type: string
        description: テーブルID
```

### サーバーの起動

```bash
toolbox --config toolbox.yaml --port 5000
```

起動後、`http://localhost:5000`でMCPサーバーが待ち受ける。

## Claude CodeへのMCP設定

### `.claude/settings.json`の編集

Claude Codeのプロジェクト設定ファイルにMCPサーバーの接続情報を追加する。

```json
{
  "mcpServers": {
    "bigquery": {
      "url": "http://localhost:5000/mcp"
    }
  }
}
```

グローバル設定（`~/.claude/settings.json`）に書くと全プロジェクトで使える。プロジェクト固有の接続先は`.claude/settings.json`に書く。

### 接続の確認

Claude Codeを起動し、以下のように話しかけると接続確認ができる。

```
BigQueryに接続できていますか？データセット一覧を教えてください。
```

MCPサーバーが正常に起動していれば、Claude CodeはBigQueryのデータセット一覧を取得して返答する。

## 基本操作

### テーブル構造の確認

```
analyticsデータセットにどんなテーブルがありますか？
ga_sessionsテーブルのスキーマを確認してください。
```

Claude Codeは`list_tables`と`get_table_schema`ツールを呼び出し、テーブル定義を取得する。

### クエリの実行

```
ga_sessionsテーブルから昨日のセッション数をデバイス別に集計してください。
```

Claude Codeは適切なSQLを生成し、`run_query`ツールで実行して結果を返す。

生成されるSQLの例：

```sql
SELECT
  device.category AS device_category,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions
FROM `your-project.analytics.ga_sessions`
WHERE DATE(TIMESTAMP_MICROS(event_timestamp)) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY 1
ORDER BY 2 DESC
```

:::message
`ga_session_id`の取得はUNNEST経由でevent_paramsから取り出す必要がある。直接カラムとして存在しないため、UNNEST処理が必須だ。
:::

### 分析の反復

MCPを使うとエージェントが結果を確認しながら次のクエリを自動生成できる。

```
セッション数が先週比で20%以上減っているデバイスはありますか？
原因として考えられるトラフィックソースを調べてください。
```

エージェントは複数のクエリを順次実行し、集計→比較→原因探索を自律的に行う。

## コスト管理の設定

エージェントが自律的にクエリを実行するため、クエリコストが意図せず膨らむリスクがある。以下の設定でコストを制御する。

### バイトスキャン上限の設定

`toolbox.yaml`にクエリのバイトスキャン上限を追加できる。

```yaml
tools:
  - name: run_query
    kind: bigquery-query
    source: bigquery-prod
    config:
      maximum_bytes_billed: 10737418240  # 10GB上限
```

### 書き込み操作の制限

参照専用の用途では、テーブルへの書き込みツールを`toolbox.yaml`に定義しないことで操作を制限できる。

### クエリ実行ログの確認

BigQueryのINFORMATION_SCHEMAでエージェントが実行したクエリ履歴を定期確認する。

```sql
SELECT
  creation_time,
  total_bytes_billed,
  query
FROM `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE DATE(creation_time) = CURRENT_DATE()
  AND user_email = 'bigquery-mcp-agent@your-project.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 50
```

## セキュリティの注意点

### データセットへのアクセス範囲を絞る

サービスアカウントにはプロジェクト全体の権限を与えず、必要なデータセットのみに権限を付与する。

```bash
# プロジェクト全体ではなくデータセット単位で権限付与
bq add-iam-policy-binding \
  --member="serviceAccount:bigquery-mcp-agent@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  your-project:analytics
```

### キーファイルの管理

本番環境では`credentials_file`よりもWorkload Identity FederationやApplication Default Credentialsを使う方が安全だ。クラウド環境（Cloud Run、GKEなど）ではキーファイルを使わずに運用できる。

### MCPサーバーへのアクセス制限

`toolbox.yaml`でAllowlistを設定してアクセスを制限する。社内ネットワークや特定のIPからのみ接続を受け付ける設定が推奨だ。

## まとめ

BigQuery MCPサーバーをセットアップすると、Claude Codeなどのエージェントから以下の操作ができるようになる。

- データセット・テーブル一覧の取得
- スキーマの確認
- SQLクエリの実行と結果取得
- 複数クエリを連続させた自律的な分析

エージェント側がBigQueryの構造を理解した上でSQLを生成・実行できるため、自然言語での分析指示がより正確に動く。次のK-26ではClaude Code × BigQuery MCPでGA4分析を任せる具体的な活用例を解説する。

---

BigQueryへのMCP接続設定・エージェント活用について、実務レベルのサポートを提供しています。ご相談はこちらからどうぞ。

https://coconala.com/services/3332133
