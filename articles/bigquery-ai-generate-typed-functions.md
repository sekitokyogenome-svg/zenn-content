---
title: "AI.GENERATE_BOOL / INT / DOUBLEで型付きの判定をSQLに埋め込む"
emoji: "🔢"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第7回です。

前回（第6回）では `AI.GENERATE_TABLE` を使って非構造化テキストを複数列の構造化データに変換する方法を整理しました。今回は **`AI.GENERATE_BOOL`** / **`AI.GENERATE_INT`** / **`AI.GENERATE_DOUBLE`** の3関数を取り上げます。

`AI.GENERATE` は文字列を返すため、「ポジティブか否か」「スコアは何点か」のような判定結果を後続の SQL で使うには、文字列パースの手間が発生します。型付きの判定関数を使えば、その変換ステップを省いて `WHERE` や `ORDER BY`、集計にそのまま組み込めます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## 3関数の概要

| 関数 | 戻り値の型 | 典型的な用途 |
|---|---|---|
| `AI.GENERATE_BOOL` | BOOL | 該当する／しない、ポジティブ／ネガティブ、スパムか否か |
| `AI.GENERATE_INT` | INT64 | 1〜5のスコア、優先度、カウント推定 |
| `AI.GENERATE_DOUBLE` | FLOAT64 | 0.0〜1.0の確信度、感情強度、類似スコア |

いずれも「`AI.GENERATE` でテキストを取り出してキャストする」の短縮形です。パースエラーのリスクがなく、型チェックがクエリ実行時に保証されます。

---

## 基本構文

3関数とも構文は共通です。

```sql
AI.GENERATE_BOOL(
  MODEL model_name,
  input_query,
  STRUCT(prompt AS prompt [, temperature AS temperature])
)

AI.GENERATE_INT(
  MODEL model_name,
  input_query,
  STRUCT(prompt AS prompt [, temperature AS temperature])
)

AI.GENERATE_DOUBLE(
  MODEL model_name,
  input_query,
  STRUCT(prompt AS prompt [, temperature AS temperature])
)
```

`AI.GENERATE` と異なり、**サブクエリに `prompt` 列を持たせるのではなく、STRUCT の `prompt` フィールドでプロンプトを渡します**。この点が大きく異なります。

戻り値は直接その型の値が返るため、`ml_generate_text_result.candidates[0].content` のような取り出し手順は不要です。

---

## AI.GENERATE_BOOL の使い方

### 例：CS 問い合わせのスパム判定

```sql
SELECT
  inquiry_id,
  inquiry_body,
  AI.GENERATE_BOOL(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      CONCAT(
        '以下のテキストはスパムまたは無意味なテスト送信ですか？',
        '「はい」なら TRUE、そうでなければ FALSE を返してください。\n\nテキスト: ',
        inquiry_body
      ) AS prompt,
      0.0 AS temperature
    )
  ) AS is_spam
FROM `your-project.your_dataset.raw_inquiries`
WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
```

戻り値が BOOL のため、`WHERE is_spam = FALSE` で有効な問い合わせだけを抽出するクエリをそのまま書けます。

### 例：商品レビューのポジティブ判定

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.review_positive_flag` AS
SELECT
  review_id,
  product_id,
  review_text,
  AI.GENERATE_BOOL(
    MODEL `your-project.ai_lab.gemini_model`,
    review_text,
    STRUCT(
      CONCAT(
        '次のレビューは全体的にポジティブな内容ですか？',
        'TRUE か FALSE だけを返してください。\n\nレビュー: ',
        review_text
      ) AS prompt,
      0.0 AS temperature
    )
  ) AS is_positive
FROM `your-project.your_dataset.reviews`
WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
```

---

## AI.GENERATE_INT の使い方

### 例：問い合わせの緊急度スコアリング

```sql
SELECT
  inquiry_id,
  received_at,
  inquiry_body,
  AI.GENERATE_INT(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      CONCAT(
        '次のCS問い合わせの緊急度を 1（低）〜5（高）の整数で評価してください。',
        '数字のみを返してください。\n\n問い合わせ: ',
        inquiry_body
      ) AS prompt,
      0.0 AS temperature
    )
  ) AS urgency_score
FROM `your-project.your_dataset.raw_inquiries`
WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
```

結果は INT64 のため、`ORDER BY urgency_score DESC` や `WHERE urgency_score >= 4` が型変換なしで使えます。

### GA4 データと組み合わせた例

フォーム送信イベントと問い合わせデータを結合し、流入チャネル別の緊急度分布を集計する例です。

```sql
WITH session_info AS (
  SELECT
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium AS medium
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'form_submit'
),
scored AS (
  SELECT
    i.inquiry_id,
    i.ga_session_id,
    AI.GENERATE_INT(
      MODEL `your-project.ai_lab.gemini_model`,
      i.inquiry_body,
      STRUCT(
        CONCAT(
          '問い合わせの緊急度を 1〜5 の整数で評価してください。数字のみ返してください。\n\n',
          i.inquiry_body
        ) AS prompt,
        0.0 AS temperature
      )
    ) AS urgency_score
  FROM `your-project.your_dataset.form_inquiries` AS i
  WHERE DATE(i.received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)
SELECT
  s.medium,
  AVG(sc.urgency_score) AS avg_urgency,
  COUNTIF(sc.urgency_score >= 4) AS high_urgency_count,
  COUNT(*) AS total
FROM scored AS sc
INNER JOIN session_info AS s ON sc.ga_session_id = s.ga_session_id
GROUP BY s.medium
ORDER BY avg_urgency DESC;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## AI.GENERATE_DOUBLE の使い方

### 例：レビューの感情強度スコア

```sql
SELECT
  review_id,
  product_id,
  review_text,
  AI.GENERATE_DOUBLE(
    MODEL `your-project.ai_lab.gemini_model`,
    review_text,
    STRUCT(
      CONCAT(
        '次のレビューのポジティブ感情の強度を 0.0（完全にネガティブ）〜',
        '1.0（非常にポジティブ）の小数で返してください。',
        '数値のみを返してください。\n\nレビュー: ',
        review_text
      ) AS prompt,
      0.0 AS temperature
    )
  ) AS sentiment_score
