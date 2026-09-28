---
title: "BigQueryベクトル検索とVECTOR INDEX — 類似検索を実装する"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "vectorsearch", "sql"]
published: true
---

## はじめに

シリーズ第12回です。

前回（第11回）では `AI.EMBED` / `AI.GENERATE_EMBEDDING` でテキストをベクトルに変換する方法を解説しました。今回は **`VECTOR_SEARCH`** と **`VECTOR INDEX`** を深掘りします。

ベクトルを作るだけでは「類似度検索」は動きません。検索の精度と速度を両立するには、インデックスのパラメータ設計と `VECTOR_SEARCH` の引数をセットで理解する必要があります。本記事では EC サイトの類似商品検索を題材に、本番運用を意識した実装手順を解説します。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## VECTOR_INDEX とは

`VECTOR INDEX` は、`ARRAY<FLOAT64>` 型のベクトル列に対して近似最近傍検索（ANN: Approximate Nearest Neighbor）を高速化するインデックスです。

インデックスなしの `VECTOR_SEARCH` は全件スキャン（正確な最近傍検索）を行うため、行数が増えるほどクエリコストが線形に伸びます。`VECTOR INDEX` を作成すると ANN アルゴリズムが使われ、精度をわずかに犠牲にしながら大幅な高速化が実現します。

| 方式 | 精度 | 速度 | 向いているケース |
|---|---|---|---|
| フルスキャン（インデックスなし） | 完全一致 | 遅い | 数万行以下の小規模テーブル |
| IVF（インデックスあり） | 近似 | 速い | 数十万行以上の本番運用 |

---

## VECTOR INDEX の作成

```sql
CREATE OR REPLACE VECTOR INDEX product_embedding_idx
ON `your-project.your_dataset.product_embeddings`(embedding)
OPTIONS(
  index_type = 'IVF',
  distance_type = 'COSINE',
  ivf_options = '{"num_lists": 500}'
);
```

### 主要オプション

| オプション | 説明 |
|---|---|
| `index_type` | `IVF`（反転ファイルインデックス）のみ対応 |
| `distance_type` | `COSINE`（コサイン距離）または `EUCLIDEAN`（ユークリッド距離） |
| `ivf_options.num_lists` | クラスタ数。行数の平方根を目安に設定する |

`num_lists` はインデックスの粒度を決めるパラメータです。行数が 100 万行なら `num_lists = 1000` 前後が目安です。値を大きくすると検索精度は上がりますが、インデックスの構築時間とクエリ時のメモリ使用量が増加します。

---

## インデックス構築状況の確認

インデックスは非同期で構築されます。`coverage_percentage` が 100 に達するまで ANN は使われません。

```sql
SELECT
  index_name,
  coverage_percentage,
  last_refresh_time,
  unindexed_row_count,
  total_logical_bytes
FROM `your-project.your_dataset.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE table_name = 'product_embeddings';
```

`coverage_percentage` が 100 未満の間は、`VECTOR_SEARCH` がフルスキャンにフォールバックします。大規模テーブルへの初回インデックス適用は時間を要するため、深夜バッチで実行することを推奨します。

---

## VECTOR_SEARCH の構文と引数

```sql
VECTOR_SEARCH(
  TABLE base_table,
  column_to_search,
  TABLE query_table,
  [top_k => integer],
  [distance_type => 'COSINE' | 'EUCLIDEAN'],
  [options => json_string]
)
```

### 代表的な引数

| 引数 | 説明 |
|---|---|
| `top_k` | 類似上位 N 件を返す（デフォルト 10） |
| `distance_type` | インデックス作成時と同じ距離関数を指定する |
| `options.fraction_lists_to_search` | スキャンするクラスタ数の比率（0.0〜1.0） |
| `options.use_brute_force` | `true` にすると ANN を使わず全件スキャン |

`fraction_lists_to_search` を大きくすると精度は上がりますが速度が落ちます。デフォルト（`null`）では BigQuery が自動調整します。本番環境では最初にデフォルトで動かし、精度不足と感じたときに 0.1〜0.2 程度に引き上げると調整しやすいです。

---

## 実装例：EC 商品の類似検索

### Step 1: ベクトルテーブルの準備

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.product_embeddings` AS
SELECT
  product_id,
  product_name,
  category,
  price,
  CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')) AS combined_text,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')),
    STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE is_active = TRUE
  AND description IS NOT NULL;
```

### Step 2: VECTOR INDEX の作成

```sql
CREATE OR REPLACE VECTOR INDEX product_embedding_idx
ON `your-project.your_dataset.product_embeddings`(embedding)
OPTIONS(
  index_type = 'IVF',
  distance_type = 'COSINE',
  ivf_options = '{"num_lists": 500}'
);
```

### Step 3: 類似商品の検索

ユーザーがカートに入れた商品に近い商品を上位5件返すクエリです。

```sql
SELECT
  query.product_id        AS source_product_id,
  query.product_name      AS source_product_name,
  result.product_id       AS similar_product_id,
  result.product_name     AS similar_product_name,
  result.category         AS similar_category,
  result.price            AS similar_price,
  result.distance
