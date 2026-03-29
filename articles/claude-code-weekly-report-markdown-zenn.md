---
title: "Claude Codeに週次レポートをMarkdownで生成させてそのままZennに投稿する"
emoji: "📰"
type: "tech"
topics: ["claudecode","bigquery","zenn"]
published: false
---

## はじめに

「分析結果をブログ記事として発信したいけど、書く時間がない」

データ分析の結果を社内共有するだけでなく、Zennなどの技術ブログに発信することで、ポートフォリオの蓄積やブランディングにつながります。しかし、分析→記事執筆→投稿という一連の流れは工数がかかるものです。

本記事では、BigQueryから週次データを取得し、Claude CodeでMarkdownレポートを自動生成し、Zenn CLIでそのまま公開するパイプラインを構築した方法を紹介します。

## 全体フロー

```
BigQuery（週次データ取得）
    ↓
Python（データ整形・要約テンプレート生成）
    ↓
Claude Code（Markdown記事生成）
    ↓
Zenn CLI（プレビュー → GitHubにpush → 公開）
```

## Step 1: BigQueryから週次データを取得する

まず、週次レポートの元データをBigQueryから取得します。

```python
"""
モジュール名: weekly_data_fetcher.py
目的: 週次レポート用のデータをBigQueryから取得する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
import json
from pathlib import Path

def fetch_weekly_metrics(client: bigquery.Client, project_id: str, dataset: str) -> dict:
    """直近7日間の主要指標を取得する"""
    query = f"""
    WITH weekly_data AS (
      SELECT
        PARSE_DATE('%Y%m%d', event_date) AS date,
        COUNT(DISTINCT
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        ) AS sessions,
        COUNTIF(event_name = 'purchase') AS purchases,
        SUM(ecommerce.purchase_revenue) AS revenue,
        COUNT(DISTINCT user_pseudo_id) AS users
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
      GROUP BY date
    ),
    prev_week AS (
      SELECT
        COUNT(DISTINCT
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        ) AS sessions,
        COUNTIF(event_name = 'purchase') AS purchases,
        SUM(ecommerce.purchase_revenue) AS revenue,
        COUNT(DISTINCT user_pseudo_id) AS users
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    )
    SELECT
      'current' AS period,
      SUM(sessions) AS sessions,
      SUM(purchases) AS purchases,
      SUM(revenue) AS revenue,
      SUM(users) AS users
    FROM weekly_data
    UNION ALL
    SELECT
      'previous' AS period,
      sessions, purchases, revenue, users
    FROM prev_week
    """
    df = client.query(query).to_dataframe()

    current = df[df['period'] == 'current'].iloc[0]
    previous = df[df['period'] == 'previous'].iloc[0]

    return {
        'current': {
            'sessions': int(current['sessions']),
            'purchases': int(current['purchases']),
            'revenue': float(current['revenue'] or 0),
            'users': int(current['users']),
        },
        'previous': {
            'sessions': int(previous['sessions']),
            'purchases': int(previous['purchases']),
            'revenue': float(previous['revenue'] or 0),
            'users': int(previous['users']),
        }
    }

def fetch_channel_breakdown(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """チャネル別の内訳を取得する"""
    query = f"""
    SELECT
      IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
      COUNT(DISTINCT
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases,
      SUM(ecommerce.purchase_revenue) AS revenue
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY medium
    ORDER BY revenue DESC
    """
    return client.query(query).to_dataframe()
```

## Step 2: データをJSONに保存してClaude Codeに渡す

取得したデータをJSON形式で保存し、Claude Codeへの入力として使います。

```python
def save_weekly_data(metrics: dict, channel_df: pd.DataFrame, output_path: str):
    """週次データをJSONで保存する"""
    data = {
        'metrics': metrics,
        'channels': channel_df.to_dict(orient='records'),
        'generated_at': pd.Timestamp.now().isoformat()
    }
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"データを {output_path} に保存しました")
```

## Step 3: Claude Codeでレポート記事を生成する

保存したJSONデータを元に、Claude Codeでレポート記事を生成します。

```bash
claude "data/processed/weekly_data.json を読み込んで、
以下の構成でZenn記事用のMarkdownを生成してください。

構成:
1. frontmatter（title, emoji, type: idea, topics, published: false）
2. 今週のサマリー（主要KPI 4つと前週比）
3. チャネル別パフォーマンス（表形式）
4. 今週の注目ポイント（データから読み取れる傾向を3つ）
5. 来週のアクション（改善提案を2-3個）

出力先: articles/weekly-report-2026-w13.md"
```

### 生成されるMarkdownの例

```markdown
---
title: "【週次レポート】EC分析ダイジェスト 2026年第13週"
emoji: "📈"
type: "idea"
topics: ["ec","analytics","marketing"]
published: false
---

## 今週のサマリー

| 指標 | 今週 | 先週 | 前週比 |
|------|------|------|--------|
| セッション | 3,240 | 2,980 | +8.7% |
| ユーザー数 | 2,150 | 1,980 | +8.6% |
| 購入数 | 45件 | 38件 | +18.4% |
| 売上 | ¥567,000 | ¥489,000 | +15.9% |

## チャネル別パフォーマンス

| チャネル | セッション | 購入 | 売上 | CVR |
|----------|-----------|------|------|-----|
| organic | 1,450 | 22 | ¥280,000 | 1.5% |
| cpc | 890 | 15 | ¥195,000 | 1.7% |
| social | 520 | 5 | ¥52,000 | 1.0% |
| direct | 380 | 3 | ¥40,000 | 0.8% |
```

## Step 4: Zenn CLIで投稿する

生成されたMarkdownファイルをZenn CLIでプレビュー・公開します。

### Zenn CLIのセットアップ

