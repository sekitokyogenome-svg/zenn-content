"""Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う

出典記事: articles/claude-code-python-review-sentiment-nps.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import anthropic
import json
import time

client = anthropic.Anthropic()

def analyze_sentiment(review_text: str) -> dict:
    """レビューテキストの感情スコアとラベルを返す"""
    prompt = f"""
以下の顧客レビューを感情分析してください。
結果をJSON形式のみで出力してください（説明文は不要）。

フォーマット:
{{"score": 数値(-1.0〜1.0), "label": "positive/neutral/negative", "reason": "理由を20文字以内で"}}

レビュー:
{review_text}
"""
    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=256,
        messages=[{"role": "user", "content": prompt}]
    )
    raw = message.content[0].text.strip()
    return json.loads(raw)


results = []
for i, row in df.iterrows():
    if not row["review_text"]:
        continue
    result = analyze_sentiment(row["review_text"])
    results.append({
        "ga_session_id": row["ga_session_id"],
        "user_pseudo_id": row["user_pseudo_id"],
        "medium": row["medium"],
        "source": row["source"],
        "sentiment_score": result["score"],
        "sentiment_label": result["label"],
        "reason": result["reason"]
    })
    time.sleep(0.3)  # レートリミット対策

df_result = pd.DataFrame(results)
print(df_result.describe())
