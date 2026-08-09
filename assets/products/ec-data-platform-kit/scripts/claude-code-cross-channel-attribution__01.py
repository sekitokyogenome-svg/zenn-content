"""Claude Codeでクロスチャネルアトリビューション分析を自動化した

出典記事: articles/claude-code-cross-channel-attribution.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: attribution_analysis.py
目的: マルチタッチアトリビューション分析を自動実行する
作成日: 2026-03-30
依存: google-cloud-bigquery, anthropic
"""

from google.cloud import bigquery
import anthropic
import os
from dotenv import load_dotenv

load_dotenv()

def run_attribution_query(model: str) -> list:
    """指定モデルのアトリビューションSQLを実行する"""
    client = bigquery.Client()
    sql_path = f"queries/attribution/{model}.sql"
    with open(sql_path, "r") as f:
        query = f.read()
    result = client.query(query).to_dataframe()
    return result.to_dict(orient="records")

def analyze_with_claude(results: dict) -> str:
    """Claude APIでアトリビューション結果を分析する"""
    client = anthropic.Anthropic(
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    import json
    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=4096,
        messages=[{
            "role": "user",
            "content": f"""
以下のアトリビューション分析結果を比較し、
チャネル別の予算配分見直し提案を作成してください。

{json.dumps(results, ensure_ascii=False, indent=2)}
"""
        }]
    )
    return message.content[0].text

def main():
    models = ["last_click", "linear", "time_decay"]
    results = {}
    for model in models:
        print(f"{model}モデルを実行中...")
        results[model] = run_attribution_query(model)

    print("Claude APIで分析中...")
    analysis = analyze_with_claude(results)

    output_path = "reports/attribution_analysis.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(analysis)
    print(f"分析結果を保存しました: {output_path}")

if __name__ == "__main__":
    main()
