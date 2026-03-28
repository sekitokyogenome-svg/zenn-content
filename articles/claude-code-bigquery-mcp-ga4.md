---
title: "Claude Code × BigQuery MCPでGA4分析を完全自動化する方法【EC事業者向け実践ガイド】"
emoji: "🤖"
type: "tech"
topics: ["claudecode", "bigquery", "googleanalytics", "mcp", "lookerstudio"]
published: true
---

## はじめに

「BigQueryにGA4データは入っているのに、SQLを書くのが面倒で結局見ていない」

そんな状況を根本から解決するのが、**Claude Code × BigQuery MCP** の組み合わせです。

MCP（Model Context Protocol）を使うと、Claude Codeが直接BigQueryに接続し、自然言語でデータを取得・分析できるようになります。SQLを書く必要はありません。

この記事では、EC事業者向けに以下を実践的に解説します。

- BigQuery MCPのセットアップ手順
- Claude Codeでの自然言語クエリの実例
- 毎朝レポートを自動生成する仕組みの構築

---

## BigQuery MCPとは

MCP（Model Context Protocol）はAnthropicが策定したオープン規格で、Claude CodeなどのAIエージェントが外部ツール・データベースに直接接続するための仕組みです。

BigQuery MCPを使うと以下が実現できます。

- 自然言語でBigQueryにクエリを発行
- クエリ結果をそのまま分析・要約
- 定期実行スクリプトとの組み合わせで完全自動化

---

## 事前準備

### 必要なもの

- Google Cloud Platform（GCP）アカウント
- GA4のBigQueryエクスポート設定済み（[公式設定ガイド](https://support.google.com/analytics/answer/9358801)）
- Claude Codeインストール済み
- Python 3.10以上

### GCP認証の設定

```bash
# Google Cloud SDKのインストール後
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

---

## BigQuery MCPのセットアップ

### 1. MCPサーバーのインストール

```bash
pip install bigquery-mcp-server
```

### 2. Claude Codeの設定ファイルに追記

`~/.claude/settings.json` を開き、以下を追加します。

```json
{
  "mcpServers": {
    "bigquery": {
      "command": "python",
      "args": ["-m", "bigquery_mcp_server"],
      "env": {
        "GOOGLE_CLOUD_PROJECT": "YOUR_PROJECT_ID"
      }
    }
  }
}
```

### 3. 接続確認

Claude Codeを起動し、以下のように話しかけます。

```
昨日のセッション数をBigQueryから取得してください。
データセットはanalytics_XXXXXXXXXです。
```

正常に接続されていれば、Claude Codeが自動でクエリを生成・実行し結果を返します。

---

## 実際の使用例（EC事業者向け）

### ケース1：チャネル別セッション数・CV数の確認

```
先月のチャネル別セッション数とコンバージョン数を集計し、
チャネルごとのCV率を計算してください。
```

Claude Codeが生成するクエリの例：

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions,
  ROUND(
    COUNTIF(event_name = 'purchase') /
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (SELECT value.int_value FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING))
    ) * 100, 2
  ) AS cvr_pct
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY 1
ORDER BY sessions DESC
```

### ケース2：商品カテゴリ別の離脱分析

```
先週、商品詳細ページを見たあとカートに入れずに離脱したユーザーが
多かったページを教えてください。
```

### ケース3：リピート率の確認

```
初回購入から30日以内に2回目の購入をしたユーザーの割合を
月別で出してください。
```

SQLの知識がなくても、欲しい数字を日本語で伝えるだけで取得できます。

---

## 毎朝レポートを自動生成する仕組み

Claude Codeをスケジュール実行することで、毎朝レポートを自動生成できます。

### Pythonスクリプトの例

```python
import subprocess
from datetime import date

prompt = f"""
本日（{date.today()}）のECサイトの状況を以下の形式でレポートしてください。

1. 昨日のセッション数・CV数・CVR
2. チャネル別の昨日の流入数（上位5チャネル）
3. 昨日の売上金額（purchaseイベントのrevenueから集計）
4. 前週同日との比較
5. 気になる変化があれば指摘

BigQueryのデータセット: analytics_XXXXXXXXX
データはBigQueryから取得してください。
"""

subprocess.run(["claude", "-p", prompt], check=True)
```

### タスクスケジューラへの登録（Windows）

```
タスク名: GA4_Daily_Report
トリガー: 毎日 08:00
操作: python C:\path\to\daily_report.py
```

これで毎朝8時に自動でレポートが生成されます。

---

## 3層設計との組み合わせ

MCPで取得したデータをより使いやすくするには、BigQueryのデータを3層構造で整備しておくことを推奨します。

```
raw層     analytics_XXXXXXXXX.events_YYYYMMDD（GA4生データ）
  ↓
staging層  フラット化・クレンジング済みのビュー
  ↓
mart層     ビジネス指標に変換済みのテーブル ← MCPはここに向ける
```

mart層に向けてクエリを発行することで、Claude Codeへの指示がシンプルになり、精度も上がります。

:::message
3層設計の詳細は[「GA4のデータをBigQueryに繋ぐと何が変わるのか」](/articles/zenn_article_01)で解説しています。
:::

---

## まとめ

| 従来の方法 | Claude Code × BigQuery MCP |
|-----------|---------------------------|
| SQLを書いて実行 | 日本語で話しかけるだけ |
| 手動でレポートを作成 | 毎朝自動生成 |
| エンジニアに依頼が必要 | EC経営者が自分で操作可能 |
| 分析に週数時間 | 確認は朝5分 |

GA4×BigQueryの基盤が整っていれば、MCPの設定は1〜2時間で完了します。

「基盤構築から依頼したい」「自社EC向けにカスタマイズしてほしい」という方はこちらからご相談ください。

https://coconala.com/services/1791205