FROM
  VECTOR_SEARCH(
    TABLE `your-project.your_dataset.product_embeddings`,
    'embedding',
    (
      SELECT
        product_id,
        product_name,
        embedding
      FROM `your-project.your_dataset.product_embeddings`
      WHERE product_id IN ('P001', 'P002', 'P003')
    ),
    top_k         => 6,
    distance_type => 'COSINE'
  )
WHERE result.product_id != query.product_id  -- 自分自身を除外
ORDER BY query.product_id, result.distance
LIMIT 30;
```

`top_k = 6` にして自分自身を除くと実質5件が返ります。

---

## GA4 データと組み合わせた類似検索

GA4 のサイト内検索キーワードから、意味的に近い商品をサジェストする例です。`ga_session_id` は `UNNEST(event_params)` で取り出し、流入元は `collected_traffic_source.manual_medium` を使います。

```sql
WITH recent_searches AS (
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
    COUNT(*) AS search_count
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'search'
  GROUP BY 1, 2, 3
  HAVING search_term IS NOT NULL
),
query_embeddings AS (
  SELECT
    search_term,
    SUM(search_count) AS total_count,
    AI.EMBED(
      MODEL `your-project.ai_lab.embedding_model`,
      search_term,
      STRUCT('RETRIEVAL_QUERY' AS task_type)
    ) AS embedding
  FROM recent_searches
  GROUP BY search_term
)
SELECT
  q.search_term,
  q.total_count,
  r.product_name,
  r.category,
  r.distance
FROM
  VECTOR_SEARCH(
    TABLE `your-project.your_dataset.product_embeddings`,
    'embedding',
    TABLE query_embeddings,
    top_k         => 3,
    distance_type => 'COSINE'
  )
ORDER BY q.total_count DESC, r.distance;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## インデックスの更新戦略

商品データは日々更新されます。ベクトルテーブルの更新方法を整理します。

### 差分追加（INSERT）

新規・更新商品だけをベクトル化して追記する方式です。

```sql
INSERT INTO `your-project.your_dataset.product_embeddings`
SELECT
  product_id,
  product_name,
  category,
  price,
  CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')) AS combined_text,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model`,
    CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')),
    STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE updated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND is_active = TRUE
  AND description IS NOT NULL;
```

INSERT は `VECTOR INDEX` のカバレッジを自動更新します。

### 全件再構築（CTAS）

商品数が少ない（数万件以下）か、ベクトルモデルを入れ替えた場合は `CREATE OR REPLACE TABLE` で全件作り直します。モデルバージョンアップ後は全件再構築が必要です。

---

## 距離タイプの選び方

| 距離タイプ | 特徴 | 推奨ケース |
|---|---|---|
| `COSINE` | ベクトルの向きの類似度（長さ非依存） | テキスト類似度検索 |
| `EUCLIDEAN` | ベクトル空間上の直線距離 | 絶対値の差を重視する場合 |

テキストの意味的な類似度を測る用途では `COSINE` が標準です。インデックス作成時と `VECTOR_SEARCH` 呼び出し時の `distance_type` は必ず一致させてください。一致しない場合、ANN が使われずフルスキャンになります。

---

## コスト管理のポイント

### インデックスの維持コスト

`VECTOR INDEX` 自体は追加のストレージを消費します。`INFORMATION_SCHEMA.VECTOR_INDEXES` の `total_logical_bytes` でサイズを把握してください。商品数が少ないテーブルではインデックスのオーバーヘッドが相対的に大きいため、10 万行未満の場合はフルスキャンの方が安くなるケースもあります。

### クエリのコスト削減

```sql
-- 悪い例：毎回クエリ側ベクトルを再生成する
SELECT ...
FROM VECTOR_SEARCH(
  TABLE product_embeddings,
  'embedding',
  (SELECT AI.EMBED(..., user_input, ...) AS embedding),
  top_k => 5
);

-- 良い例：クエリ側ベクトルを事前に保存してから検索する
CREATE TEMP TABLE query_vec AS
SELECT AI.EMBED(..., user_input, ...) AS embedding, user_input;

SELECT ...
FROM VECTOR_SEARCH(
  TABLE product_embeddings,
  'embedding',
  TABLE query_vec,
  top_k => 5
);
```

---

## まとめ

- `VECTOR INDEX` は IVF 方式で、`num_lists` を行数の平方根を目安に設定する
- `coverage_percentage` が 100 になるまで ANN は有効にならない
- `VECTOR_SEARCH` の `distance_type` はインデックスと揃える
- `fraction_lists_to_search` でリコールと速度のトレードオフを調整できる
- テキスト類似検索には `COSINE`、モデルアップデート後は全件再構築が必要
- 差分 INSERT でインデックスカバレッジは自動更新される

次回（第13回）は `bigquery-autonomous-embedding-pipeline` として、ベクトルインデックスを自律的に同期し続けるパイプラインの設計を解説します。

---

## 参考

- [Create vector indexes | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/vector-index)
- [VECTOR_SEARCH function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/vector-functions#vector_search)
- [About vector index options | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/vector-index#ivf_options)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
