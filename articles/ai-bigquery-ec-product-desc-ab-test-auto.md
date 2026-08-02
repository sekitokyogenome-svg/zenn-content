---
title: "AI×BigQueryでEC商品説明文のA/Bテスト結果を自動分析・改善提案する仕組み"
emoji: "🧪"
type: "tech"
topics: ["bigquery","ai","ec","googleanalytics","claude"]
published: false
---

## はじめに

ECサイトの商品説明文を書き換えたら、売上はどう変わるのでしょうか？「より詳細なスペック情報を記載したほうが良いのか」「感情に訴えるコピーにしたほうがコンバージョンが上がるのか」——こうした問いに対して、勘や経験ではなくデータを根拠に判断できているECサイトは、実際にはそれほど多くありません。

A/Bテスト自体は多くの方がご存知の手法ですが、「テスト結果を読み解いて次のアクションに落とし込む」という工程が意外と手間のかかる作業です。BigQueryにGA4のデータが蓄積されていても、SQLを書いてデータを取り出し、それを解釈してライターや運営担当に共有するまでに、数時間〜丸1日かかってしまうケースも珍しくありません。

本記事では、GA4のBigQueryエクスポートデータを活用してA/Bテストの結果を集計し、その数値をAI（Claude APIなど）に渡して改善提案を自動生成する仕組みの構築方法を紹介します。エンジニアでなくても理解できるよう、仕組みの全体像から具体的なSQL・Pythonコードまで順を追って解説します。

---

## 全体アーキテクチャの概要

まず、今回構築する仕組みの全体像を把握しておきましょう。

```
GA4（計測）
  ↓ 日次エクスポート
BigQuery（データ蓄積）
  ↓ SQLで集計
Python スクリプト（集計結果を取得）
  ↓ プロンプトと組み合わせ
Claude API（分析・改善提案の生成）
  ↓
Slack / メール / スプレッドシートへ通知
```

ポイントは、SQLで「どの商品説明文バリアントがどれだけのセッション・購入数・購入率を生んだか」を集計し、その数値テーブルをそのままAIに渡すという設計です。AIはデータを読み取って「どちらが優位か」「なぜそう見えるか」「次にどう改善するか」を日本語で出力します。

担当者がBigQueryやGA4の専門知識を持っていなくても、出力されたレポートを読むだけで意思決定につなげられる点が、この仕組みの大きなメリットです。

---

## BigQueryでA/Bテスト結果を集計するSQL

GA4のBigQueryエクスポートテーブルを使って、商品ページごとのセッション数・購入数・購入率を集計するSQLです。

A/Bテストのバリアント情報は、GA4のカスタムイベントパラメータとして送信していることを前提とします。ここでは `ab_variant`（値例：`"A"` or `"B"`）というパラメータ名で計測している想定です。

```sql
-- GA4 BigQuery エクスポートテーブルを使ったA/Bテスト集計
-- テーブル名: `your_project.analytics_XXXXXXX.events_*`
-- 対象期間: 直近30日

WITH session_base AS (
  SELECT
    -- セッションIDはevent_paramsのUNNESTから取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- A/Bバリアントパラメータを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ab_variant'
    ) AS ab_variant,
    -- 商品ページのURLやIDを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_location'
    ) AS page_location,
    -- 流入元情報
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase', 'add_to_cart')
),

session_summary AS (
  SELECT
    CONCAT(user_pseudo_id, '_', CAST(session_id AS STRING)) AS unique_session,
    ab_variant,
    page_location,
    traffic_medium,
    traffic_source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart
  FROM session_base
  WHERE ab_variant IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
)

SELECT
  ab_variant,
  COUNT(DISTINCT unique_session)                          AS sessions,
  SUM(added_to_cart)                                     AS add_to_cart_count,
  SUM(purchased)                                         AS purchase_count,
  ROUND(SAFE_DIVIDE(SUM(added_to_cart), COUNT(DISTINCT unique_session)) * 100, 2) AS add_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(purchased), COUNT(DISTINCT unique_session)) * 100, 2)     AS purchase_rate
FROM session_summary
GROUP BY ab_variant
ORDER BY ab_variant;
```

:::message
`your_project.analytics_XXXXXXX` の部分はご自身のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。また `ab_variant` のパラメータ名はGA4の実装に合わせて変更が必要です。
:::

このSQLを実行すると、バリアントAとBそれぞれのセッション数・カート追加数・購入数・各レートが表形式で得られます。

---

## PythonでBigQueryを呼び出してAIへ連携する

次に、上記SQLをPythonから実行し、結果をAIに渡すスクリプトです。Claude APIを使って自動で改善提案を生成します。

```python
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
        model="claude-opus-4-5",
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
```

:::message
Claude APIのモデルIDやmax_tokensは用途に応じて調整してください。APIキーは環境変数 `ANTHROPIC_API_KEY` に設定するのが一般的です。
:::

このスクリプトを定期実行（例：毎週月曜朝にCloud Schedulerで動かす）することで、手作業なしにA/Bテストレポートと改善提案が手元に届く仕組みが完成します。

---

## AI出力の活用方法と注意点

AIが生成する改善提案は、あくまで「仮説の出発点」として活用することを推奨します。

**活用の流れ**

- AIの提案内容をライター・マーケターにSlackで共有
- 提案を参考に新バリアントの説明文案を作成
- 次のA/Bテストに投入してデータを積み上げる

このサイクルを繰り返すことで、説明文の品質が段階的に向上していきます。

**注意すべき点**

サンプル数が少ない（例：各バリアント100セッション未満）場合、購入率の差はランダムな揺れである可能性が高く、AIの分析も不確かなものになりがちです。BigQueryの集計結果にサンプル数を含めておき、プロンプト内でも「サンプル数が小さい場合はその旨を言及すること」と指示しておくのが効果的です。

また、流入元（`traffic_medium` / `traffic_source`）をセグメントに含めることで、「広告経由ではAが優位、自然検索ではBが優位」といったより細かい洞察を得られます。用途に応じてSQLのGROUP BY句に流入元を追加してみてください。

---

## まとめ

本記事では、GA4×BigQuery×AI（Claude API）を組み合わせて、EC商品説明文のA/Bテスト分析と改善提案を自動化する方法を紹介しました。

- **BigQuery**でGA4データを集計し、バリアントごとのKPIを数値化する
- **Python**でBigQueryの結果を取得し、AIへのプロンプトに組み込む
- **Claude API**がデータを読み取り、日本語で仮説・改善案を生成する
- 定期実行することで、毎週のレポート作業をほぼゼロにできる

まずは手元でSQLを動かして集計結果を確認し、その数値をClaude（またはお好みのAIサービス）のチャット画面に貼り付けて改善提案を試してみることをお勧めします。自動化は、手動で価値を確認してから進めると失敗が少なくなります。

データに基づいた説明文の改善サイクルを回し続けることが、中長期的なコンバージョン率の向上につながります。ぜひ自社のECサイトに合った形でカスタマイズしてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
