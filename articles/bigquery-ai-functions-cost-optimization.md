---
title: "AI関数のコスト最適化 — トークン課金を膨らませない設計"
emoji: "💰"
type: "tech"
topics: ["BigQuery", "GoogleCloud", "AI", "コスト最適化", "LLM"]
published: true
---

## この記事で解決する課題

BigQueryのAI関数（`AI.GENERATE`、`AI.CLASSIFY`、`AI.SCORE`など）を試したところ、想定外の請求が来た――そういう事例が増えています。

AI関数はトークン単位の課金モデルです。通常のBigQueryクエリのバイトスキャン課金とは構造が異なるため、既存のコスト管理の感覚が通用しません。この記事では、AI関数の課金構造を整理し、コストを膨らませない設計パターンを解説します。

---

## AI関数の課金構造を正確に把握する

AI関数はVertex AIのモデルAPIを内部で呼び出します。そのため課金は以下の2軸になります。

- **入力トークン**: プロンプト文字列 + 各行のデータをトークン化した数
- **出力トークン**: モデルが生成したレスポンスのトークン数

BigQueryのスキャン課金は通常どおり発生しますが、AI関数のコストの大部分はトークン課金です。

### モデル別の単価（2025年時点の目安）

```sql
-- 使用モデルを確認するクエリ例
SELECT
  model,
  COUNT(*) AS calls,
  SUM(ml_tokens) AS total_tokens
FROM
  `region-us`.INFORMATION_SCHEMA.JOB_TIMELINE
WHERE
  job_type = 'ML'
  AND DATE(creation_time) = CURRENT_DATE()
GROUP BY model
```

Gemini 1.5 Flashは低コストですが、出力品質はGemini 1.5 Proより劣る場面があります。タスクに応じてモデルを選択することが、コスト最適化の第一歩です。

---

## コストを膨らませる典型的なミス

### ミス1: 全件に対してAI関数を実行する

最もよくある過ちは、フィルタリングなしで全行にAI関数を適用することです。

```sql
-- NG: 全件処理（コスト大）
SELECT
  product_id,
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    CONCAT('次の商品説明を改善してください: ', description)
  )
FROM products
```

```sql
-- OK: 対象を絞ってから処理
SELECT
  product_id,
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    CONCAT('次の商品説明を改善してください: ', description)
  )
FROM products
WHERE
  description IS NOT NULL
  AND LENGTH(description) < 100  -- 短い説明文のみ改善対象
  AND updated_at < DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)  -- 未更新のものに限定
```

### ミス2: プロンプトに不要な情報を含める

入力トークンはプロンプト全体で計算されます。余分な情報を含めると、それだけでコストが増加します。

```sql
-- NG: 冗長なプロンプト
SELECT
  AI.CLASSIFY(
    MODEL `project.dataset.gemini_model`,
    CONCAT(
      'あなたは優秀なデータアナリストです。以下の商品レビューを読み、',
      'ポジティブ、ネガティブ、ニュートラルの3つのカテゴリのうち1つに分類してください。',
      '必ず回答は1単語のみにしてください。商品レビュー: ', review_text
    )
  )
FROM reviews
```

```sql
-- OK: 簡潔なプロンプト
SELECT
  AI.CLASSIFY(
    MODEL `project.dataset.gemini_model`,
    review_text,
    ['positive', 'negative', 'neutral']
  )
FROM reviews
```

`AI.CLASSIFY`には分類ラベルを配列で渡せます。自由形式のプロンプトより簡潔に記述でき、出力も安定します。

### ミス3: max_output_tokensを設定しない

出力トークンは上限を指定しないと、モデルが長文を生成してコストが跳ね上がることがあります。

```sql
-- OK: 出力トークンに上限を設定
SELECT
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    prompt,
    STRUCT(256 AS max_output_tokens, 0.1 AS temperature)
  )
FROM my_table
```

---

## コスト最適化の設計パターン

### パターン1: バッチサイズを絞って段階実行する

一度に全件処理するのではなく、毎日の差分のみに絞ります。

```sql
-- 前日追加・更新されたレコードのみ処理
SELECT
  product_id,
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    CONCAT('商品説明のキーワードを3つ抽出してください: ', description)
  ) AS keywords
FROM products
WHERE
  DATE(updated_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND description IS NOT NULL
```

### パターン2: 結果をテーブルにキャッシュする

同じ入力に対してAI関数を繰り返し呼び出さないよう、結果をテーブルに保存します。

