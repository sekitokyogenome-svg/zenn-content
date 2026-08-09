"""Claude CodeのAgents SDK × BigQueryで複数ECサイトを一括監視する

出典記事: articles/claude-code-agents-sdk-bigquery-multi-ec.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
