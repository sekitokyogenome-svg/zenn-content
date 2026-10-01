---
title: "自律型エンベディング生成でベクトルインデックスを自動同期する"
emoji: "🔄"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "vectorsearch", "embedding"]
published: true
---

## はじめに

シリーズ第13回です。

前回（第12回）では `VECTOR_SEARCH` と `VECTOR INDEX` を使った類似検索の実装を解説しました。今回は **ベクトルインデックスを自動で同期し続けるパイプライン** の設計に踏み込みます。

商品データは毎日更新されます。手動で `AI.EMBED` を実行し直すのでは運用が回りません。新規追加・更新・削除されたレコードを検知し、差分だけエンベディングを再生成してベクトルテーブルに反映する仕組みを作ります。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## なぜ「自律型」が必要か

手動でベクトルを更新すると、次の問題が起きます。

- 商品追加のたびに担当者がクエリを実行する必要がある
- 更新漏れが発生すると検索精度が劣化する
- モデルの切り替え時に全件再構築のタイミングを逃す

**自律型パイプライン** とは、更新検知→差分エンベディング生成→インデックス同期を BigQuery のスケジュール機能と Cloud Scheduler だけで完結させる設計です。

---

## パイプライン全体像

```
[products テーブル]
       |
       | 更新検知（updated_at ベース）
       ↓
[差分エンベディング生成（AI.EMBED）]
       |
       | INSERT / DELETE
       ↓
[product_embeddings テーブル]
       |
       | 自動カバレッジ更新
       ↓
[VECTOR INDEX（自動同期）]
       |
       ↓
[VECTOR_SEARCH クエリ]
```

BigQuery の `VECTOR INDEX` は、テーブルへの INSERT / DELETE を検知してカバレッジを自動更新します。パイプラインで行うのは「正しい差分をテーブルに書き込む」ことだけです。

---

## Step 1: ウォーターマークテーブルの作成

どこまで処理したかを記録するテーブルを作成します。

```sql
CREATE TABLE IF NOT EXISTS `your-project.your_dataset.embedding_pipeline_watermark` (
  pipeline_name   STRING NOT NULL,
  last_processed  TIMESTAMP NOT NULL
)
OPTIONS (
  description = 'エンベディングパイプラインの最終処理タイムスタンプ'
);

-- 初期値の投入
INSERT INTO `your-project.your_dataset.embedding_pipeline_watermark`
  (pipeline_name, last_processed)
VALUES
  ('product_embeddings', TIMESTAMP('2024-01-01 00:00:00'));
```

---

## Step 2: 差分エンベディング生成スクリプト

スケジュール実行する SQL です。ウォーターマークより新しいレコードだけを対象にします。

```sql
DECLARE last_ts TIMESTAMP;
DECLARE current_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- ウォーターマーク取得
SET last_ts = (
  SELECT last_processed
  FROM `your-project.your_dataset.embedding_pipeline_watermark`
  WHERE pipeline_name = 'product_embeddings'
);

-- 削除済み商品をベクトルテーブルから除去
DELETE FROM `your-project.your_dataset.product_embeddings` AS e
WHERE NOT EXISTS (
  SELECT 1
  FROM `your-project.your_dataset.products` AS p
  WHERE p.product_id = e.product_id
    AND p.is_active = TRUE
);

-- 差分レコードのエンベディングを生成して追記
MERGE `your-project.your_dataset.product_embeddings` AS target
USING (
  SELECT
    product_id,
    product_name,
    category,
    price,
    updated_at,
    CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')) AS combined_text,
    AI.EMBED(
      MODEL `your-project.ai_lab.embedding_model`,
      CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')),
      STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
    ) AS embedding
  FROM `your-project.your_dataset.products`
  WHERE updated_at > last_ts
    AND is_active = TRUE
    AND description IS NOT NULL
) AS source
ON target.product_id = source.product_id
WHEN MATCHED THEN
  UPDATE SET
    product_name  = source.product_name,
    category      = source.category,
    price         = source.price,
    combined_text = source.combined_text,
    embedding     = source.embedding,
    updated_at    = source.updated_at
WHEN NOT MATCHED THEN
  INSERT (product_id, product_name, category, price, combined_text, embedding, updated_at)
  VALUES (source.product_id, source.product_name, source.category, source.price,
          source.combined_text, source.embedding, source.updated_at);

-- ウォーターマークを更新
UPDATE `your-project.your_dataset.embedding_pipeline_watermark`
SET last_processed = current_ts
WHERE pipeline_name = 'product_embeddings';
```

:::message
`MERGE` 文は BigQuery のスケジュールクエリとして登録できます。DML の課題はコストです。処理行数が多い場合は `INSERT INTO ... SELECT` に分割し、`DELETE` と `INSERT` を別ステップで実行すると BigQuery のスロット利用が平準化されます。
:::

---

## Step 3: スケジュールクエリの設定

BigQuery コンソールからスケジュールクエリを登録します。

```
スケジュール: 毎日 02:00 JST（= 17:00 UTC）
タイムゾーン: Asia/Tokyo
リトライ: 3回（エラー時）
通知: Cloud Pub/Sub または メール
```