FROM `your-project.your_dataset.reviews`
WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

FLOAT64 として返るため、`AVG(sentiment_score)` で商品別の平均感情スコアをそのまま計算できます。

### 例：商品説明の品質スコア

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.product_desc_quality` AS
SELECT
  product_id,
  product_name,
  description,
  AI.GENERATE_DOUBLE(
    MODEL `your-project.ai_lab.gemini_model`,
    description,
    STRUCT(
      CONCAT(
        '次のEC商品説明文の品質を 0.0（不十分）〜1.0（優良）で評価してください。',
        '判断基準：具体的なスペック記載・ベネフィット説明・読みやすさ。',
        '数値のみを返してください。\n\n商品説明: ',
        description
      ) AS prompt,
      0.0 AS temperature
    )
  ) AS quality_score
FROM `your-project.your_dataset.products`
WHERE is_active = TRUE;
```

---

## AI.GENERATE との使い分け

```text
判定の結果を後続 SQL で直接使いたい
    ↓ Yes
型付き関数を使う
    ↓ True/False の二択       → AI.GENERATE_BOOL
    ↓ 整数スコア（1〜N）      → AI.GENERATE_INT
    ↓ 連続値（0.0〜1.0 など） → AI.GENERATE_DOUBLE

    ↓ No（テキストそのものが必要）
    → AI.GENERATE
```

ただし、**分類・判定・ランク付けが目的であれば `AI.CLASSIFY` / `AI.IF` / `AI.SCORE` を先に検討してください**。型付き生成関数はプロンプトを自分で書く分、設計の手間が増えます。マネージド関数が要件を満たすなら、そちらの方が安定します。

| 目的 | 推奨 |
|---|---|
| 決まったラベルに分類する | `AI.CLASSIFY` |
| 条件フィルタ（True/False） | `AI.IF` |
| スコアでランク付け | `AI.SCORE` |
| カスタムプロンプトで型付き値が必要 | 型付き生成関数 |
| 自由なテキスト出力が必要 | `AI.GENERATE` |

---

## コスト管理のポイント

### プロンプトの長さを絞る

出力が1〜2語になるタスクでも、プロンプト側のトークンは課金されます。指示文は簡潔にまとめてください。

```sql
-- 長すぎる例
CONCAT(
  'あなたはCS担当のエキスパートです。以下の問い合わせを詳細に分析し、',
  '長年の経験に基づいて緊急度を判断してください...',
  inquiry_body
) AS prompt

-- 短い例（十分機能する）
CONCAT('緊急度を1〜5の整数で評価。数字のみ返すこと。\n\n', inquiry_body) AS prompt
```

### 前段でフィルタする

他の AI 関数と同じく、サブクエリに WHERE を入れて処理対象の行数を絞ってください。

### 結果をマテリアライズする

同じ行に対して何度もモデルを呼ばないよう、`CREATE TABLE AS SELECT` で保存し、差分処理する設計にします。

---

## よくあるトラブルと対処

### 型変換エラーになる

モデルが指示と異なる形式（「5点」「約0.8」など）を返す場合、型変換に失敗します。プロンプトで「数字のみ返してください」と明示し、`temperature = 0.0` に設定してください。

### 常に同じ値が返る

`temperature = 0.0` にしても一定の多様性があります。プロンプトで選択肢や範囲を明確に定義すると、出力が安定します。

### 想定外の値が入る（範囲外）

モデルが指定した範囲（1〜5 など）を外れた値を返すことがあります。後処理で `GREATEST(1, LEAST(5, score))` などのクリッピングを加えておくと安全です。

---

## まとめ

- **`AI.GENERATE_BOOL`**：True/False の判定を型付きで直接返す。後続の WHERE やフラグカラムとして使いやすい
- **`AI.GENERATE_INT`**：スコアや優先度を整数で返す。`ORDER BY`・集計に変換なしで使える
- **`AI.GENERATE_DOUBLE`**：確信度や強度を連続値で返す。`AVG` などの数値集計に直結できる
- マネージド関数（`AI.CLASSIFY` / `AI.IF` / `AI.SCORE`）が要件を満たすなら、そちらが優先
- GA4 との組み合わせでは `UNNEST(event_params)` と `collected_traffic_source.manual_medium` を使う
- コスト対策は「プロンプト短縮＋前段フィルタ＋結果のマテリアライズ」の3点が基本

次回（第8回）は `AI.IF` を取り上げます。WHERE 句に意味ベースの条件を埋め込む「セマンティックフィルタ」で、従来のキーワードマッチでは拾えなかった行を自然言語で絞り込む方法を解説します。

---

## 参考

- [AI.GENERATE_BOOL function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate_bool)
- [AI.GENERATE_INT function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate_int)
- [AI.GENERATE_DOUBLE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate_double)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
