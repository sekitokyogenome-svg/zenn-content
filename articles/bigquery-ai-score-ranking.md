---
title: "AI.SCOREでORDER BYする — 自然言語の基準でランキングを作る"
emoji: "📊"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第10回です。

前回（第9回）では `AI.CLASSIFY` を使い、テキストを指定したラベルに振り分けて `GROUP BY` で集計する方法を解説しました。今回は **`AI.SCORE`** を取り上げます。

`AI.SCORE` はテキストが指定した基準にどれだけ合致するかを数値（FLOAT64）で返す AI 関数です。`ORDER BY` に組み合わせることで「自然言語で定義した基準に従って上位N件を取り出す」という操作をSQLだけで実現できます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.SCORE とは

`AI.SCORE` はテキスト列と採点基準（criteria）を受け取り、0〜1の範囲のスコアを返す AI 関数です。

```sql
AI.SCORE(
  MODEL model_name,
  text_expression,
  STRUCT(criteria AS criteria [, temperature AS temperature])
)
```

| 引数 | 説明 |
|---|---|
| `model_name` | 使用するリモートモデルのリソース名 |
| `text_expression` | スコアリング対象のテキスト列 |
| `STRUCT(criteria AS criteria)` | 採点基準を記述した自然言語の文字列 |

戻り値は FLOAT64 なので、`ORDER BY score DESC` で上位N件を取り出せます。

---

## AI.CLASSIFY との違い

| 観点 | AI.CLASSIFY | AI.SCORE |
|---|---|---|
| 返す値 | STRING（ラベル） | FLOAT64（スコア） |
| 向いているケース | 離散的なカテゴリに振り分ける | 連続的な関連度・優先度でソートする |
| ORDER BYでの活用 | ラベルでソートは可能 | スコア値で自然なランキングを作れる |
| 上位N件の抽出 | 特定ラベルでWHERE絞りが必要 | `ORDER BY score DESC LIMIT N` で取れる |

「Aか、Bか、Cか」の振り分けには `AI.CLASSIFY`、「どれだけAらしいか」の度合いを見るには `AI.SCORE` が適しています。

---

## 基本的な使い方

### CS問い合わせを優先度でランキングする

対応の緊急度が高い問い合わせを上位に並べる例です。

```sql
SELECT
  inquiry_id,
  received_at,
  inquiry_body,
  AI.SCORE(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      '顧客に与える影響が大きく、早急な対応が必要な問い合わせである。返金・法的クレーム・大量注文のキャンセルなどを高く評価する。' AS criteria,
      0.0 AS temperature
    )
  ) AS urgency_score
FROM `your-project.your_dataset.raw_inquiries`
WHERE
  DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND status = 'open'
  AND inquiry_body IS NOT NULL
ORDER BY urgency_score DESC
LIMIT 20;
```

---

### GA4のサイト内検索キーワードを購買関連度でランキングする

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
    collected_traffic_source.manual_medium AS medium
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'search'
),
aggregated AS (
  SELECT
    search_term,
    COUNT(*) AS search_count
  FROM search_events
  WHERE search_term IS NOT NULL
  GROUP BY search_term
  HAVING COUNT(*) >= 5
)
SELECT
  search_term,
  search_count,
  AI.SCORE(
    MODEL `your-project.ai_lab.gemini_model`,
    search_term,
    STRUCT(
      '購入意欲が高く、今すぐ商品を買いたい、または特定商品の購入を強く検討していることを示す検索ワードである。商品名・型番・「購入」「注文」「送料」などのキーワードを含む場合に高いスコアを付ける。' AS criteria,
      0.0 AS temperature
    )
  ) AS purchase_intent_score
FROM aggregated
ORDER BY purchase_intent_score DESC
LIMIT 30;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## 商品レビューを有用度でランキングする

他のユーザーの購買判断に役立つレビューを上位に表示するための採点例です。

```sql
WITH recent_reviews AS (
  SELECT
    review_id,
    product_id,
    review_text,
    rating
  FROM `your-project.your_dataset.product_reviews`
  WHERE
    DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND review_text IS NOT NULL
    AND LENGTH(review_text) >= 20
)
SELECT
  review_id,
  product_id,
  rating,
  review_text,
  AI.SCORE(
    MODEL `your-project.ai_lab.gemini_model`,
    review_text,
    STRUCT(
      '商品の具体的な使用感・品質・サイズ感・耐久性など、購入判断に役立つ詳細な情報が含まれており、他のユーザーにとって参考になるレビューである。' AS criteria,
      0.0 AS temperature
    )
  ) AS usefulness_score
FROM recent_reviews
ORDER BY usefulness_score DESC
LIMIT 50;
```

