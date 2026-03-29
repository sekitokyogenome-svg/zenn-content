---
title: "MCP × BigQuery × Claude Codeで聞くだけで分析できる社内ツールを作った"
emoji: "🔍"
type: "tech"
topics: ["claudecode", "bigquery", "mcp"]
published: false
---

## はじめに

「先週のチャネル別セッション数、出してもらえますか？」

この一言をデータチームに投げるたびに、返答まで半日〜1日かかる。マーケ担当やCSチームがデータを見たいタイミングと、実際に手に入るタイミングにズレがある。SQLを書けない非エンジニアにとって、BigQueryに溜まったデータは「見えない資産」のままです。

この課題を解決するために、**MCP（Model Context Protocol）を使ってClaude CodeとBigQueryを接続**し、自然言語で質問するだけで分析結果が返ってくる社内ツールを構築しました。

この記事では、セットアップから運用のガードレールまで、実際に導入した手順を共有します。

---

## MCP（Model Context Protocol）とは

MCPはAnthropicが策定したオープンプロトコルで、AIエージェントが外部のツールやデータソースに接続するための標準規格です。

MCPには主に2つの概念があります。

- **Tools**: AIが呼び出せる「操作」。SQLの実行、データの取得など
- **Resources**: AIが参照できる「情報」。テーブルのスキーマ、データセット一覧など

MCPサーバーがこれらを公開し、Claude Code（MCPクライアント）が接続することで、AIが直接BigQueryを操作できるようになります。

```
[ユーザー] → 自然言語で質問
    ↓
[Claude Code] → MCPプロトコルでリクエスト
    ↓
[BigQuery MCPサーバー] → SQL生成・実行
    ↓
[BigQuery] → クエリ結果を返却
    ↓
[Claude Code] → 結果を要約してユーザーに回答
```

---

## BigQuery MCPサーバーのセットアップ

### 1. 事前準備

- Google Cloud Platform（GCP）アカウント
- BigQueryにデータが格納済み
- Claude Codeインストール済み

### 2. GCP認証の設定

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 3. MCPサーバーのインストール

```bash
pip install bigquery-mcp-server
```

### 4. Claude Codeの設定

プロジェクトルートの `.mcp.json` または `~/.claude/settings.json` に以下を追加します。

```json
{
  "mcpServers": {
    "bigquery": {
      "command": "python",
      "args": ["-m", "bigquery_mcp_server"],
      "env": {
        "GOOGLE_CLOUD_PROJECT": "your-project-id"
      }
    }
  }
}
```

:::message
`.mcp.json` をプロジェクトルートに置けば、チームメンバーがリポジトリをcloneするだけで同じMCP設定を共有できます。
:::

### 5. 接続確認

Claude Codeを起動して、以下のように話しかけます。

```
BigQueryに接続できていますか？利用可能なデータセットを教えてください。
```

正常に接続されていれば、データセット一覧が返ってきます。

---

## 実際の会話例

### 例1：チャネル別セッション数の確認

**ユーザー:**
> 先週のチャネル別セッション数を教えて

**Claude Code:**
BigQueryに対して以下のクエリを実行しました。

```sql
SELECT
  channel_grouping,
  COUNT(DISTINCT session_id) AS sessions
FROM `your-project.your_dataset.stg_sessions`
WHERE session_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND CURRENT_DATE()
GROUP BY channel_grouping
ORDER BY sessions DESC
```

| チャネル | セッション数 |
|---------|------------|
| Organic Search | 1,245 |
| Direct | 892 |
| Social | 456 |

先週のセッション数は合計2,593でした。Organic Searchが最も多く全体の48%を占めています。

### 例2：前週比の確認

**ユーザー:**
> 前週と比べてどう変化した？

Claude Codeは直前の文脈を理解しているため、追加で前々週のデータも取得し、比較結果を返してくれます。SQLを都度指定する必要はありません。

---

## ガードレールの設定

社内ツールとして運用するには、安全対策が不可欠です。以下の3点を設定しました。

### 1. 読み取り専用アクセス

GCPのIAMで、MCPサーバーが使用するサービスアカウントに **`BigQuery データ閲覧者`**（`roles/bigquery.dataViewer`）ロールのみを付与します。

```bash
gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:mcp-reader@your-project-id.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"
```

:::message alert
`BigQuery 管理者`や`BigQuery データ編集者`は絶対に付与しないでください。意図しないデータの削除・変更を防ぐためです。
:::

### 2. クエリコスト上限

BigQueryのカスタムクォータを設定し、1日あたりのスキャン量に上限を設けます。

```bash
# 1日あたり1TBまでに制限（プロジェクト単位）
bq update --project_id your-project-id \
  --default_query_job_config '{"maximum_bytes_billed": "1099511627776"}'
```

MCPサーバー側でもクエリごとの上限を設定できます。

```json
{
  "mcpServers": {
    "bigquery": {
      "command": "python",
      "args": ["-m", "bigquery_mcp_server"],
      "env": {
        "GOOGLE_CLOUD_PROJECT": "your-project-id",
        "BQ_MAXIMUM_BYTES_BILLED": "10737418240"
      }
    }
  }
}
```

### 3. 許可データセットの制限

MCPサーバーの設定で、アクセス可能なデータセットを明示的に指定します。顧客の個人情報が含まれるデータセットを除外することで、情報漏洩リスクを低減できます。

---

## チームへの展開

### 共有する設定ファイル

`.mcp.json` をリポジトリに含め、以下のドキュメントを用意しました。

1. **セットアップ手順**: GCP認証とClaude Codeのインストール
2. **質問例集**: よく使う分析パターンをテンプレート化
3. **注意事項**: コスト上限とアクセス範囲の説明

### 質問テンプレートの例

チームメンバーが迷わないよう、CLAUDE.mdに質問例を記載しました。

```markdown
## よく使う分析クエリ
- 「今週のチャネル別セッション数を教えて」
- 「先月のコンバージョン率を日別で出して」
- 「直帰率が高いランディングページ上位10件は？」
- 「前月比でセッション数が増えたチャネルはどれ？」
```

---

## 導入後の変化

MCPを導入してから、以下の変化がありました。

- **データチームへの問い合わせが減少**: 定型的な集計はチームメンバーが自分で実行
- **意思決定のスピード向上**: データ取得までのリードタイムが半日→数秒に
- **分析の幅が広がった**: SQLを意識しない分、「こういう切り口で見たい」という発想が増えた

ただし、複雑なクエリや精度が求められる分析は、依然としてデータチームが対応しています。MCPは万能ではなく、**日常的なセルフサービス分析を担う補助ツール**として位置づけるのが現実的です。

---

## まとめ

MCP × BigQuery × Claude Codeの組み合わせで、非エンジニアでも自然言語でデータ分析ができる社内ツールを構築しました。

ポイントは以下の3点です。

1. **MCPサーバーでClaude CodeとBigQueryを接続**し、SQLを書かずにデータ取得
2. **IAM・コスト上限・データセット制限**でガードレールを設定
3. **設定ファイルとテンプレートを共有**し、チーム全体で活用

「GA4のデータがBigQueryにあるけど活用できていない」「データチームへの依頼が多すぎて回らない」といった課題をお持ちの方は、ぜひ試してみてください。

GA4 × BigQueryの基盤構築やデータ活用の仕組みづくりでお困りの方は、以下のサービスでご相談を承っています。

https://coconala.com/services/554778
