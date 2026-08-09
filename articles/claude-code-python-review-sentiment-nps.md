---
title: "Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う"
emoji: "💬"
type: "tech"
topics: ["claude","python","bigquery","ai","ec"]
published: false
---

## はじめに

ECサイトを運営していると、商品レビューや問い合わせフォームへのコメントが日々蓄積されていきます。「とりあえず読んでいる」という方も多いかと思いますが、100件・200件と増えてくると、全件を丁寧に読み込んでトレンドを把握するのは現実的ではありません。「どの商品の評判が落ちているのか」「どの流入経路で購入した顧客が不満を抱きやすいのか」—そうした問いに、データとして答えられている事業者はまだ多くありません。

感情分析（Sentiment Analysis）は、テキストデータをポジティブ・ネガティブ・ニュートラルに自動分類する技術です。以前は専門的な機械学習の知識が必要でしたが、現在はClaude CodeとPythonを組み合わせることで、エンジニア経験が浅い方でも実装できる水準まで下がっています。

本記事では、顧客レビューをClaudeのAPIで感情スコアリングし、NPS（ネットプロモータースコア）予測へ活用するまでの流れを解説します。BigQueryに蓄積されたGA4データと組み合わせることで、「どの流入経路の顧客が高評価をつけやすいか」まで分析できる仕組みを構築します。

---

## NPSと感情分析の関係を整理する

NPSとは、「この商品・サービスを知人に勧めたいですか？（0〜10点）」という1問で顧客ロイヤルティを測る指標です。9〜10点が推奨者、7〜8点が中立者、0〜6点が批判者に分類され、推奨者の割合から批判者の割合を引いた値がNPSになります。

ただし、NPS調査を全顧客に対して定期実施するのはコストがかかります。そこで役立つのが感情分析です。購入後レビューや問い合わせメッセージのテキストには、顧客の満足度・不満・期待感が自然言語で表現されています。これをスコアに変換することで、「NPSアンケートを送らなくても推定的に満足度を測る」代替指標として活用できます。

感情スコアとNPS実測値を数ヶ月分突き合わせると、両者に一定の相関が見えてくることがあります。完全な代替にはなりませんが、施策の優先度判断や改善ポイントの絞り込みには十分な精度で活用できます。

---

## 環境構築：Claude CodeとAnthropicライブラリの準備

まずPython環境を整えます。Claude Code（Anthropicが提供するAIコーディングアシスタント）をターミナルで使うことで、コードの作成・修正・デバッグを会話形式で進められます。

```bash
# 仮想環境の作成と有効化
python -m venv venv
source venv/bin/activate  # Windowsの場合: venv\Scripts\activate

# 必要なライブラリのインストール
pip install anthropic pandas google-cloud-bigquery db-dtypes
```

AnthropicのAPIキーを環境変数に設定します。

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

APIキーはAnthropicのコンソール（console.anthropic.com）から発行できます。GCPのBigQueryに接続する場合は、サービスアカウントのJSONキーも併せて用意してください。

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account.json"
```

---

## BigQueryからレビューデータとGA4流入情報を取得する

BigQueryにはGA4のイベントデータが蓄積されています。ここでは購入完了後に発生するレビュー投稿イベントと、その購入セッションの流入元情報を紐付けるSQLを示します。

GA4のBigQueryエクスポートでは、`event_params`がネスト構造になっているため、`ga_session_id`を取得する際は`UNNEST`が必要です。また流入元の情報は`collected_traffic_source`列から参照します。

```sql
SELECT
  ep.value.int_value AS ga_session_id,
  e.user_pseudo_id,
  e.event_date,
  cts.manual_medium AS medium,
  cts.manual_source AS source,
  ep2.value.string_value AS review_text
FROM
  `your_project.analytics_XXXXXXX.events_*` AS e,
  UNNEST(e.event_params) AS ep,
  UNNEST(e.event_params) AS ep2
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cts
WHERE
  e.event_name = 'review_submit'
  AND ep.key = 'ga_session_id'
  AND ep2.key = 'review_body'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