```sql
-- AI処理結果を専用テーブルに保存
CREATE OR REPLACE TABLE `project.dataset.product_ai_cache`
AS
SELECT
  product_id,
  description,
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    CONCAT('商品カテゴリを1語で答えてください: ', description)
  ) AS ai_category,
  CURRENT_TIMESTAMP() AS processed_at
FROM products
WHERE
  product_id NOT IN (
    SELECT product_id FROM `project.dataset.product_ai_cache`
  )
```

以降のクエリはキャッシュテーブルを参照します。AI関数の呼び出しは新規レコードのみに限定されます。

### パターン3: 軽量モデルで事前フィルタリングする

高精度が必要な処理の前に、軽量モデルで事前スクリーニングします。

```sql
-- Step1: Flashモデルで大量データをスクリーニング
CREATE TEMP TABLE screened AS
SELECT *
FROM reviews
WHERE
  AI.CLASSIFY(
    MODEL `project.dataset.gemini_flash_model`,
    review_text,
    ['relevant', 'spam', 'offtopic']
  ) = 'relevant'
;

-- Step2: 絞り込まれたデータにのみProモデルを適用
SELECT
  review_id,
  AI.GENERATE(
    MODEL `project.dataset.gemini_pro_model`,
    CONCAT('このレビューの課題を構造化してください: ', review_text),
    STRUCT(512 AS max_output_tokens)
  ) AS structured_feedback
FROM screened
```

---

## コスト監視の仕組みを作る

AI関数のコストはINFORMATION_SCHEMAから監視できます。

```sql
-- AI関数のコスト・トークン使用量を日次集計
SELECT
  DATE(creation_time) AS execution_date,
  job_id,
  query,
  total_slot_ms,
  total_bytes_processed,
  -- AI関数関連の情報はjob_statisticsに含まれる
  TO_JSON_STRING(job_statistics) AS stats_json
FROM
  `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
  DATE(creation_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND REGEXP_CONTAINS(query, r'AI\.(GENERATE|CLASSIFY|SCORE|EMBED|IF)')
ORDER BY
  creation_time DESC
```

:::message
AI関数のトークン消費量の詳細は、現時点ではCloud Billingのコストエクスプローラーでも確認できます。BigQueryの請求明細で「Vertex AI」関連の行を確認してください。
:::

### スケジュールクエリにコスト上限を設定する

スケジュールクエリでAI関数を定期実行する場合は、行数の上限を明示的に設けます。

```sql
-- 1日あたりの処理行数を上限設定
WITH target_rows AS (
  SELECT
    product_id,
    description
  FROM products
  WHERE
    ai_processed_at IS NULL
    OR ai_processed_at < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  LIMIT 1000  -- 1回あたりの処理件数を制限
)
SELECT
  product_id,
  AI.GENERATE(
    MODEL `project.dataset.gemini_model`,
    CONCAT('要約（50字以内）: ', description),
    STRUCT(100 AS max_output_tokens)
  ) AS summary
FROM target_rows
```

---

## コスト感の目安

実務での参考値として、以下のような規模感を想定して設計してください。

| 処理規模 | 想定トークン数 | おおよその費用感 |
|---------|-------------|---------------|
| 商品説明1,000件の分類 | 入力50万 / 出力5万トークン | 数十〜数百円規模 |
| 商品説明10,000件の生成 | 入力500万 / 出力100万トークン | 数百〜数千円規模 |
| 全注文50万件の感情分析 | 入力5,000万 / 出力500万トークン | 数万円規模 |

処理規模が大きい場合は、まず小規模でテストし、トークン消費量を実測してから本番展開を判断してください。

---

## まとめ

BigQueryのAI関数コストを最適化するポイントは以下の4つです。

1. **対象を絞る**: WHEREでフィルタリングしてから処理する
2. **プロンプトを簡潔に**: 不要な文章を削り、専用関数（AI.CLASSIFYなど）を活用する
3. **出力を制限する**: max_output_tokensを設定して上限を管理する
4. **結果をキャッシュする**: 処理済みフラグを管理して再実行を防ぐ

AI関数は適切に設計すれば、データ分析の質を大幅に高められます。コストを把握した上で、段階的に活用範囲を広げていくことをお勧めします。

---

データ基盤の設計・GA4分析の自動化・AI活用についてのご相談は、ぜひ以下からお問い合わせください。

https://coconala.com/services/1791205
