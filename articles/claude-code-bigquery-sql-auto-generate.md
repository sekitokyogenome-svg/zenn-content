---
title: "Claude CodeでBigQueryのSQLを自然言語から自動生成する"
emoji: "💬"
type: "tech"
topics: ["claudecode", "bigquery", "sql", "googleanalytics"]
published: true
---

## はじめに

「GA4のデータはBigQueryに入っているけど、SQLが書けなくて活用できていない」

GA4のBigQueryエクスポートデータは、`UNNEST` が必要なネスト構造や、`event_params` からの値取り出しなど、SQLの難易度が高めです。エンジニアでない事業担当者が自力で書くのはハードルが高く、エンジニアに依頼するにも時間がかかります。

この記事では、**Claude Code**を使って自然言語からBigQuery SQLを自動生成する方法を紹介します。プロンプトの書き方からSQL検証のコツまで、実践的にまとめました。

---

## Claude Codeとは

Claude Codeは、Anthropicが提供するターミナルベースのAIコーディングアシスタントです。

```bash
# インストール
npm install -g @anthropic-ai/claude-code

# 起動
claude
```

ターミナル上で自然言語の指示を出すと、コードの生成・編集・実行を行ってくれます。BigQuery SQLの生成にも活用できます。

:::message
Claude Codeの利用にはAnthropicのAPIキーまたはサブスクリプションが必要です。詳細は[公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)を確認してください。
:::

---

## 自然言語からSQLを生成する方法

Claude Codeに対して、日本語で分析したい内容を伝えるだけでSQLが生成されます。ポイントは、テーブル名やデータ構造のヒントを添えることです。

### 基本的なプロンプトの流れ

```text
GA4のBigQueryエクスポートテーブル `project.dataset.events_*` を使って、
〇〇を集計するSQLを書いて
```

これだけで、GA4特有の `UNNEST` 構文を含んだSQLが返ってきます。

---

## 実例1：セッション数をチャネル別に集計

以下のようにClaude Codeに指示します。

```text
your_project.analytics_XXXXXXXXX.events_* を使って、
先月のセッション数をチャネル別に集計するSQLを書いて。
collected_traffic_source.manual_source を使ってチャネルを判定して。
```

生成されるSQLの例：

```sql
SELECT
  collected_traffic_source.manual_source AS channel,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  channel
ORDER BY
  sessions DESC
```

GA4特有の `ga_session_id` の取り出しや `_TABLE_SUFFIX` による日付フィルタリングが正しく組み込まれています。

---

## 実例2：purchaseイベントから商品別売上を集計

```text
your_project.analytics_XXXXXXXXX.events_* から、
先月のpurchaseイベントで商品別の売上金額を出して。
itemsをUNNESTして、item_name と item_revenue を使って。
```

生成されるSQLの例：

```sql
SELECT
  items.item_name,
  SUM(items.item_revenue) AS total_revenue,
  COUNT(*) AS purchase_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  items.item_name
ORDER BY
  total_revenue DESC
```

`items` 配列の `UNNEST` が適切に処理され、商品名ごとの売上と購入回数が集計されます。

---

## より良いプロンプトのコツ

Claude Codeに正確なSQLを生成してもらうために、以下の情報をプロンプトに含めると精度が上がります。

| 情報 | 例 | 効果 |
|------|-----|------|
| テーブル名 | `project.dataset.events_*` | 正しいFROM句が生成される |
| 期間指定 | 「先月」「直近7日」 | `_TABLE_SUFFIX` の条件が正確になる |
| 使用カラム | `collected_traffic_source` | GA4固有のカラムを正しく参照 |
| 集計単位 | 「日別×チャネル別」 | GROUP BY句が適切に構成される |
| 出力形式 | 「上位10件」「割合も出して」 | ORDER BYやウィンドウ関数が追加される |

:::message alert
GA4のBigQueryスキーマはバージョンによって変わることがあります。生成されたSQLは必ず実行前に確認してください。
:::

---

## 生成されたSQLの検証方法

Claude Codeが生成したSQLは、そのまま本番実行する前に検証しましょう。

### LIMIT句で結果を確認

```sql
-- 末尾にLIMITを付けて少量で確認
SELECT ...
FROM ...
LIMIT 10
```

### ドライランでコスト見積もり

BigQueryコンソールでクエリを貼り付けると、右上に処理データ量の見積もりが表示されます。CLIでも確認できます。

```bash
bq query --dry_run --use_legacy_sql=false '
SELECT ...
FROM `your_project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN "20260201" AND "20260228"
'
```

`_TABLE_SUFFIX` で期間を絞ることは、コスト削減にも直結します。

---

## 実務ワークフロー

Claude Codeを起点としたデータ分析のワークフロー全体像です。

```text
自然言語で分析したい内容を記述
    ↓
Claude Code がBigQuery SQLを生成
    ↓
BigQueryで実行・結果を確認
    ↓
Looker Studio に接続してダッシュボード化
    ↓
経営判断・施策立案に活用
```

SQLを書けなくても「何を知りたいか」を言語化できれば、データ分析の入口に立てます。BigQuery MCPを使えばClaude Codeから直接クエリを実行することも可能です。

---

## まとめ

- GA4のBigQuery SQLは構造が複雑だが、Claude Codeなら自然言語から生成できる
- プロンプトにテーブル名・期間・カラム名を含めると精度が上がる
- 生成されたSQLはLIMIT句やドライランで必ず検証する
- Claude Code → BigQuery → Looker Studioの流れで、非エンジニアでもデータ活用が始められる

GA4×BigQueryのデータ活用やLooker Studioダッシュボード構築でお困りの方は、以下からご相談ください。

https://coconala.com/services/554778
