---
title: "Conversational Analyticsでデータエージェントを作る"
emoji: "💬"
type: "tech"
topics: ["BigQuery", "GoogleCloud", "AI", "データ分析", "エージェント"]
published: true
---

## この記事で解決する課題

BigQueryのデータにアクセスするたびに、SQLを書いて実行して結果を確認する、という繰り返し作業に時間を取られていませんか。

経営者や事業担当者が「先月の売上上位10商品を見たい」と思った瞬間、自分でSQLを書かずにデータを引き出せたら、意思決定のサイクルが大幅に短縮されます。BigQueryのConversational Analytics（会話型分析）機能を使うと、自然言語の問いかけに応答してSQLを生成・実行し、回答を返すデータエージェントを構築できます。この記事では、その仕組みと実務への適用方法を解説します。

---

## Conversational Analyticsとは

Conversational AnalyticsはBigQueryに組み込まれたAI機能の一つで、Geminiモデルを活用して自然言語のクエリをSQLに変換し、データを照会する機能です。BigQuery Studioのチャットインターフェースから利用できるほか、APIを通じて独自のアプリケーションやエージェントに組み込むことも可能です。

主な特徴は以下のとおりです。

- 自然言語でBigQueryのデータを照会できる
- テーブルスキーマとKnowledge Catalogの情報をコンテキストとして活用する
- 生成されたSQLを確認・修正してから実行できる
- 会話の文脈を引き継いで連続した質問に答えられる

---

## 事前準備：Knowledge Catalogの設定

Conversational Analyticsの回答精度は、テーブルやカラムに付与されたメタデータの質に大きく依存します。事前にKnowledge Catalogで意味のある説明を記載することが前提となります。

```sql
-- テーブルに説明を付与する例
ALTER TABLE `project.dataset.orders`
SET OPTIONS (
  description = '受注テーブル。1行が1注文に対応する。order_statusはplaced/confirmed/shipped/deliveredの4値をとる。'
);

-- カラムに説明を付与する例
ALTER TABLE `project.dataset.orders`
ALTER COLUMN order_id SET OPTIONS (description = '注文ID。UUIDv4形式。');

ALTER TABLE `project.dataset.orders`
ALTER COLUMN total_amount SET OPTIONS (description = '税込合計金額（円）。返品後の調整は含まない。');

ALTER TABLE `project.dataset.orders`
ALTER COLUMN channel SET OPTIONS (description = '注文経路。organic/paid_search/social/emailのいずれか。');
```

カラム説明を整備することで、「メルマガ経由の注文を集計して」という曖昧な表現を、`channel = 'email'` という条件に正しく変換できるようになります。

---

## BigQuery Studio での基本的な使い方

BigQuery Studioの「データキャンバス」タブを開き、チャット欄から自然言語で質問を入力します。

### 例：先月の売上集計

入力：
```text
先月（前月）のチャネル別の売上合計と注文件数を教えてください
```

生成されるSQL（例）：
```sql
SELECT
  channel,
  COUNT(order_id) AS order_count,
  SUM(total_amount) AS revenue
FROM `project.dataset.orders`
WHERE
  DATE(created_at) BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH)
    AND LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
GROUP BY channel
ORDER BY revenue DESC
```

生成されたSQLを確認し、問題なければ「実行」ボタンを押します。次に「上位3チャネルの前月比も出して」と続けると、直前の結果を踏まえてSQLが補完されます。

---

## APIを使ったデータエージェントの構築

Conversational Analyticsの機能はAPI経由で呼び出せるため、Slackボット・社内Webアプリ・Claude Code上のエージェントなどに組み込めます。

### APIエンドポイントの呼び出し例（Python）

```python
from google.cloud import bigquery_datatransfer_v1
from google.cloud import bigquery
import google.auth
import requests

credentials, project_id = google.auth.default()
credentials.refresh(google.auth.transport.requests.Request())

def query_with_conversational_analytics(
    question: str,
    dataset_id: str,
    project_id: str,
) -> dict:
    """
    Conversational Analytics APIに自然言語の質問を送り、
    生成されたSQLと実行結果を返す
    """
    endpoint = (
        f"https://bigquery.googleapis.com/v2/projects/{project_id}"
        f"/datasets/{dataset_id}:query"
    )

    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
    }

    payload = {
        "naturalLanguageQuery": question,
        "location": "asia-northeast1",
    }

    response = requests.post(endpoint, headers=headers, json=payload)
    response.raise_for_status()
    return response.json()
```

