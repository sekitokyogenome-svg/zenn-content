"""AI×BigQueryでEC商品説明文のA/Bテスト結果を自動分析・改善提案する仕組み

出典記事: articles/ai-bigquery-ec-product-desc-ab-test-auto.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import os
from google.cloud import bigquery
from anthropic import Anthropic

# クライアント初期化
bq_client = bigquery.Client(project="your_project")
ai_client = Anthropic()

# BigQueryでA/Bテスト結果を取得
def fetch_ab_test_results(query: str) -> str:
    query_job = bq_client.query(query)
    rows = query_job.result()
    lines = ["バリアント,セッション数,カート追加数,購入数,カート追加率(%),購入率(%)"]
    for row in rows:
        lines.append(
            f"{row.ab_variant},{row.sessions},{row.add_to_cart_count},"
            f"{row.purchase_count},{row.add_to_cart_rate},{row.purchase_rate}"
        )
    return "\n".join(lines)


# AIに改善提案を依頼
def generate_suggestions(ab_result_csv: str, product_name: str) -> str:
    prompt = f"""
以下は「{product_name}」の商品説明文A/Bテスト結果（過去30日）です。

{ab_result_csv}

このデータをもとに、以下の観点で分析と提案をしてください。
1. どちらのバリアントがより良いパフォーマンスを示しているか
2. 購入率・カート追加率の差異から読み取れる仮説
3. 次のA/Bテストに向けた具体的な改善案（商品説明文の観点から3点）

なお、サンプル数が少ない場合はその旨も言及してください。
回答は日本語で、箇条書きを交えて読みやすくまとめてください。
"""
    message = ai_client.messages.create(
        model="claude-opus-5",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )
    return message.content[0].text


if __name__ == "__main__":
    SQL = """
    -- 上記のSQLをここに貼り付け
    """
    result_csv = fetch_ab_test_results(SQL)
    suggestion = generate_suggestions(result_csv, product_name="〇〇商品")
    print(suggestion)
