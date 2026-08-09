"""Claude Codeに週次レポートをMarkdownで生成させてそのままZennに投稿する

出典記事: articles/claude-code-weekly-report-markdown-zenn.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