```bash
# Zenn CLIのインストール
npm install zenn-cli

# プレビュー確認
npx zenn preview
```

### 自動公開フロー

```bash
# 記事をGitHubにpush → Zennに自動反映
git add articles/weekly-report-2026-w13.md
git commit -m "週次レポート 2026年第13週を追加"
git push origin main
```

:::message
Zennの記事は `published: true` に変更してGitHubにpushすると公開されます。自動化する場合も、最初は `published: false` で生成し、内容を確認してから公開に切り替えることを推奨します。
:::

## Step 5: 全体を1コマンドで実行するスクリプト

一連の処理をまとめたスクリプトを作成します。

```python
"""
モジュール名: generate_weekly_report.py
目的: BigQueryデータ取得→Markdownレポート生成→Zenn記事作成の自動化
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas, python-dotenv
"""

import os
import subprocess
from datetime import datetime
from google.cloud import bigquery
from dotenv import load_dotenv
from pathlib import Path

load_dotenv()

def get_week_number() -> str:
    """現在の年と週番号を返す"""
    now = datetime.now()
    week = now.isocalendar()[1]
    return f"{now.year}-w{week:02d}"

def generate_frontmatter(week: str) -> str:
    """Zenn記事のfrontmatterを生成する"""
    return f"""---
title: "【週次レポート】EC分析ダイジェスト {week}"
emoji: "📈"
type: "idea"
topics: ["ec","analytics","marketing"]
published: false
---
"""

def build_report_markdown(metrics: dict, channel_data: list) -> str:
    """取得データからMarkdownレポートを組み立てる"""
    current = metrics['current']
    previous = metrics['previous']

    def pct_change(curr, prev):
        if prev == 0:
            return "N/A"
        change = (curr - prev) / prev * 100
        sign = "+" if change >= 0 else ""
        return f"{sign}{change:.1f}%"

    md = "## 今週のサマリー\n\n"
    md += "| 指標 | 今週 | 先週 | 前週比 |\n"
    md += "|------|------|------|--------|\n"
    md += f"| セッション | {current['sessions']:,} | {previous['sessions']:,} | {pct_change(current['sessions'], previous['sessions'])} |\n"
    md += f"| ユーザー | {current['users']:,} | {previous['users']:,} | {pct_change(current['users'], previous['users'])} |\n"
    md += f"| 購入数 | {current['purchases']}件 | {previous['purchases']}件 | {pct_change(current['purchases'], previous['purchases'])} |\n"
    md += f"| 売上 | ¥{current['revenue']:,.0f} | ¥{previous['revenue']:,.0f} | {pct_change(current['revenue'], previous['revenue'])} |\n"
    md += "\n"

    md += "## チャネル別パフォーマンス\n\n"
    md += "| チャネル | セッション | 購入 | 売上 | CVR |\n"
    md += "|----------|-----------|------|------|-----|\n"

    for ch in channel_data:
        sessions = ch.get('sessions', 0)
        purchases = ch.get('purchases', 0)
        revenue = ch.get('revenue', 0) or 0
        cvr = (purchases / sessions * 100) if sessions > 0 else 0
        md += f"| {ch['medium']} | {sessions:,} | {purchases} | ¥{revenue:,.0f} | {cvr:.1f}% |\n"

    return md

def main():
    week = get_week_number()
    client = bigquery.Client(project=os.getenv('BQ_PROJECT_ID'))
    dataset = os.getenv('BQ_DATASET')
    project_id = os.getenv('BQ_PROJECT_ID')

    # データ取得
    metrics = fetch_weekly_metrics(client, project_id, dataset)
    channel_df = fetch_channel_breakdown(client, project_id, dataset)

    # Markdown生成
    frontmatter = generate_frontmatter(week)
    body = build_report_markdown(metrics, channel_df.to_dict(orient='records'))

    # ファイル出力
    filename = f"weekly-report-{week}.md"
    articles_dir = Path("articles")
    articles_dir.mkdir(exist_ok=True)
    filepath = articles_dir / filename

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(frontmatter + "\n" + body)

    print(f"記事を生成しました: {filepath}")

if __name__ == "__main__":
    main()
```

## 自動化のレベルを段階的に上げる

### Level 1: データ取得とMarkdown生成の自動化

上記のスクリプトで実現できます。記事の公開は手動で判断します。

### Level 2: Claude Codeで考察を自動追加

数値だけでなく「今週の注目ポイント」や「改善提案」をClaude Codeに生成させます。

```bash
claude "以下のデータに基づいて、今週の注目ポイント3つと改善提案2つを考えてください。
$(cat data/processed/weekly_data.json)"
```

### Level 3: GitHubへのpushまで自動化

CI/CDパイプラインに組み込み、毎週月曜日に自動で記事を生成してpushする構成です。

```yaml
# .github/workflows/weekly-report.yml
name: Weekly Report
on:
  schedule:
    - cron: '0 0 * * 1'  # 毎週月曜 09:00 JST
jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -r requirements.txt
      - run: python scripts/generate_weekly_report.py
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
      - run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add articles/
          git commit -m "Add weekly report" || echo "No changes"
          git push
```

:::message
GitHub Actionsでサービスアカウントキーを使う場合は、Repository SecretsにBase64エンコードしたJSONキーを格納し、ジョブ内でデコードして使用する方法が一般的です。
:::

## まとめ

BigQueryのデータ取得からZenn記事公開までの流れを自動化するポイントは以下の3つです。

1. 週次データをBigQueryからJSON形式で取得して中間ファイルに保存する
2. Claude CodeでMarkdownレポートを生成する（考察や提案も含む）
3. Zenn CLIとGitHub連携で公開フローを効率化する

定期的なアウトプットを仕組みとして構築することで、技術ブランディングの継続が容易になります。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
