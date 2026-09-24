---
title: "AI.CLASSIFYでGROUP BYする — 分類軸を自然言語で定義する"
emoji: "🏷️"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第9回です。

前回（第8回）では `AI.IF` を使い、WHERE句に自然言語の条件を埋め込む「セマンティックフィルタ」を解説しました。今回は **`AI.CLASSIFY`** を取り上げます。

`AI.CLASSIFY` はテキストを指定したラベルのいずれかに分類する関数です。`AI.IF` が「この行は条件を満たすか／満たさないか」のBool判定だとすれば、`AI.CLASSIFY` は「この行はAかBかCか」の多クラス振り分けです。`GROUP BY` と組み合わせることで、事前に固定したラベル体系によるカテゴリ集計を自然言語で実現できます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.CLASSIFY とは

`AI.CLASSIFY` は、テキスト列と分類ラベルの候補リストを受け取り、最も適合するラベルを文字列で返す AI 関数です。

```sql
AI.CLASSIFY(
  MODEL model_name,
  text_expression,
  STRUCT(
    [label_1, label_2, ...] AS labels
    [, temperature AS temperature]
  )
)
```

| 引数 | 説明 |
|---|---|
| `model_name` | 使用するリモートモデルのリソース名 |
| `text_expression` | 分類対象のテキスト列 |
| `STRUCT(labels AS labels)` | ラベルの候補リスト（STRING の ARRAY） |

戻り値は STRING なので、`GROUP BY` の分類軸としてそのまま使えます。

---

## AI.IF との違い

| 観点 | AI.IF | AI.CLASSIFY |
|---|---|---|
| 返す値 | BOOL | STRING（ラベル） |
| 向いているケース | 「該当する／しない」の二値判定 | 複数ラベルへの振り分け |
| WHERE句での使用 | 直接使える | `= 'ラベル名'` で使える |
| GROUP BYでの使用 | 向かない | そのまま集計軸にできる |
| モデル呼び出し回数 | 判定1件につき1回 | 分類1件につき1回（多ラベルでも同じ） |

CASE式で `AI.IF` を並べると分岐の数だけモデルが呼ばれますが、`AI.CLASSIFY` はラベルが増えても呼び出しは1回で済みます。

---

## 基本的な使い方

### CS問い合わせをカテゴリ別に集計する

```sql
SELECT
  AI.CLASSIFY(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      ['返品・返金・交換', '配送遅延・紛失', '商品の不良・破損',
       '使い方・操作方法', 'キャンセル', 'その他'] AS labels,
      0.0 AS temperature
    )
  ) AS category,
  COUNT(*) AS cnt
FROM `your-project.your_dataset.raw_inquiries`
WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND inquiry_body IS NOT NULL
GROUP BY category
ORDER BY cnt DESC;
```

前段の `WHERE` で行数を絞ってから `AI.CLASSIFY` を呼んでいる点がポイントです。テーブル全件に対して呼ぶとトークンコストが跳ね上がります。

---

### GA4のサイト内検索キーワードを意図別に集計する

GA4 イベントデータと組み合わせた例です。`ga_session_id` は `UNNEST(event_params)` 経由で取得し、流入元は `collected_traffic_source.manual_medium` を使います。

```sql
WITH search_events AS (
  SELECT
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'search_term'
    ) AS search_term,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    event_date
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'search'
),
classified AS (
  SELECT
    search_term,
    medium,
    AI.CLASSIFY(
      MODEL `your-project.ai_lab.gemini_model`,
      search_term,
      STRUCT(
        ['商品名・型番検索', '価格・割引・セール', 'カテゴリ・用途探し',
         '比較・レビュー', 'サポート・使い方', 'その他'] AS labels,
        0.0 AS temperature
      )
    ) AS intent_category
  FROM search_events
  WHERE search_term IS NOT NULL
)
SELECT
  intent_category,
  medium,
  COUNT(*) AS search_count
FROM classified
GROUP BY intent_category, medium
ORDER BY search_count DESC;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## 商品レビューの感情傾向を分類する

ECサイトのレビューテキストを感情・トピック軸で分類し、商品カテゴリ別に集計する例です。

```sql
WITH reviews AS (
  SELECT
    product_id,
    category,
    review_text
  FROM `your-project.your_dataset.product_reviews`
  WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND review_text IS NOT NULL
),
classified AS (
  SELECT
    product_id,
    category,
    AI.CLASSIFY(
      MODEL `your-project.ai_lab.gemini_model`,
      review_text,
      STRUCT(
        ['品質・耐久性への満足', '価格・コスパへの満足',
         '配送・梱包への満足', '品質・耐久性への不満',
         '価格・コスパへの不満', '配送・梱包への不満', 'その他'] AS labels,
        0.0 AS temperature
      )
    ) AS review_topic
  FROM reviews
)
SELECT
  category,
  review_topic,
  COUNT(*) AS review_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY category), 1) AS pct
