---
title: "Claude CodeのAgentモードでEC売上データを自動分析させた結果"
emoji: "🤖"
type: "tech"
topics: ["claudecode","bigquery","ec"]
published: false
---

## はじめに

「EC売上データ、BigQueryに溜まってるけど毎回同じSQL書くの面倒…」

こんな悩みを抱えているEC運営者やデータ分析者は多いのではないでしょうか。GA4のデータをBigQueryにエクスポートしているのに、分析のたびにSQLを手書きし、結果を整形し、レポートにまとめる。この繰り返し作業に時間を取られていませんか。

本記事では、Claude CodeのAgentモードを使って、EC売上データの分析を自然言語の指示だけで自動化した実践例を紹介します。

## Claude Code Agentモードとは

Claude Codeには対話的にコードを生成・実行する「Agentモード」があります。通常のチャットと異なり、以下の特徴があります。

- ファイルの読み書き、コマンド実行を自律的に行う
- 中間結果を見て次のアクションを判断する
- エラーが出た場合に自動で修正を試みる

つまり「分析して」と指示するだけで、SQL生成→実行→結果の整形→レポート出力までを一気通貫で処理してくれます。

## プロンプト設計のポイント

Agentモードで精度の高いアウトプットを得るには、プロンプトの設計が重要です。以下の3点を意識しています。

### 1. 分析の目的を明示する

```
BigQueryのGA4データから、直近30日間のEC売上トレンドを分析して、
前月比較とチャネル別の内訳を含むレポートをMarkdownで出力してください。
```

「何を知りたいのか」を先に伝えることで、生成されるSQLの方向性がブレにくくなります。

### 2. テーブル構造のヒントを渡す

GA4のBigQueryエクスポートは `event_params` がネストされた構造です。Claude Codeに正しいSQLを書かせるために、以下のようなヒントを添えます。

```
GA4のBigQueryテーブルは `project.dataset.events_*` 形式です。
セッションIDは event_params から ga_session_id を UNNEST で取得してください。
トラフィックソースは collected_traffic_source.manual_medium を使ってください。
```

:::message
GA4のBigQueryデータでは、セッションIDは `event_params` 内の `ga_session_id` を `UNNEST` して取得します。`session_id` という単独カラムは存在しないため注意してください。
:::

### 3. 出力フォーマットを指定する

```
出力はMarkdown形式で、以下の構成にしてください：
1. サマリー（主要KPI 3-5個）
2. 日別売上推移の表
3. チャネル別内訳の表
4. 考察と改善ポイント
```

## 実践：売上分析の自動化フロー

### Step 1: BigQueryクエリの自動生成

Claude Codeに以下のように指示します。

```bash
claude "BigQueryのGA4データから直近30日間のEC売上を日別・チャネル別に集計するSQLを書いて実行して"
```

生成されるSQLの例：

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  date, medium
ORDER BY
  date DESC, revenue DESC
```

:::message
`collected_traffic_source.manual_medium` はGA4のBigQueryエクスポートで正しいトラフィックソースのフィールドです。`traffic_source.medium` はセッションスコープのデータが取れないケースがあるため、用途に応じて使い分けてください。
:::

### Step 2: 結果の自動整形

Agentモードでは、SQLの実行結果を受け取った後、自動的に以下の処理を行います。

1. 数値のフォーマット（カンマ区切り、小数点以下の丸め）
2. 前月同期間との比較計算
3. チャネル別の構成比算出

### Step 3: Markdownレポートの出力

最終的に以下のような構造のレポートが自動生成されます。

```markdown
# EC売上月次レポート（2026年3月）

## サマリー
| 指標 | 当月 | 前月 | 前月比 |
|------|------|------|--------|
| 売上合計 | ¥1,234,567 | ¥1,100,000 | +12.2% |
| 購入数 | 89件 | 78件 | +14.1% |
| CVR | 2.3% | 2.1% | +0.2pt |

## チャネル別内訳
| チャネル | セッション | 売上 | CVR |
|----------|-----------|------|-----|
| organic | 2,340 | ¥520,000 | 2.8% |
| cpc | 1,890 | ¥480,000 | 3.1% |
| ...
```

## Pythonスクリプトとして保存する

一度うまくいったフローは、再利用可能なスクリプトとして保存しておくと便利です。

```python
"""
モジュール名: ec_sales_report.py
目的: BigQueryからEC売上データを取得し月次レポートを生成する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
from datetime import datetime, timedelta

def fetch_sales_data(client: bigquery.Client, project_id: str, dataset: str, days: int = 30) -> pd.DataFrame:
    """直近N日間の売上データをBigQueryから取得する"""
    query = f"""
    SELECT
      PARSE_DATE('%Y%m%d', event_date) AS date,
      collected_traffic_source.manual_medium AS medium,
      COUNT(DISTINCT
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases,
      SUM(ecommerce.purchase_revenue) AS revenue
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL {days} DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY
      date, medium
    ORDER BY
      date DESC, revenue DESC
    """
    return client.query(query).to_dataframe()

def generate_markdown_report(df: pd.DataFrame) -> str:
    """DataFrameからMarkdownレポートを生成する"""
    total_revenue = df['revenue'].sum()
    total_purchases = df['purchases'].sum()
    total_sessions = df['sessions'].sum()
    cvr = (total_purchases / total_sessions * 100) if total_sessions > 0 else 0

    report = f"""# EC売上レポート（直近30日間）

## サマリー
- 売上合計: ¥{total_revenue:,.0f}
- 購入数: {total_purchases}件
- セッション数: {total_sessions:,}
- CVR: {cvr:.1f}%

## チャネル別内訳
| チャネル | セッション | 売上 | CVR |
|----------|-----------|------|-----|
"""
    channel_data = df.groupby('medium').agg({
        'sessions': 'sum',
        'revenue': 'sum',
        'purchases': 'sum'
    }).reset_index()

    for _, row in channel_data.iterrows():
        ch_cvr = (row['purchases'] / row['sessions'] * 100) if row['sessions'] > 0 else 0
        report += f"| {row['medium']} | {row['sessions']:,} | ¥{row['revenue']:,.0f} | {ch_cvr:.1f}% |\n"

    return report
```

## Agentモードを使うメリットと注意点

### メリット
- SQL手書きの時間が大幅に削減される
- 分析→整形→レポートの一連の流れが途切れない
- 「前月比も出して」など追加の指示に即座に対応できる

### 注意点
- 生成されたSQLは実行前に目視で確認する習慣をつける
- 大量データへのクエリはコスト面を意識する（パーティションフィルタの有無など）
- GA4のスキーマ変更があった場合、プロンプトのヒント情報も更新が必要

## まとめ

Claude CodeのAgentモードを活用すると、EC売上データの分析がプロンプト一つで完了します。ポイントは以下の3つです。

1. 分析の目的とテーブル構造のヒントを明示する
2. 出力フォーマットを事前に指定する
3. うまくいったフローはPythonスクリプトとして保存する

日次・週次の定型レポートは自動化し、分析者は意思決定に直結するインサイトの発見に集中する。そんな運用体制を構築してみてはいかがでしょうか。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
