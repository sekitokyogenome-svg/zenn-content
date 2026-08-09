"""Claude Code × Gemini CLIをオーケストレーションしてEC分析を多角的に回す方法

出典記事: articles/claude-code-gemini-cli-orchestration-ec.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import subprocess
import json

def run_bq_query(sql: str) -> str:
    """BigQueryクエリを実行してJSON文字列で返す"""
    result = subprocess.run(
        ["bq", "query", "--use_legacy_sql=false", "--format=json", sql],
        capture_output=True, text=True
    )
    return result.stdout

def ask_claude(prompt: str, context: str) -> str:
    """Claude Codeにプロンプトを送って回答を取得"""
    full_prompt = f"{prompt}\n\nデータ:\n{context}"
    result = subprocess.run(
        ["claude", "-p", full_prompt],
        capture_output=True, text=True
    )
    return result.stdout.strip()

def ask_gemini(prompt: str, context: str) -> str:
    """Gemini CLIにプロンプトを送って回答を取得"""
    full_prompt = f"{prompt}\n\nデータ:\n{context}"
    result = subprocess.run(
        ["gemini", "-p", full_prompt],
        capture_output=True, text=True
    )
    return result.stdout.strip()

if __name__ == "__main__":
    sql = """
    SELECT
      source, medium,
      COUNT(DISTINCT ga_session_id) AS sessions,
      SUM(has_purchase) AS purchases
    FROM `your_project.analytics_XXXXXXXXX.session_summary`
    GROUP BY source, medium
    ORDER BY sessions DESC
    LIMIT 10
    """
    data = run_bq_query(sql)

    claude_resp = ask_claude(
        "このデータに対して、購買数を増やすための追加分析クエリを1つ提案してください",
        data
    )

    gemini_resp = ask_gemini(
        "このEC流入元データを見て、注力すべき施策を日本語で簡潔に教えてください",
        data
    )

    print("【Claude Codeの提案】")
    print(claude_resp)
    print("\n【Gemini CLIの解釈】")
    print(gemini_resp)
