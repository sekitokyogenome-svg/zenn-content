---
title: "BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み"
emoji: "📊"
type: "tech"
topics: ["claudecode", "bigquery", "automation"]
published: false
---

## はじめに

「毎月の事業報告書、手作業でデータを集めて資料にするのが辛い」

月次報告書は経営において重要なアウトプットですが、データの集計からレポートの作成まで手動で行うと、半日以上かかることもあります。

この記事では、BigQueryからKPIデータを抽出し、Claude Codeで**Markdownの月次報告書を自動生成**し、Slackに通知するまでの仕組みを紹介します。

---

## 全体アーキテクチャ

```
BigQuery（GA4 + 売上データ）
    ↓ SQL実行
KPIデータ（CSV / JSON）
    ↓ Claude Code
月次報告書（Markdown）
    ↓ Slack API
チームに自動通知
```

この3ステップをPythonスクリプトでつなぎます。

---

## Step 1：月次KPIを抽出するSQLを作成する

まず、BigQueryで月次の主要KPIを集計するSQLを用意します。

### セッション・CV・売上の月次サマリ

```sql
-- 月次KPIサマリ
WITH monthly_data AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN user_pseudo_id END) AS purchasers,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY month
)
SELECT
  month,
  sessions,
  purchasers,
  revenue,
  SAFE_DIVIDE(purchasers, sessions) AS cvr,
  SAFE_DIVIDE(revenue, purchasers) AS avg_order_value
FROM monthly_data;
```

### チャネル別パフォーマンス

```sql
-- チャネル別月次パフォーマンス
SELECT
  CONCAT(
    IFNULL(collected_traffic_source.manual_source, '(direct)'),
    ' / ',
    IFNULL(collected_traffic_source.manual_medium, '(none)')
  ) AS channel,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  SUM(CASE WHEN event_name = 'purchase'
    THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
FROM `project.analytics_XXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY channel
ORDER BY sessions DESC
LIMIT 10;
```

---

## Step 2：Pythonスクリプトでデータを取得する

BigQuery Pythonクライアントでデータを取得し、辞書形式に変換します。

```python
"""
モジュール名: monthly_report_generator.py
目的: BigQueryからKPIを取得しClaude Codeで月次報告書を生成する
作成日: 2026-03-30
依存: google-cloud-bigquery, anthropic
"""

from google.cloud import bigquery
import json

def fetch_monthly_kpi() -> dict:
    """BigQueryから月次KPIを取得する"""
    client = bigquery.Client()

    # サマリクエリ
    summary_query = open("queries/monthly_summary.sql").read()
    summary_df = client.query(summary_query).to_dataframe()

    # チャネル別クエリ
    channel_query = open("queries/monthly_channel.sql").read()
    channel_df = client.query(channel_query).to_dataframe()

    return {
        "summary": summary_df.to_dict(orient="records"),
        "channels": channel_df.to_dict(orient="records"),
        "period": summary_df["month"].iloc[0] if len(summary_df) > 0 else "N/A"
    }
```

---

## Step 3：Claude Codeでレポートを自動生成する

取得したKPIデータをClaude APIに渡し、Markdownレポートを生成します。

```python
import anthropic
import os
from dotenv import load_dotenv

load_dotenv()

def generate_report(kpi_data: dict) -> str:
    """KPIデータからMarkdown月次報告書を生成する"""
    client = anthropic.Anthropic(
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    prompt = f"""
以下のKPIデータから月次事業報告書をMarkdown形式で作成してください。

## データ
{json.dumps(kpi_data, ensure_ascii=False, indent=2)}

## レポート要件
1. エグゼクティブサマリ（3行以内）
2. 主要KPIの前月比較（上昇/下降の矢印付き）
3. チャネル別パフォーマンスのテーブル
4. 課題と改善提案（3つ以内）
5. 来月のアクションアイテム

数値にはカンマ区切りを使い、割合は小数点1桁まで表示してください。
"""

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=4096,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )
    return message.content[0].text
```

:::message
APIキーは `.env` ファイルに記載し、`python-dotenv` で読み込みます。コードにハードコードしないでください。
:::

---

## Step 4：Slackに通知する

生成したレポートをSlackに投稿します。

```python
import requests

def notify_slack(report: str, webhook_url: str) -> None:
    """SlackにMarkdownレポートを投稿する"""
    payload = {
        "text": f"📊 月次事業報告書が生成されました",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": report[:3000]  # Slack文字数制限を考慮
                }
            }
        ]
    }

    try:
        response = requests.post(webhook_url, json=payload)
        response.raise_for_status()
        print("Slack通知が完了しました")
    except requests.exceptions.RequestException as e:
        print(f"Slack通知に失敗しました: {e}")
```

---

## Step 5：すべてをつなげるメインスクリプト

```python
def main():
    """月次報告書の自動生成メインフロー"""
    print("月次KPIデータを取得中...")
    kpi_data = fetch_monthly_kpi()

    print("レポートを生成中...")
    report = generate_report(kpi_data)

    # ファイルに保存
    output_path = f"reports/monthly_{kpi_data['period']}.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"レポートを保存しました: {output_path}")

    # Slack通知
    webhook_url = os.getenv("SLACK_WEBHOOK_URL")
    if webhook_url:
        notify_slack(report, webhook_url)

if __name__ == "__main__":
    main()
```

---

## 定期実行の設定

月初に自動で実行するには、cron（Linux/Mac）またはタスクスケジューラ（Windows）を使います。

```bash
# cron設定例（毎月1日の朝9時に実行）
0 9 1 * * cd /path/to/project && python monthly_report_generator.py
```

GCPを使っている場合は、Cloud Schedulerでの定期実行も選択肢になります。

---

## 生成されるレポートの例

以下のようなMarkdownレポートが自動生成されます。

```markdown
# 月次事業報告書（2026年3月）

## エグゼクティブサマリ
3月はセッション数が前月比+12%と堅調に推移。
CVRは1.8%から2.1%に改善し、売上は前月比+23%を達成した。

## 主要KPI
| 指標 | 今月 | 前月 | 前月比 |
|------|------|------|--------|
| セッション | 12,345 | 11,023 | ↑ +12.0% |
| CV数 | 259 | 198 | ↑ +30.8% |
| CVR | 2.1% | 1.8% | ↑ +0.3pt |
| 売上 | ¥1,234,567 | ¥1,003,210 | ↑ +23.0% |

## 課題と改善提案
1. Direct流入のCVRが低い → LP改善を検討
2. モバイルのカート放棄率が高い → 決済UIの見直し
```

---

## まとめ

BigQuery × Claude Codeで月次報告書を自動化する仕組みを紹介しました。

ポイントは以下の3つです。

1. BigQueryでKPI抽出SQLをテンプレート化しておく
2. Claude APIでデータからMarkdownレポートを生成する
3. Slackに自動通知して、チームにすぐ共有する

毎月の報告書作成に数時間かけている方は、この仕組みで作業時間を大幅に削減できるはずです。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
