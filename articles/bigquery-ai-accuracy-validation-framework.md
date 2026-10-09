---
title: "AI関数の精度を検証する — 評価用データセットとテストの作り方"
emoji: "🔬"
type: "tech"
topics: ["BigQuery", "GoogleCloud", "AI", "機械学習", "データ品質"]
published: true
---

## この記事で解決する課題

BigQueryのAI関数（`AI.CLASSIFY`、`AI.GENERATE`、`AI.SCORE`など）を本番データに適用する前に、精度を定量的に確認できていますか。

「なんとなく動いている」で運用を始めると、モデルのアップデートや入力データの変化によって静かに精度が劣化し、誤った分析結果が意思決定に使われてしまいます。この記事では、評価用データセットの設計からSQL単体テストの実装まで、AI関数の精度を継続的に検証する仕組みの作り方を解説します。

---

## なぜ精度検証が必要なのか

AI関数の出力はモデルの確率的な推論に基づいています。同じプロンプトでも微妙に結果が変わる場合があり、特に以下の場面で精度劣化が発生しやすいです。

- **モデルバージョンの更新**: Geminiのモデルが自動更新され、出力傾向が変わる
- **入力データの変化**: 商品説明のフォーマットや表現が変わる
- **プロンプトの変更**: 改善のつもりが一部のケースで精度が下がる

精度検証の仕組みがなければ、これらの変化を検知できません。

---

## 評価データセットの設計

精度検証の核心は、正解ラベル付きのゴールドセットを用意することです。

### ゴールドセットの要件

```sql
-- 評価用ゴールドセットのテーブル定義例
CREATE TABLE `project.dataset.ai_evaluation_gold`
(
  eval_id        STRING NOT NULL,
  input_text     STRING NOT NULL,
  expected_label STRING NOT NULL,    -- 人手で付けた正解ラベル
  source_table   STRING,             -- データの出所
  difficulty     STRING,             -- easy/medium/hard
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
```

ゴールドセットには次の3種類のデータを含めます。

| 種類 | 内容 | 割合の目安 |
|-----|------|---------|
| 典型例 | モデルが容易に正解できるケース | 50% |
| 境界例 | 分類が難しい曖昧なケース | 30% |
| エッジケース | 極端に短い・長い・特殊な表現 | 20% |

境界例とエッジケースを意図的に含めることで、プロンプト改修後の退行を検出しやすくなります。

### 正解ラベルの付け方

```sql
-- 評価データを準備するクエリ（人手レビュー用に出力）
SELECT
  product_id AS eval_id,
  description AS input_text,
  NULL AS expected_label,  -- 人手でラベルを付ける列
  'products' AS source_table
FROM `project.dataset.products`
WHERE
  RAND() < 0.01  -- 全体の1%をサンプリング
  AND description IS NOT NULL
  AND LENGTH(description) BETWEEN 20 AND 500
ORDER BY RAND()
LIMIT 200
```

このクエリで抽出したデータをスプレッドシートに書き出し、業務担当者がラベルを付けた後、ゴールドセットテーブルに取り込みます。最低でも100〜200件、クラスが複数ある場合は各クラス30件以上を目安にしてください。

---

## 分類精度の測定

`AI.CLASSIFY`を使った分類タスクでは、精度（Precision）と再現率（Recall）を計算します。

```sql
-- AI.CLASSIFYの出力をゴールドセットと突き合わせて精度を計算
WITH ai_results AS (
  SELECT
    g.eval_id,
    g.expected_label,
    AI.CLASSIFY(
      MODEL `project.dataset.gemini_model`,
      g.input_text,
      ['positive', 'negative', 'neutral']
    ) AS predicted_label
  FROM `project.dataset.ai_evaluation_gold` AS g
  WHERE source_table = 'products'
),

confusion AS (
  SELECT
    expected_label,
    predicted_label,
    COUNT(*) AS cnt
  FROM ai_results
  GROUP BY 1, 2
),

per_class AS (
  SELECT
    expected_label AS label,
    SUM(CASE WHEN expected_label = predicted_label THEN cnt ELSE 0 END) AS tp,
    SUM(CASE WHEN expected_label != predicted_label THEN cnt ELSE 0 END) AS fn,
    SUM(CASE WHEN predicted_label = expected_label
             AND expected_label != label     THEN cnt ELSE 0 END) AS fp
  FROM confusion
  GROUP BY label
)

SELECT
  label,
  tp,
  fn,
  fp,
  SAFE_DIVIDE(tp, tp + fp) AS precision_score,
  SAFE_DIVIDE(tp, tp + fn) AS recall_score,
  SAFE_DIVIDE(2 * tp, 2 * tp + fp + fn) AS f1_score
FROM per_class
ORDER BY f1_score DESC
```

### 全体の正解率（Accuracy）

```sql
-- シンプルな全体正解率の確認
SELECT
  COUNT(*) AS total,
  COUNTIF(expected_label = predicted_label) AS correct,
  ROUND(COUNTIF(expected_label = predicted_label) / COUNT(*), 4) AS accuracy
FROM ai_results
```

