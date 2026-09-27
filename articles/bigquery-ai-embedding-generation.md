---
title: "AI.EMBED / AI.GENERATE_EMBEDDINGでベクトルを作る"
emoji: "🔢"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第11回です。

前回（第10回）では `AI.SCORE` を使い、自然言語の基準でテキストにスコアを付けて `ORDER BY` でランキングを作る方法を解説しました。今回は **`AI.EMBED`** / **`AI.GENERATE_EMBEDDING`** を取り上げます。

これらの関数はテキストを高次元のベクトル（数値の配列）に変換します。ベクトルに変換することで「意味の近さ」を数値で表現できるようになり、類似商品の推薦やユーザーレビューのクラスタリングといった処理をSQLの中で完結させられます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.EMBED と AI.GENERATE_EMBEDDING の違い

2026年現在、BigQuery でテキストをベクトル化する関数は2系統あります。

| 関数 | 系統 | 状態 |
|---|---|---|
| `AI.EMBED` | AI.* 関数ファミリー（新系統） | 推奨・使用中 |
| `AI.GENERATE_EMBEDDING` | ML.* 関数ファミリー（旧系統） | 後方互換で維持 |

新規実装では `AI.EMBED` を使うのが推奨です。既存の `ML.GENERATE_EMBEDDING` を使ったパイプラインは `AI.GENERATE_EMBEDDING` を経由して継続動作しますが、長期的には `AI.EMBED` へ移行することを前提に設計してください。

---

## AI.EMBED の構文

```sql
AI.EMBED(
  MODEL model_name,
  text_expression
  [, STRUCT(task_type AS task_type)]
)
```

| 引数 | 説明 |
|---|---|
| `model_name` | 埋め込みモデルのリソース名（text-embedding-005 など） |
| `text_expression` | ベクトル化するテキスト列 |
| `STRUCT(task_type AS task_type)` | タスク種別（省略可） |

戻り値は `ARRAY<FLOAT64>` です。この配列が後続の `VECTOR_SEARCH` や `VECTOR_INDEX` に渡す「ベクトル」になります。

---

## task_type の選び方

`task_type` を指定するとモデルの出力が対象タスクに最適化されます。

| task_type 値 | 向いているケース |
|---|---|
| `RETRIEVAL_DOCUMENT` | 検索対象として登録する文書側 |
| `RETRIEVAL_QUERY` | 検索クエリ側（ユーザーの問い合わせ文） |
| `SEMANTIC_SIMILARITY` | 2つのテキストの意味的類似度を測る |
| `CLASSIFICATION` | テキストを分類モデルの入力に使う |
| `CLUSTERING` | テキストのクラスタリングに使う |

検索用途では文書側を `RETRIEVAL_DOCUMENT`、クエリ側を `RETRIEVAL_QUERY` にするとベクトルの最適化が変わり、検索精度が上がります。

---

## 基本的な使い方

### 商品説明文をベクトル化して保存する

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.product_embeddings` AS
SELECT
  product_id,
  product_name,
  description,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    description,
    STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE
  is_active = TRUE
  AND description IS NOT NULL;
```

実行後、`embedding` 列に `ARRAY<FLOAT64>` が格納されます。この結果テーブルを `VECTOR_INDEX` の対象にすることで高速な近似最近傍検索（ANN）が可能になります。

---

### GA4のサイト内検索キーワードをベクトル化する

GA4 イベントデータから検索キーワードを取り出してベクトル化する例です。`ga_session_id` は `UNNEST(event_params)` 経由で取得し、流入元は `collected_traffic_source.manual_medium` を使います。

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
unique_terms AS (
  SELECT
    search_term,
    COUNT(*) AS search_count
  FROM search_events
  WHERE search_term IS NOT NULL
  GROUP BY search_term
  HAVING COUNT(*) >= 3
)
SELECT
  search_term,
  search_count,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    search_term,
    STRUCT('RETRIEVAL_QUERY' AS task_type)
  ) AS embedding
FROM unique_terms;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## VECTOR_SEARCH で類似テキストを検索する

ベクトルを保存したら `VECTOR_SEARCH` 関数で最近傍を検索できます。

```sql
SELECT
  query.search_term,
  result.product_name,
  result.description,
  result.distance
FROM
  VECTOR_SEARCH(
    TABLE `your-project.your_dataset.product_embeddings`,
    'embedding',
    (
      SELECT
        search_term,
        AI.EMBED(
          MODEL `your-project.ai_lab.embedding_model`,
          search_term,
          STRUCT('RETRIEVAL_QUERY' AS task_type)
        ) AS embedding
      FROM UNNEST(['防水スニーカー', 'ギフト用タオル']) AS search_term
    ),
    top_k => 3,
    distance_type => 'COSINE'
  )
ORDER BY query.search_term, result.distance;
```

`top_k` は取得する上位件数、`distance_type` はコサイン距離（COSINE）またはユークリッド距離（EUCLIDEAN）を指定します。コサイン距離は値が小さいほど類似度が高い（0が完全一致、1が無関係）ことを表します。

