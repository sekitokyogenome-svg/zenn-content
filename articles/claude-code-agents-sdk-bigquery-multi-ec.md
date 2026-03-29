---
title: "Claude CodeのAgents SDK × BigQueryで複数ECサイトを一括監視する"
emoji: "🤖"
type: "tech"
topics: ["claudecode", "bigquery", "agentssdk"]
published: false
---

## はじめに

「ECサイトを複数運営しているけど、各サイトのGA4を個別にチェックする時間がない」

複数のECサイトを運営・支援している事業者にとって、サイトごとにBigQueryのコンソールを開いてクエリを実行するのは非効率です。特に異常値の検知は、早期発見が重要なのに人手のチェックでは遅れがちです。

この記事では、Claude CodeのAgents SDKを使い、複数ECサイトのGA4データをBigQueryから一括で監視し、異常検知を自動化するアーキテクチャを紹介します。

---

## Agents SDKとは

Agents SDKは、Anthropicが提供するPythonフレームワークで、複数のAIエージェントを連携させてタスクを実行できます。

主な特徴は以下の通りです。

- **ツール定義**: エージェントが使えるツール（関数）を定義できる
- **ハンドオフ**: エージェント間でタスクを引き継げる
- **ガードレール**: 入出力のバリデーションを組み込める

```bash
# Agents SDKのインストール
pip install claude-agent-sdk
```

