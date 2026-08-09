"""Claude CodeのAgents SDKでEC在庫アラート→発注提案→Slack通知を全自動化した

出典記事: articles/claude-agents-sdk-ec-inventory-alert-slack.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import anthropic
import json
from google.cloud import bigquery

client = anthropic.Anthropic()
bq_client = bigquery.Client(project="your_project")

# ---- ツール定義 ----

tools = [
    {
        "name": "get_low_stock_items",
        "description": "BigQueryから在庫残日数がリードタイム以下の商品一覧を取得する",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "post_slack_alert",
        "description": "在庫アラートと発注提案をSlackに投稿する",
        "input_schema": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Slackに投稿するメッセージ本文（Markdown形式）"
                }
            },
            "required": ["message"]
        }
    }
]

# ---- ツール実装 ----

def get_low_stock_items():
    """BigQueryのクエリを実行して低在庫商品を返す"""
    query = """
    -- 上記SQLを文字列として埋め込む
    SELECT product_name, stock_quantity, estimated_days_remaining, avg_daily_sales
    FROM `your_project.ec_data.low_stock_view`
    ORDER BY estimated_days_remaining ASC
    LIMIT 10
    """
    rows = bq_client.query(query).result()
    return [dict(row) for row in rows]

def post_slack_alert(message: str):
    """Slack Incoming Webhookにメッセージを送信する"""
    import urllib.request
    webhook_url = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
    payload = json.dumps({"text": message}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as res:
        return res.read().decode("utf-8")

# ---- エージェントループ ----

def run_inventory_agent():
    messages = [
        {
            "role": "user",
            "content": (
                "今日の在庫状況を確認してください。"
                "在庫残日数がリードタイム以下の商品を抽出し、"
                "各商品への発注推奨数量と優先度をビジネス担当者向けにわかりやすくまとめ、"
                "Slackの#在庫アラートチャンネルに日本語で投稿してください。"
            )
        }
    ]

    while True:
        response = client.messages.create(
            model="claude-sonnet-5",
            max_tokens=2048,
            tools=tools,
            messages=messages
        )

        if response.stop_reason == "end_turn":
            print("エージェント処理完了")
            break

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    if block.name == "get_low_stock_items":
                        result = get_low_stock_items()
                    elif block.name == "post_slack_alert":
                        result = post_slack_alert(block.input["message"])
                    else:
                        result = {"error": "unknown tool"}

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result, ensure_ascii=False)
                    })

            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": tool_results})

if __name__ == "__main__":
    run_inventory_agent()