---

## スコアを閾値で絞り込む

`ORDER BY` だけでなく、`WHERE` 句でスコアの閾値を設けることもできます。

```sql
WITH scored AS (
  SELECT
    inquiry_id,
    inquiry_body,
    AI.SCORE(
      MODEL `your-project.ai_lab.gemini_model`,
      inquiry_body,
      STRUCT(
        '返品・返金・交換に強く関連する問い合わせである' AS criteria,
        0.0 AS temperature
      )
    ) AS return_score
  FROM `your-project.your_dataset.raw_inquiries`
  WHERE
    DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND inquiry_body IS NOT NULL
)
SELECT
  inquiry_id,
  inquiry_body,
  return_score
FROM scored
WHERE return_score >= 0.7
ORDER BY return_score DESC;
```

ただし、スコアの絶対値はモデルやプロンプトによって変わるため、閾値は実データで調整してください。まず `ORDER BY` で分布を確認し、ビジネス的に「対応が必要」とみなしたい件数に合わせて閾値を決めるのが実用的です。

---

## 複数のスコアを組み合わせる

2つの基準で採点して合計スコアで順位付けする例です。

```sql
WITH scored AS (
  SELECT
    product_id,
    product_name,
    description,
    AI.SCORE(
      MODEL `your-project.ai_lab.gemini_model`,
      description,
      STRUCT(
        '商品説明文が具体的で購入意欲を高める魅力的な内容である' AS criteria,
        0.0 AS temperature
      )
    ) AS appeal_score,
    AI.SCORE(
      MODEL `your-project.ai_lab.gemini_model`,
      description,
      STRUCT(
        '商品説明文にSEO対策上有効なキーワードが自然な形で含まれている' AS criteria,
        0.0 AS temperature
      )
    ) AS seo_score
  FROM `your-project.your_dataset.products`
  WHERE
    is_active = TRUE
    AND description IS NOT NULL
)
SELECT
  product_id,
  product_name,
  appeal_score,
  seo_score,
  (appeal_score + seo_score) / 2 AS combined_score
FROM scored
ORDER BY combined_score ASC
LIMIT 20;
```

`combined_score` が低い商品が「説明文の改善余地が大きいもの」として浮かび上がります。

---

## コスト管理のポイント

### 集約してからスコアリングする

個別行ではなく、集計後のユニークな値に対してスコアリングすると呼び出し回数を大幅に削減できます。

```sql
-- 悪い例：全イベント行（数万行）に対してスコアリング
SELECT AI.SCORE(...) FROM events_table WHERE ...;

-- 良い例：ユニーク検索ワードのみにスコアリング（数百行に圧縮）
WITH agg AS (
  SELECT search_term, COUNT(*) AS cnt
  FROM events_table WHERE ...
  GROUP BY search_term
  HAVING cnt >= 5
)
SELECT *, AI.SCORE(..., search_term, ...) FROM agg;
```

### 結果をマテリアライズして再利用する

スコアリング結果を `CREATE TABLE AS SELECT` で保存しておけば、同じデータに対して何度もモデルを呼ぶ必要がなくなります。

### criteria の文は簡潔に

criteria のテキストが長くなるほどトークンが増えます。50〜100文字程度でポイントを絞って書くと安定します。

---

## まとめ

- `AI.SCORE` はテキストの基準合致度をFLOAT64で返し、`ORDER BY` に使える
- 「AかBかCか」の離散分類には `AI.CLASSIFY`、「どれだけAらしいか」の連続スコアには `AI.SCORE`
- GA4データとの組み合わせでは `UNNEST(event_params)` と `collected_traffic_source.manual_medium` を使う
- 閾値フィルタよりもまず `ORDER BY` で分布を確認してからビジネス要件に合わせて調整する
- コスト対策は「集約してから呼ぶ」「結果をマテリアライズする」の2点が基本

次回（第11回）は `AI.EMBED` / `AI.GENERATE_EMBEDDING` を取り上げます。テキストをベクトルに変換し、その後の類似度検索や分類に活用する基礎を解説します。

---

## 参考

- [AI.SCORE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_score)
- [Overview of AI functions | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/ai-functions-overview)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