:::message
Agents SDKの利用にはAnthropicのAPIキーが必要です。詳細は[公式ドキュメント](https://docs.anthropic.com/en/docs/agents-sdk)を確認してください。
:::

---

## 全体アーキテクチャ

```
[Cloud Scheduler] 毎朝7:00 JST
       ↓ トリガー
[オーケストレーター Agent]
       ↓ サイトごとにハンドオフ
[サイト監視 Agent] × N サイト
       ↓ BigQuery クエリ実行
[異常検知 Agent]
       ↓ 判定・分析
[通知 Agent]
       ↓
[Slack / メール]
```

4種類のエージェントが役割分担し、各サイトのデータを並列で監視します。

---

## Step 1：サイト設定を定義する

監視対象のサイトをYAMLで管理します。

```yaml
# config/sites.yaml
sites:
  - name: "サイトA"
    project: "project-a"
    dataset: "analytics_111111111"
    slack_channel: "#site-a-alerts"
    thresholds:
      session_drop_pct: 30
      cvr_drop_pct: 20
      revenue_drop_pct: 25

  - name: "サイトB"
    project: "project-b"
    dataset: "analytics_222222222"
    slack_channel: "#site-b-alerts"
    thresholds:
      session_drop_pct: 25
      cvr_drop_pct: 15
      revenue_drop_pct: 20
```

---

## Step 2：BigQueryクエリツールを定義する

エージェントがBigQueryにアクセスするためのツールを定義します。

```python
"""
モジュール名: tools/bigquery_tool.py
目的: Agents SDKのツールとしてBigQueryクエリを実行する
作成日: 2026-03-30
依存: google-cloud-bigquery, claude-agent-sdk
"""

from google.cloud import bigquery

def query_bigquery(
    project: str, dataset: str, query_template: str
) -> list:
    """BigQueryクエリを実行して結果を返す"""
    client = bigquery.Client(project=project)

    query = query_template.replace("{dataset}", f"{project}.{dataset}")
    result = client.query(query).to_dataframe()
    return result.to_dict(orient="records")

# 日次KPIクエリテンプレート
DAILY_KPI_QUERY = """
WITH today AS (
  SELECT
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `{dataset}.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE(
    '%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
prev_week AS (
  SELECT
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `{dataset}.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE(
    '%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY))
)
SELECT
  t.sessions AS today_sessions,
  p.sessions AS prev_sessions,
  SAFE_DIVIDE(t.sessions - p.sessions, p.sessions) * 100
    AS session_change_pct,
  t.purchases AS today_purchases,
  SAFE_DIVIDE(t.purchases, t.sessions) * 100 AS today_cvr,
  SAFE_DIVIDE(p.purchases, p.sessions) * 100 AS prev_cvr,
  t.revenue AS today_revenue,
  p.revenue AS prev_revenue,
  SAFE_DIVIDE(t.revenue - p.revenue, p.revenue) * 100
    AS revenue_change_pct
FROM today t, prev_week p;
"""
```

---

## Step 3：エージェントを定義する

Agents SDKを使って、各エージェントを定義します。

```python
"""
モジュール名: agents/monitor_agents.py
目的: 複数ECサイト監視用エージェントを定義する
作成日: 2026-03-30
依存: claude-agent-sdk
"""

from claude_agent_sdk import Agent, Tool
import yaml
import json

# サイト設定を読み込む
with open("config/sites.yaml", "r") as f:
    config = yaml.safe_load(f)

# BigQueryクエリツール
bq_tool = Tool(
    name="query_bigquery",
    description="BigQueryにクエリを実行してKPIデータを取得する",
    function=query_bigquery
)

# サイト監視エージェント
site_monitor = Agent(
    name="SiteMonitor",
    instructions="""
あなたはECサイトの監視エージェントです。
BigQueryからKPIデータを取得し、異常値がないかチェックします。

チェック項目:
- セッション数の前週同曜日比
- CVR（コンバージョン率）の変動
- 売上金額の変動

閾値を超える変動があった場合、異常として報告してください。
""",
    tools=[bq_tool]
)

# 異常検知エージェント
anomaly_detector = Agent(
    name="AnomalyDetector",
    instructions="""
あなたは異常検知の専門家です。
サイト監視エージェントから受け取ったKPIデータを分析し、
以下の観点で判定してください:

1. 閾値超過の有無（設定ファイルの thresholds を参照）
2. 異常の深刻度（低/中/高）
3. 考えられる原因の仮説（3つ以内）
4. 推奨アクション

出力はJSON形式で返してください。
"""
)

# 通知エージェント
notifier = Agent(
    name="Notifier",
    instructions="""
あなたは通知担当エージェントです。
異常検知エージェントの結果を受け取り、
Slack通知用のメッセージを作成してください。

フォーマット:
- 深刻度が高い場合: 🚨 をつける
- 深刻度が中の場合: ⚠️ をつける
- 深刻度が低い場合: ℹ️ をつける
"""
)
```

---

## Step 4：オーケストレーターで全体を制御する

```python
"""
モジュール名: main.py
目的: 複数サイト監視のオーケストレーション
作成日: 2026-03-30
依存: claude-agent-sdk, pyyaml
"""

from claude_agent_sdk import Orchestrator
import os
from dotenv import load_dotenv

load_dotenv()

def run_multi_site_monitor():
    """全サイトの監視を実行する"""
    orchestrator = Orchestrator(
        agents=[site_monitor, anomaly_detector, notifier],
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    results = []
    for site in config["sites"]:
        print(f"監視中: {site['name']}")

        # サイト監視 → 異常検知 → 通知 のフローを実行
        result = orchestrator.run(
            initial_agent=site_monitor,
            input_data={
                "site_name": site["name"],
                "project": site["project"],
                "dataset": site["dataset"],
                "thresholds": site["thresholds"],
                "query_template": DAILY_KPI_QUERY
            },
            handoff_sequence=[
                anomaly_detector,
                notifier
            ]
        )
        results.append(result)

    return results

if __name__ == "__main__":
    run_multi_site_monitor()
```

---

## Step 5：Cloud Schedulerで定期実行する

GCPのCloud Schedulerで毎朝自動実行します。

```bash
# Cloud Functionsにデプロイ
gcloud functions deploy multi-site-monitor \
  --runtime python311 \
  --trigger-http \
  --entry-point run_multi_site_monitor \
  --region asia-northeast1 \
  --timeout 300

# Cloud Schedulerで定期実行を設定
gcloud scheduler jobs create http site-monitor-daily \
  --schedule="0 7 * * *" \
  --time-zone="Asia/Tokyo" \
  --uri="https://asia-northeast1-your-project.cloudfunctions.net/multi-site-monitor" \
  --http-method=POST
```

---

## 異常検知の精度を上げるコツ

### 1. 曜日を考慮する

ECサイトは曜日によるトラフィック変動が大きいです。前日比ではなく、前週同曜日比で比較するのが基本です。

### 2. 閾値はサイトごとに調整する

サイトの規模やジャンルによって「正常な変動幅」は異なります。最初は緩めの閾値から始めて、誤検知の頻度を見ながら調整してください。

### 3. 季節変動を除外する

セール期間やイベント時期は通常と異なるトラフィックパターンになります。設定ファイルに除外期間を追加する仕組みがあると便利です。

```yaml
# 除外期間の設定例
exclusion_periods:
  - start: "2026-12-01"
    end: "2026-12-31"
    reason: "年末セール期間"
```

---

## まとめ

Agents SDK × BigQueryで複数ECサイトの一括監視を自動化しました。

1. サイト設定をYAMLで一元管理する
2. エージェントに役割を分担させ、監視 → 検知 → 通知のフローを自動化する
3. Cloud Schedulerで毎朝自動実行する

複数サイトの運営・支援をしている方は、手動チェックからの脱却として検討してみてください。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
