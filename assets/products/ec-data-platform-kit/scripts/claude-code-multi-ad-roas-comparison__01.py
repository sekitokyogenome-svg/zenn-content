"""Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した

出典記事: articles/claude-code-multi-ad-roas-comparison.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: ad_roas_comparison.py
目的: 複数広告媒体のROASを一括比較するレポートを生成する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
from pathlib import Path

def fetch_ad_performance(client: bigquery.Client, project_id: str, dataset: str, days: int = 90) -> pd.DataFrame:
    """統合広告データをBigQueryから取得する"""
    query = f"""
    SELECT
      platform,
      FORMAT_DATE('%Y-%m', date) AS month,
      SUM(cost) AS total_cost,
      SUM(conversion_value) AS total_conversion_value,
      SUM(conversions) AS total_conversions,
      SUM(clicks) AS total_clicks,
      SUM(impressions) AS total_impressions
    FROM
      `{project_id}.{dataset}.unified_ad_performance`
    WHERE
      date >= DATE_SUB(CURRENT_DATE(), INTERVAL {days} DAY)
    GROUP BY
      platform, month
    ORDER BY
      month DESC, platform
    """
    return client.query(query).to_dataframe()

def calculate_roas_metrics(df: pd.DataFrame) -> pd.DataFrame:
    """ROAS関連の指標を計算する"""
    df['roas'] = df.apply(
        lambda row: round(row['total_conversion_value'] / row['total_cost'], 2)
        if row['total_cost'] > 0 else 0,
        axis=1
    )
    df['cpa'] = df.apply(
        lambda row: round(row['total_cost'] / row['total_conversions'], 0)
        if row['total_conversions'] > 0 else 0,
        axis=1
    )
    df['ctr'] = df.apply(
        lambda row: round(row['total_clicks'] / row['total_impressions'] * 100, 2)
        if row['total_impressions'] > 0 else 0,
        axis=1
    )
    df['cvr'] = df.apply(
        lambda row: round(row['total_conversions'] / row['total_clicks'] * 100, 2)
        if row['total_clicks'] > 0 else 0,
        axis=1
    )
    return df

def generate_markdown_report(df: pd.DataFrame) -> str:
    """ROAS比較のMarkdownレポートを生成する"""
    report = "# 広告媒体別ROAS比較レポート\n\n"

    for month in sorted(df['month'].unique(), reverse=True):
        month_data = df[df['month'] == month]
        report += f"## {month}\n\n"
        report += "| 媒体 | 広告費 | CV値 | ROAS | CPA | CTR | CVR |\n"
        report += "|------|--------|------|------|-----|-----|-----|\n"

        for _, row in month_data.iterrows():
            report += (
                f"| {row['platform']} "
                f"| ¥{row['total_cost']:,.0f} "
                f"| ¥{row['total_conversion_value']:,.0f} "
                f"| {row['roas']}x "
                f"| ¥{row['cpa']:,.0f} "
                f"| {row['ctr']}% "
                f"| {row['cvr']}% |\n"
            )
        report += "\n"

    return report

def main():
    client = bigquery.Client()
    project_id = "your-project"
    dataset = "your_dataset"

    # データ取得
    df = fetch_ad_performance(client, project_id, dataset)

    # 指標計算
    df = calculate_roas_metrics(df)

    # CSV出力
    output_dir = Path("data/processed")
    output_dir.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_dir / "ad_roas_comparison.csv", index=False)

    # Markdownレポート出力
    report = generate_markdown_report(df)
    with open(output_dir / "ad_roas_report.md", "w", encoding="utf-8") as f:
        f.write(report)

    print("レポート生成完了")

if __name__ == "__main__":
    main()
