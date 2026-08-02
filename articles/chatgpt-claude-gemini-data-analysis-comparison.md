---
title: "ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した"
emoji: "⚖️"
type: "idea"
topics: ["ai","bigquery","googleanalytics","claude","gemini"]
published: false
---

## はじめに

「AIに分析を任せたいけど、どのAIが一番使えるのかわからない」——そんな疑問を持つEC事業者や担当者の方は多いのではないでしょうか。ChatGPT・Claude・Geminiはどれも「データ分析ができる」と言われていますが、実際に同じデータを渡したとき、返ってくる回答の質には大きな差があります。

本記事では、GA4のBigQueryエクスポートデータを題材にしながら、3つのAIに同じ質問・同じSQLクエリを渡して、それぞれの回答精度・説明のわかりやすさ・実務での使いやすさを比較しました。AIツール選びの参考にしていただければ幸いです。

なお、検証に使用したデータはGA4のBigQueryエクスポートテーブル（`events_*`）です。ECサイトの購買データや流入元データを使い、非エンジニアの方でも理解しやすい観点で評価しています。

---

## 検証方法と評価基準

今回の比較では、以下の3つの観点でAIを評価しました。

1. **SQLの正確性**: GA4 BigQueryの独自仕様（UNNEST構文など）に対応できているか
2. **説明のわかりやすさ**: 非エンジニアの担当者でも理解できる日本語で回答しているか
3. **実務提案力**: 数字の背後にある課題や改善策まで言及しているか

同一のプロンプトとして、次のような依頼を各AIに送りました。

> 「GA4のBigQueryエクスポートデータで、流入元別のセッション数と購入率を集計するSQLを書いてください。また、結果から読み取れる課題を教えてください」

---

## ChatGPTの回答傾向：汎用性は高いが GA4仕様に要注意

ChatGPT（GPT-4o）は全般的な説明力が高く、初心者にも理解しやすい丁寧な文章で回答してくれます。一方で、GA4のBigQuery独自仕様への対応に弱さが見られました。

たとえば、`ga_session_id`を`event_params`からUNNESTして取得する書き方や、流入元を`collected_traffic_source`から参照する点は、明示的に指示しないと一般的なSQLを返してしまうケースがありました。

以下は、正しいGA4 BigQuery向けSQLの例です（流入元別セッション数の集計）。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_xxxxxx.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

ChatGPTへの指示文に「GA4 BigQueryのUNNEST構文を使うこと」「流入元はcollected_traffic_sourceを使うこと」と明記したところ、正確なSQLを出力できるようになりました。プロンプト次第で品質が大きく変わる点は、使う側のスキルが問われます。

---

## Claudeの回答傾向：仕様理解と説明の深さが際立つ

Claude（Claude 3.5 Sonnet以降）は、GA4 BigQueryの仕様をあらかじめ理解していることが多く、UNNEST構文や`collected_traffic_source`を自然に使ったSQLを返してくれます。指示文が多少曖昧でも、GA4の文脈を読み取って適切に補完してくれる印象です。

また、数値の解釈と課題提案が具体的な点も特徴です。たとえば「オーガニック検索のセッションが多いのに購入率が低い場合、ランディングページのCTAや商品ページの構成を見直すことが考えられます」といった、次のアクションまで言及してくれます。

購入イベントを組み合わせた購入率の集計例は以下のとおりです。

```sql
WITH session_base AS (
  SELECT
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id') AS session_id,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase
  FROM
    `your_project.analytics_xxxxxx.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  GROUP BY
    medium, source, session_id
)
SELECT
  medium,
  source,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS purchase_rate_pct
FROM
  session_base
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

このクエリをClaudeに渡したところ、「メールマーケティング経由のセッションは購入率が高い傾向があります。リターゲティングや会員向けメルマガの強化が有効かもしれません」といった、実務につながる洞察を返してくれました。

:::message
上記SQLの`your_project.analytics_xxxxxx`の部分は、ご自身のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。
:::

---

## Geminiの回答傾向：Googleサービスとの親和性が強み

Gemini（Gemini 1.5 Pro以降）は、Google製品であるGA4やBigQueryとの親和性が高く、テーブルスキーマや仕様を正確に把握した回答が期待できます。特にLooker StudioやGoogle スプレッドシートとの連携を前提とした提案が得意です。

一方で、日本語での説明の細かさはClaudeに比べるとやや簡潔な印象でした。分析結果の解釈よりも、クエリ生成や手順の案内に強みがある印象です。

また、Google AI StudioやVertex AI上でBigQueryのデータに直接アクセスできる機能が整いつつあるため、「GCPを中心にデータ基盤を構築している」という方には、Geminiを中心としたワークフローが今後さらに使いやすくなると考えられます。

---

## 3AIの比較まとめ表

| 評価軸 | ChatGPT | Claude | Gemini |
|---|---|---|---|
| GA4 BigQuery仕様への対応 | プロンプト次第 | 自然に対応 | 対応良好 |
| 説明のわかりやすさ | 高い | 非常に高い | やや簡潔 |
| 実務提案・改善示唆 | 普通 | 詳細 | 手順重視 |
| Google連携 | 標準 | 標準 | 強み |
| 非エンジニア向きか | 〇 | ◎ | 〇 |

どのAIが「優れている」かは一概には言えません。目的や使い方によって、最適なツールは変わります。

---

## まとめと次のアクション

今回の比較から言えることは、「AIに丸投げするのではなく、AIを正しく使う側の設計が重要」だということです。

- **ChatGPT**: プロンプトの設計に慣れている方、汎用的なデータ分析や文章生成と組み合わせたい方に向いています
- **Claude**: GA4やBigQueryを使ったデータ分析で、非エンジニアでもわかる説明や改善提案が欲しい方におすすめです
- **Gemini**: GCP・Looker Studioとの連携を重視し、Googleのエコシステム内で完結させたい方に向いています

まずは自社のGA4データをBigQueryにエクスポートした上で、上記のSQLを試してみてください。「どの流入元からの訪問者が購入につながっているか」が見えてくるだけで、広告予算の配分やコンテンツ戦略の判断材料が大きく変わります。

分析の入口として、AIはとても有効なパートナーです。ぜひ実際に触れながら、自社に合ったツールを見つけていただければと思います。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