---

## 生成タスクの品質測定

`AI.GENERATE`のような自由形式の生成タスクは、ラベルで評価できません。代わりに以下の方法で品質を定量化します。

### ルールベースの検証

```sql
-- 生成結果がルールを満たしているかチェック
WITH generated AS (
  SELECT
    product_id,
    AI.GENERATE(
      MODEL `project.dataset.gemini_model`,
      CONCAT('次の商品説明を50字以内で要約してください: ', description),
      STRUCT(100 AS max_output_tokens)
    ) AS summary
  FROM `project.dataset.ai_evaluation_gold`
  WHERE source_table = 'products'
)

SELECT
  COUNT(*) AS total,
  COUNTIF(summary IS NOT NULL) AS non_null_count,
  COUNTIF(LENGTH(summary) <= 50) AS within_length,
  COUNTIF(LENGTH(summary) BETWEEN 10 AND 50) AS quality_count,
  ROUND(COUNTIF(LENGTH(summary) BETWEEN 10 AND 50) / COUNT(*), 4) AS quality_rate
FROM generated
```

### AI-as-a-Judgeによる品質評価

生成品質をAI関数自体で評価する手法です。

```sql
-- AI生成物の品質をAIで評価する（AI-as-a-Judge）
SELECT
  product_id,
  original_description,
  generated_summary,
  AI.CLASSIFY(
    MODEL `project.dataset.gemini_model`,
    CONCAT(
      '元の説明: ', original_description,
      '\n要約: ', generated_summary
    ),
    ['excellent', 'good', 'poor']
  ) AS quality_judgment
FROM `project.dataset.generated_summaries`
```

この手法は絶対的な精度測定ではありませんが、プロンプト改修前後の比較に活用できます。

---

## 継続的な精度監視の実装

ゴールドセットに対する精度を定期的に計測し、テーブルに記録します。

```sql
-- 精度評価結果を履歴テーブルに記録
INSERT INTO `project.dataset.ai_accuracy_history`
SELECT
  CURRENT_DATE() AS eval_date,
  'classify_sentiment' AS task_name,
  COUNT(*) AS total_samples,
  COUNTIF(expected_label = predicted_label) AS correct_count,
  ROUND(COUNTIF(expected_label = predicted_label) / COUNT(*), 4) AS accuracy,
  'gemini-1.5-flash-001' AS model_version
FROM (
  SELECT
    g.expected_label,
    AI.CLASSIFY(
      MODEL `project.dataset.gemini_model`,
      g.input_text,
      ['positive', 'negative', 'neutral']
    ) AS predicted_label
  FROM `project.dataset.ai_evaluation_gold` AS g
)
```

このクエリをスケジュールクエリとして毎週実行し、精度の推移をLooker Studioで可視化することで、モデル更新による退行を早期に検知できます。

### 精度アラートの設定

```sql
-- 精度が閾値を下回ったら検知するクエリ
SELECT
  eval_date,
  task_name,
  accuracy,
  LAG(accuracy) OVER (PARTITION BY task_name ORDER BY eval_date) AS prev_accuracy,
  accuracy - LAG(accuracy) OVER (PARTITION BY task_name ORDER BY eval_date) AS delta
FROM `project.dataset.ai_accuracy_history`
WHERE
  eval_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
HAVING
  delta < -0.05  -- 5%以上の精度低下を検知
ORDER BY eval_date DESC
```

このクエリの結果をCloud Schedulerと組み合わせてSlack通知する仕組みにすると、精度劣化の見落としを防げます。

---

## 評価フレームワークの全体像

実装のステップをまとめると以下の流れになります。

1. **ゴールドセット作成**: サンプリング→人手ラベル付け→テーブル取り込み
2. **ベースライン計測**: 初回精度を測定して基準値として記録
3. **定期評価**: スケジュールクエリで週次・月次に精度を計測
4. **アラート設定**: 精度が閾値を下回ったら通知
5. **プロンプト改修サイクル**: 精度低下の原因を分析してプロンプトを修正

特にゴールドセットのメンテナンスは継続的に行います。入力データの分布が変わった場合は、新しいデータをサンプリングしてゴールドセットを拡充してください。

---

## まとめ

BigQueryのAI関数を本番運用するためには、精度を定量的に把握する仕組みが不可欠です。

- **ゴールドセット**を作り、典型例・境界例・エッジケースを含める
- **Precision/Recall/F1**でクラス別に精度を測定する
- **精度履歴テーブル**に記録し、推移を監視する
- **アラート**で精度劣化を早期検知する

AI関数はモデルの確率的な出力に依存します。精度検証の仕組みを整えることで、信頼性の高いAI活用基盤を構築できます。

---

データ基盤の設計・AI関数の活用支援・BigQuery × GA4分析についてのご相談は、ぜひ以下からお問い合わせください。

https://coconala.com/services/1791205
