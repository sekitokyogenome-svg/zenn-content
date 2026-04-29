---
title: "Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した"
emoji: "📊"
type: "tech"
topics: ["claudecode","bigquery","advertising"]
published: true
---

## はじめに

「Google広告、Meta広告、LINE広告…それぞれの管理画面を開いてROASを比較するのが手間すぎる」

複数の広告媒体を運用しているEC事業者にとって、媒体横断でのROAS比較は重要な業務です。しかし、各媒体の管理画面にログインし、期間を揃え、数値をスプレッドシートに転記する作業は非効率的です。

本記事では、BigQueryに集約した広告データをClaude Codeで一括比較するスクリプトを作成した過程を紹介します。

## 全体アーキテクチャ

```text
[Google Ads API] ──→ BigQuery (raw_google_ads)
[Meta Marketing API] ──→ BigQuery (raw_meta_ads)     ──→ 統合ビュー ──→ ROAS比較レポート
[LINE Ads API] ──→ BigQuery (raw_line_ads)
```

各広告媒体のAPIからデータを取得し、BigQueryに格納します。その後、統合ビューを作成してROASを横断比較する構成です。

## Step 1: BigQueryに広告データを集約する

### テーブル設計

各媒体のデータを統一的に扱うため、共通のスキーマを定義します。

```sql
-- 広告データ統合ビュー
CREATE OR REPLACE VIEW `project.dataset.unified_ad_performance` AS

-- Google Ads
SELECT
  'google' AS platform,
  segments_date AS date,
  campaign_name,
  metrics_cost_micros / 1000000 AS cost,
  metrics_conversions AS conversions,
  metrics_conversions_value AS conversion_value,
  metrics_clicks AS clicks,
  metrics_impressions AS impressions
FROM
  `project.dataset.raw_google_ads`

UNION ALL

-- Meta Ads
SELECT
  'meta' AS platform,
  date_start AS date,
  campaign_name,
  spend AS cost,
  CAST(actions_purchase AS FLOAT64) AS conversions,
  action_values_purchase AS conversion_value,
  clicks,
  impressions
FROM
  `project.dataset.raw_meta_ads`

UNION ALL

-- LINE Ads
SELECT
  'line' AS platform,
  report_date AS date,
  campaign_name,
  cost,
  conversions,
  conversion_value,
  clicks,
  impressions
FROM
  `project.dataset.raw_line_ads`
```

:::message
各広告媒体のAPIレスポンスはスキーマが異なります。データ取得スクリプトの段階でカラム名を統一するか、上記のようにビューで吸収するかはプロジェクトの方針に合わせて選択してください。
:::

## Step 2: Claude CodeでROAS比較スクリプトを生成する

Claude Codeに以下のように指示します。

```bash
claude "BigQueryのunified_ad_performanceビューから、
媒体別・月別のROASを計算して比較するPythonスクリプトを作って。
出力はCSVとMarkdownの両方で。"
```

生成されたスクリプト：

```python
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
```

## Step 3: GA4のコンバージョンデータと突合する

広告媒体の管理画面とGA4のコンバージョン数には乖離が生じることが一般的です。GA4側のデータも取得して突合する処理を追加します。

```sql
-- GA4側のチャネル別コンバージョン
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS ga4_conversions,
  SUM(ecommerce.purchase_revenue) AS ga4_revenue
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  medium, source
ORDER BY
  ga4_revenue DESC
```

:::message
広告媒体のCV数とGA4のCV数が異なるのは正常です。アトリビューションモデル、計測タイミング、クロスデバイス計測の有無など、複数の要因が影響します。両方の数値を把握した上で判断することが重要です。
:::

## Step 4: アラート機能を追加する

ROASが基準値を下回った場合に通知する機能も、Claude Codeに追加させました。

```python
def check_roas_alerts(df: pd.DataFrame, threshold: float = 2.0) -> list[dict]:
    """ROASが閾値を下回る媒体を検出する"""
    latest_month = df['month'].max()
    latest_data = df[df['month'] == latest_month]
    alerts = []

    for _, row in latest_data.iterrows():
        if row['roas'] < threshold and row['total_cost'] > 10000:
            alerts.append({
                'platform': row['platform'],
                'roas': row['roas'],
                'cost': row['total_cost'],
                'message': f"{row['platform']}のROASが{row['roas']}xに低下（閾値: {threshold}x）"
            })

    return alerts
```

`total_cost > 10000` の条件を入れているのは、少額テスト配信でのノイズを除外するためです。閾値はビジネスの利益率に応じて調整してください。

## 運用で得られた知見

### 媒体間の比較で見えてくること

実際にこのスクリプトを1ヶ月運用して、以下のような気づきが得られました。

- Google広告はCPAが低いがLTVも低い傾向がある
- Meta広告はCPAが高いがリピート率が高い
- LINE広告はCTRが高いがCVRが低い

ROASだけで判断すると見誤るケースがあるため、CPAやCVRなど複数の指標を組み合わせて評価する仕組みにしています。

### 自動化のポイント

- 日次でデータを取得し、BigQueryに蓄積する
- 週次でROAS比較レポートを自動生成する
- ROASが閾値を下回った場合にSlack通知する

この3つを組み合わせることで、広告運用の異常検知が早まり、無駄な広告費の支出を抑えられます。

## まとめ

複数広告媒体のROAS比較は、以下の手順で自動化できます。

1. 各媒体のAPIデータをBigQueryに集約する
2. 統合ビューで共通スキーマに揃える
3. Claude CodeでROAS比較スクリプトを生成する
4. GA4データとの突合やアラート機能を追加する

媒体ごとの管理画面を行き来する時間を削減し、データに基づいた広告予算の配分判断に集中できる環境を構築してみてください。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
