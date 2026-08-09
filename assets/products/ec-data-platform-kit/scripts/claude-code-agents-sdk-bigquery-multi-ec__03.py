"""Claude CodeのAgents SDK × BigQueryで複数ECサイトを一括監視する

出典記事: articles/claude-code-agents-sdk-bigquery-multi-ec.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