返却されるレスポンスには、生成されたSQLと実行結果（行データ）の両方が含まれます。これをパースして、Slackメッセージやダッシュボードに整形して表示します。

---

## エージェントに渡す「instructions」の設計

APIでConversational Analyticsを呼び出す際、instructionsパラメータにビジネスコンテキストを記述することで、回答精度が向上します。

```python
instructions = """
あなたはEC事業の売上データアナリストです。以下のルールに従ってください。

- 金額はすべて税込（円）で表示する
- 「先月」はDATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)の月を指す
- ROASを求める場合はSUM(revenue) / SUM(ad_cost)で計算する
- 返品済みの注文（status = 'returned'）は売上集計から除外する
- データが存在しない期間についてはその旨を明示する
"""

payload = {
    "naturalLanguageQuery": question,
    "instructions": instructions,
    "location": "asia-northeast1",
}
```

instructionsは長くなりすぎるとモデルの理解精度が低下します。ビジネスルールは簡潔に、具体的に記述することが重要です。

---

## 会話文脈の管理

連続した質問に対応するためには、セッションIDを引き継いでAPIを呼び出します。

```python
def create_analytics_session(project_id: str, dataset_id: str) -> str:
    """会話セッションを開始してセッションIDを返す"""
    endpoint = (
        f"https://bigquery.googleapis.com/v2/projects/{project_id}"
        f"/datasets/{dataset_id}:createSession"
    )
    response = requests.post(endpoint, headers=get_headers())
    return response.json()["sessionId"]


def query_in_session(
    session_id: str,
    question: str,
    project_id: str,
    dataset_id: str,
) -> dict:
    """既存セッション内で質問を送る"""
    endpoint = (
        f"https://bigquery.googleapis.com/v2/projects/{project_id}"
        f"/datasets/{dataset_id}/sessions/{session_id}:query"
    )
    payload = {
        "naturalLanguageQuery": question,
        "location": "asia-northeast1",
    }
    response = requests.post(endpoint, headers=get_headers(), json=payload)
    response.raise_for_status()
    return response.json()
```

セッションを使うことで「その中でも返品率が高い商品は？」「そのチャネル限定で前年同期比を出して」という追加質問に自然に応答できます。

---

## 実務での活用シナリオ

### シナリオ1：朝会前の売上確認ボット

Slackに「おはよう」と打つと、前日の売上サマリーを自然言語で返答するボットを構築できます。

- 質問例：「昨日のチャネル別売上と前週比を教えて」
- 返答例：「昨日の売上合計は XX万円でした。チャネル別ではpaid_searchが最大でXX万円（前週比+12%）です。」

### シナリオ2：経営者向けセルフサービス分析

非エンジニアの経営者が自分でデータを照会できる社内Webアプリを構築します。入力フォームに質問を入力すると、APIを経由してBigQueryが応答します。

SQLを知らなくても、ビジネス上の問いに即座にデータで答えられる環境が整います。

### シナリオ3：Claude Code上のデータエージェント

Claude Code × BigQuery MCPでConversational Analytics APIを呼び出す関数をツールとして定義すると、「先月のROAS上位広告を調べて、その広告のクリエイティブ傾向を要約して」という多段階の分析を自律的に実行するエージェントを作れます。

---

## コストと制約の確認

Conversational Analyticsの料金は、内部で実行されるBigQueryクエリのスキャン量に基づきます。自然言語の質問が複雑なSQLに変換された場合、想定外のコストが発生することがあります。

対策として以下を実施します。

```sql
-- クエリコスト上限の設定（バイト単位）
-- プロジェクト設定でMaximum Bytes Billedを指定する
-- 例：500MB = 500 * 1024^2 = 524288000
```

また、Conversational Analyticsが参照できるテーブル数には制限があるため、データセットを目的別に分割し、エージェントが使うデータセットを明示的に指定する設計が有効です。

---

## まとめ

BigQueryのConversational Analyticsを活用すると、非エンジニアでも自然言語でデータを照会できるデータエージェントを構築できます。

- Knowledge CatalogでテーブルとカラムのメタデータをAIに理解させる
- instructionsにビジネスルールを記述して回答精度を高める
- セッションIDを引き継いで連続した質問に対応する
- APIを通じてSlack・社内Webアプリ・Claude Codeに組み込む

データ分析の民主化を実現するための基盤として、Conversational Analyticsの導入を検討してみてください。

---

データ基盤の設計・Conversational Analytics導入支援・BigQuery × GA4分析についてのご相談は、ぜひ以下からお問い合わせください。

https://coconala.com/services/1791205