```

このクエリで取得した結果をPandasのDataFrameに読み込みます。

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client()

query = """
-- 上記SQLをここに貼り付け
"""

df = client.query(query).to_dataframe()
print(df.head())
```

`review_text`列にレビュー本文が入った状態のDataFrameが得られれば、次の感情分析ステップに進めます。

---

## ClaudeのAPIで感情スコアリングを実装する

取得したレビューテキストをAnthropicのAPIに渡し、感情スコアを返してもらいます。スコアは「-1.0（非常にネガティブ）〜 +1.0（非常にポジティブ）」の範囲で数値化するようプロンプトで指定します。

```python
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
        model="claude-sonnet-4-5",
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
```

:::message
APIの呼び出し回数が多い場合はバッチ処理を分割し、エラーハンドリング（try/except）を加えると安定して動作します。大量のレビューを処理する際は、1件ずつではなく複数件をまとめてプロンプトに渡す「バルク送信」も検討してください。
:::

---

## 流入経路別・感情スコアの集計とNPS予測への応用

感情スコアが揃ったら、流入経路（medium/source）別に集計します。「SNS広告経由の顧客は評価が低い傾向がある」「SEO流入の顧客は高評価が多い」といった傾向が可視化できれば、広告予算の配分見直しや商品ページの改善優先度の判断材料になります。

```python
import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.family'] = 'IPAexGothic'  # 日本語フォント

# 流入経路別の平均感情スコア
summary = (
    df_result
    .groupby("medium")["sentiment_score"]
    .agg(["mean", "count"])
    .rename(columns={"mean": "avg_score", "count": "review_count"})
    .sort_values("avg_score", ascending=False)
)

print(summary)

# 可視化
summary["avg_score"].plot(kind="bar", figsize=(10, 5), color="steelblue")
plt.title("流入経路別 平均感情スコア")
plt.xlabel("流入経路（medium）")
plt.ylabel("感情スコア（-1〜+1）")
plt.axhline(0, color="red", linestyle="--")
plt.tight_layout()
plt.savefig("sentiment_by_medium.png", dpi=150)
```

NPS予測への応用としては、感情スコアを以下のように変換するシンプルな手法があります。

```python
def score_to_nps_band(score: float) -> str:
    """感情スコアをNPS分類に変換（推定）"""
    if score >= 0.6:
        return "推奨者（9〜10点相当）"
    elif score >= 0.1:
        return "中立者（7〜8点相当）"
    else:
        return "批判者（0〜6点相当）"

df_result["nps_band"] = df_result["sentiment_score"].apply(score_to_nps_band)
nps_distribution = df_result["nps_band"].value_counts(normalize=True) * 100
print(nps_distribution)
```

このスコアとNPSアンケートの実測値を数ヶ月分比較し、分類精度を検証することで、推定NPSとしての信頼性を高めていくことができます。

---

## まとめ

本記事では、Claude Code × PythonでECサイトの顧客レビューを感情分析し、NPS予測に活用する方法を解説しました。要点を整理します。

- **BigQueryのGA4データとレビューを紐付ける**ことで、流入経路別の顧客満足度が見えてくる
- **AnthropicのAPIを使った感情スコアリング**は、専門的なML知識がなくてもPythonで実装できる
- **感情スコア → NPS帯への変換**により、アンケートを送らずに推定NPSを継続観測できる
- `ga_session_id`はBigQueryで`UNNEST(event_params)`経由で取得し、流入元は`collected_traffic_source`を参照する点に注意

次のアクションとして、まずは直近3ヶ月分のレビューデータを抽出し、感情スコアの分布を可視化してみてください。「どの流入経路の顧客が最も不満を持っているか」が見えてくると、改善施策の優先度が立てやすくなります。BigQuery上の結果をLooker Studioに接続すれば、ダッシュボードとして定点観測する仕組みも構築できます。

## 関連記事

- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