---

## AI.GENERATE_EMBEDDING との互換性

既存のパイプラインで `AI.GENERATE_EMBEDDING` を使っている場合の互換確認です。

```sql
-- 旧構文（後方互換で動作）
SELECT
  product_id,
  AI.GENERATE_EMBEDDING(
    MODEL `your-project.ai_lab.embedding_model`,
    description
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE is_active = TRUE;
```

旧構文でも動作しますが、`task_type` の指定方法など引数の細部に差異があります。新規開発は `AI.EMBED` で書いてください。

---

## VECTOR_INDEX の作成

ベクトル列を対象に `VECTOR_INDEX` を作成すると、全件スキャンより高速な近似最近傍検索（ANN）が使えます。

```sql
CREATE OR REPLACE VECTOR INDEX product_embedding_idx
ON `your-project.your_dataset.product_embeddings`(embedding)
OPTIONS(
  index_type = 'IVF',
  distance_type = 'COSINE',
  ivf_options = '{"num_lists": 100}'
);
```

インデックスは非同期で構築されます。構築状況は `INFORMATION_SCHEMA.VECTOR_INDEXES` で確認できます。

```sql
SELECT
  index_name,
  coverage_percentage,
  last_refresh_time
FROM `your-project.your_dataset.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE table_name = 'product_embeddings';
```

`coverage_percentage` が 100 に近づくとインデックスが有効になります。

---

## EC用ユースケース

### 類似商品レコメンドのベクトルテーブルを作る

```sql
-- カテゴリ・商品名・説明文を結合してベクトル化
CREATE OR REPLACE TABLE `your-project.your_dataset.product_embeddings` AS
SELECT
  product_id,
  CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')) AS combined_text,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')),
    STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE is_active = TRUE;
```

複数のテキスト列を結合してベクトル化すると、商品の文脈情報を一本化したベクトルを作れます。

### カスタマーレビューをクラスタリング用にベクトル化する

```sql
SELECT
  review_id,
  product_id,
  review_text,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    review_text,
    STRUCT('CLUSTERING' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.product_reviews`
WHERE
  DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND review_text IS NOT NULL
  AND LENGTH(review_text) >= 10;
```

このベクトルを外部のクラスタリングライブラリ（Python scikit-learn など）に渡すか、BigQuery ML の `CREATE MODEL ... OPTIONS(model_type = 'KMEANS')` に入力として使えます。

---

## コスト管理のポイント

### ユニーク値に絞ってからベクトル化する

同じテキストが複数行に出現する場合は重複を排除してから `AI.EMBED` を呼びます。

```sql
-- 悪い例：全レビュー行（10万行）をベクトル化
SELECT review_id, AI.EMBED(..., review_text, ...) FROM reviews;

-- 良い例：同一テキストのユニーク分だけベクトル化して結合
WITH unique_texts AS (
  SELECT DISTINCT review_text FROM reviews WHERE review_text IS NOT NULL
),
embedded AS (
  SELECT review_text, AI.EMBED(..., review_text, ...) AS embedding
  FROM unique_texts
)
SELECT r.review_id, e.embedding
FROM reviews r
JOIN embedded e USING (review_text);
```

### 差分だけを更新する

毎日全商品を再ベクトル化するのではなく、前回以降に更新・追加された行だけを処理します。

```sql
INSERT INTO `your-project.your_dataset.product_embeddings`
SELECT
  product_id,
  description,
  AI.EMBED(..., description, ...) AS embedding
FROM `your-project.your_dataset.products`
WHERE updated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND description IS NOT NULL;
```

### ベクトルを再利用する

一度作ったベクトルは `CREATE TABLE AS SELECT` で保存し、検索のたびに再生成しないようにします。文書側のベクトルは内容が変わらない限り使い回せます。

---

## まとめ

- `AI.EMBED` は新系統のベクトル化関数で、戻り値は `ARRAY<FLOAT64>`
- `AI.GENERATE_EMBEDDING` は後方互換で動作するが、新規実装は `AI.EMBED` を推奨
- `task_type` を用途に合わせて指定すると検索・分類・クラスタリングの精度が上がる
- `VECTOR_SEARCH` で意味的な類似テキスト検索が可能になり、商品レコメンドや類似レビュー検索に使える
- `VECTOR_INDEX` を作成すると大規模テーブルでも高速な近似最近傍検索ができる
- コスト対策は「ユニーク値に絞る」「差分だけ更新」「結果を保存して再利用」の3点が基本

次回（第12回）は `VECTOR_INDEX` と `VECTOR_SEARCH` をより深掘りします。インデックスパラメータの調整方法と、ECサイトの類似検索を本番運用する際の設計パターンを解説します。

---

## 参考

- [AI.EMBED function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_embed)
- [VECTOR_SEARCH function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/vector-functions#vector_search)
- [Create vector indexes | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/vector-index)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