FROM classified
GROUP BY category, review_topic
ORDER BY category, review_count DESC;
```

`OVER (PARTITION BY category)` でカテゴリ内の割合も同時に計算しています。

---

## GROUP BY の前にマテリアライズする

`AI.CLASSIFY` の結果を複数のクエリで使い回す場合は、一度テーブルに保存してから集計します。これで同じテキストに対して何度もモデルを呼ぶ無駄を防げます。

```sql
-- Step 1: 分類結果を保存
CREATE OR REPLACE TABLE `your-project.your_dataset.classified_inquiries_20260923` AS
SELECT
  inquiry_id,
  received_at,
  inquiry_body,
  AI.CLASSIFY(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      ['返品・返金・交換', '配送遅延・紛失', '商品の不良・破損',
       '使い方・操作方法', 'キャンセル', 'その他'] AS labels,
      0.0 AS temperature
    )
  ) AS category
FROM `your-project.your_dataset.raw_inquiries`
WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND inquiry_body IS NOT NULL;

-- Step 2: 以降の集計は保存テーブルを参照
SELECT
  category,
  COUNT(*) AS cnt,
  AVG(response_time_hours) AS avg_response_h
FROM `your-project.your_dataset.classified_inquiries_20260923`
JOIN `your-project.your_dataset.inquiry_responses` USING (inquiry_id)
GROUP BY category
ORDER BY cnt DESC;
```

---

## ラベル設計のコツ

### ラベルは排他的かつ網羅的に

ラベル同士が重複していると分類が揺れます。また、どのラベルにも当てはまらないケースが多い場合は「その他」を必ず入れてください。

```sql
-- 悪い例（「品質不満」と「素材不満」が重なりやすい）
-- ['品質への不満', '素材への不満', '価格への不満']

-- 良い例（排他的でその他を含む）
-- ['品質・素材への不満', '価格・コスパへの不満', '配送への不満', 'その他']
```

### ラベルは日本語で明確に

ラベル名は分類の意図を表す短い文章にすると精度が上がります。単語1語よりも「〇〇への△△」のような形式が安定します。

### temperature は 0.0 に固定

分類タスクでは一貫性が重要です。`temperature: 0.0` で確定的な出力にしてください。

---

## `AI.CLASSIFY` と `AI.GENERATE` の使い分け

| 状況 | 推奨 |
|---|---|
| ラベルが事前に決まっている | `AI.CLASSIFY` |
| ラベルが決まっておらず、自由にカテゴリを付けてほしい | `AI.GENERATE` でラベルを生成 |
| 階層分類が必要（大分類→小分類） | `AI.CLASSIFY` を2段階で実行 |
| 複数ラベルを同時に付けたい（マルチラベル） | `AI.GENERATE_TABLE` でSTRUCT返し |

`AI.CLASSIFY` はラベルの候補リストが必要な代わりに、出力が必ずリスト内の文字列になるため後続の SQL で型エラーが起きません。

---

## コスト管理のポイント

- **行数を絞ってから呼ぶ**: WHERE句で日付やステータスを絞り、不要な行を除外する
- **結果をマテリアライズする**: 同じデータへの多重呼び出しを避ける
- **ラベルは簡潔に**: ラベルのテキストもトークンに含まれるため、長いラベルは避ける
- **スケジュール実行と組み合わせる**: 毎日の差分データだけを処理するバッチに組み込む

---

## まとめ

- `AI.CLASSIFY` はテキストを指定ラベルに振り分ける関数で、`GROUP BY` の分類軸に直接使える
- 多クラス分類を `AI.IF` のCASE式で書くより呼び出し回数が少なく済む
- GA4データとの組み合わせでは `UNNEST(event_params)` と `collected_traffic_source.manual_medium` を使う
- ラベルは排他的・網羅的に設計し、`temperature: 0.0` で出力を安定させる
- コスト対策は「前段フィルタで行数を絞る」「分類結果をマテリアライズして再利用する」が基本

次回（第10回）は `AI.SCORE` を取り上げます。自然言語で定義した基準で行をスコアリングし、`ORDER BY` で上位を取り出す方法を解説します。

---

## 参考

- [AI.CLASSIFY function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_classify)
- [Overview of AI functions | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/ai-functions-overview)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