コマンドラインから登録する場合は次のようになります。

```bash
bq query \
  --use_legacy_sql=false \
  --schedule="every 24 hours" \
  --display_name="product_embeddings_daily_sync" \
  --location=asia-northeast1 \
  "$(cat embedding_pipeline.sql)"
```

---

## Step 4: モデルバージョン更新時の全件再構築

エンベディングモデルのバージョンが上がった場合、過去のベクトルと新しいベクトルは空間が異なるため混在できません。全件再構築が必要です。

```sql
-- 1. 全件再構築（新テーブルに書き出す）
CREATE OR REPLACE TABLE `your-project.your_dataset.product_embeddings_new` AS
SELECT
  product_id,
  product_name,
  category,
  price,
  updated_at,
  CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')) AS combined_text,
  AI.EMBED(
    MODEL `your-project.ai_lab.embedding_model_v2`,  -- 新モデル
    CONCAT(category, ' / ', product_name, ' : ', COALESCE(description, '')),
    STRUCT('RETRIEVAL_DOCUMENT' AS task_type)
  ) AS embedding
FROM `your-project.your_dataset.products`
WHERE is_active = TRUE
  AND description IS NOT NULL;

-- 2. ベクトルインデックスを再作成
CREATE OR REPLACE VECTOR INDEX product_embedding_idx
ON `your-project.your_dataset.product_embeddings_new`(embedding)
OPTIONS(
  index_type    = 'IVF',
  distance_type = 'COSINE',
  ivf_options   = '{"num_lists": 500}'
);

-- 3. テーブルをアトミックに差し替え（テーブルコピー→リネーム）
-- BigQuery にはリネームがないため、コピーして旧テーブルを削除する
```

:::message
本番環境では古いテーブルをすぐ削除せず、7日間タイムトラベルが効く状態で保持しておくと安全です。
:::

---

## GA4 データとの連携：検索品質の自動モニタリング

ベクトル検索の精度が実際の購買につながっているかを GA4 × BigQuery で検証します。

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
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'search'
),
purchase_sessions AS (
  SELECT DISTINCT
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'purchase'
)
SELECT
  s.search_term,
  COUNT(DISTINCT s.ga_session_id)            AS search_sessions,
  COUNT(DISTINCT p.ga_session_id)            AS purchase_sessions,
  SAFE_DIVIDE(
    COUNT(DISTINCT p.ga_session_id),
    COUNT(DISTINCT s.ga_session_id)
  )                                          AS search_to_purchase_rate
FROM search_events AS s
LEFT JOIN purchase_sessions AS p
  USING (ga_session_id)
GROUP BY s.search_term
HAVING COUNT(DISTINCT s.ga_session_id) >= 10
ORDER BY search_to_purchase_rate ASC
LIMIT 50;
```

購買率の低い検索クエリは「ベクトル検索の結果が購買意図と合っていない」サインです。このリストを定期的に確認してエンベディングモデルや商品説明文を改善します。

---

## インデックスカバレッジの監視クエリ

パイプライン実行後にカバレッジが低下していないかを確認します。

```sql
SELECT
  index_name,
  coverage_percentage,
  last_refresh_time,
  unindexed_row_count,
  total_logical_bytes / (1024 * 1024) AS size_mb
FROM `your-project.your_dataset.INFORMATION_SCHEMA.VECTOR_INDEXES`
WHERE table_name = 'product_embeddings'
ORDER BY last_refresh_time DESC
LIMIT 5;
```

`unindexed_row_count` が増え続ける場合、MERGE の INSERT が大量に走ってインデックスの再構築が追いついていない可能性があります。その場合は `CREATE OR REPLACE VECTOR INDEX` で手動再構築を行います。

---

## コスト試算の目安

| 処理 | コストの主な要因 |
|---|---|
| `AI.EMBED` の実行 | トークン数 × モデル単価 |
| `MERGE` DML | 処理バイト数（通常クエリと同様） |
| `VECTOR INDEX` 維持 | ストレージ（論理バイト） |
| `VECTOR_SEARCH` クエリ | 処理バイト数 |

日次差分が数千件以下のEC規模であれば、`AI.EMBED` のトークンコストは月数百円程度に収まるケースが多いです。ただしモデルの全件再構築時は一時的にコストが跳ね上がるため、月次・四半期ごとの計画実行を推奨します。

---

## まとめ

- ウォーターマークテーブルで差分検知し、MERGE で差分エンベディングを更新する
- `VECTOR INDEX` はテーブルへの書き込みを検知してカバレッジを自動更新する
- モデルバージョン切り替え時は全件再構築が必要で、旧テーブルはすぐ削除しない
- GA4 の検索→購買率で検索品質を定期モニタリングし、エンベディングの精度を保つ
- `INFORMATION_SCHEMA.VECTOR_INDEXES` でカバレッジを監視する

次回（第14回）は `AI.FORECAST` と TimesFM を使った学習不要の時系列予測を解説します。

---

## 参考

- [Introduction to Autonomous Embedding Pipelines | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/autonomous-pipelines)
- [Schedule queries | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/scheduling-queries)
- [VECTOR_SEARCH function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/vector-functions#vector_search)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
