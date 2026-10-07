---
title: "SQL内プロンプト設計のコツ — 出力を安定させる書き方"
emoji: "🎯"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "sql", "promptengineering"]
published: true
---

## はじめに

シリーズ第16回です。

前回（第15回）では `ObjectRef` を使って画像・PDFなどの非構造化データをSQLから扱う方法を解説しました。今回は **SQL内プロンプト設計** を掘り下げます。

BigQueryのAI関数（`AI.GENERATE`・`AI.CLASSIFY`・`AI.GENERATE_TABLE`など）は、SQLの中にプロンプトを直接記述します。通常のチャットAIと違い、**大量の行を一括処理する**・**結果をそのままテーブルに保存する**という特性があるため、出力が安定しないと後続の集計やジョインが破綻します。

本記事では「出力が安定しないとき」の原因と、SQL内プロンプト設計で使えるパターンをまとめます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## なぜSQL内プロンプトは難しいのか

通常のチャットAIとの最大の違いは次の3点です。

| 比較項目 | チャットAI | SQL内AI関数 |
|---|---|---|
| 実行単位 | 1リクエスト | 数千〜数百万行を並列処理 |
| 結果の利用方法 | 画面で読む | WHERE句・JOIN・集計に使う |
| 失敗の影響 | 読み直して再試行 | NULL・型エラー・ジョイン不一致が連鎖 |

チャットでは多少揺れのある出力でも問題ありませんが、SQLでは「カテゴリ分類が行によって『アパレル』だったり『アパレル・ファッション』だったり」するだけで GROUP BY が壊れます。

---

## 出力を安定させる5つの設計パターン

### パターン1: 出力形式を明示する

**NG例（揺れが生じやすい）**

```sql
SELECT
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT('この商品レビューの感情を分析してください。\nレビュー: ' || review_text AS prompt)
  ).text AS sentiment
FROM `your-project.your_dataset.product_reviews`;
```

**OK例（形式を固定）**

```sql
SELECT
  review_id,
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT(
      '以下のレビューの感情を「positive」「neutral」「negative」の3値から1つだけ出力してください。\n'
      || '出力は選択肢の単語のみ。説明文不要。\n\nレビュー: '
      || review_text AS prompt
    )
  ).text AS sentiment_raw
FROM `your-project.your_dataset.product_reviews`;
```

「1つだけ出力」「説明文不要」という制約を追加することで、余計な前置き文が入らなくなります。

---

### パターン2: 選択肢を列挙して閉集合を作る

分類タスクでは `AI.CLASSIFY` か、`AI.GENERATE` に選択肢を渡す形を使います。

```sql
SELECT
  product_id,
  inquiry_text,
  AI.CLASSIFY(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_text,
    labels => [
      'サイズ・カラー問い合わせ',
      '配送・到着日問い合わせ',
      '返品・交換依頼',
      '商品品質クレーム',
      'その他'
    ],
    STRUCT('お客様の問い合わせ内容を上記ラベルから1つ選んで分類してください。' AS prompt)
  ).label AS inquiry_category
FROM `your-project.your_dataset.customer_inquiries`
WHERE inquiry_text IS NOT NULL;
```

`AI.CLASSIFY` は内部で選択肢に対するスコアリングを行うため、`AI.GENERATE` よりも分類の安定性が高くなります。

---

### パターン3: JSON出力を強制してAI.GENERATE_TABLEに移行する

複数フィールドを返す場合、文字列解析よりも `AI.GENERATE_TABLE` の `output_schema` で型を強制する方が安定します。

**NG: AI.GENERATEでJSONを自力でパース**

```sql
SELECT
  product_id,
  JSON_VALUE(
    AI.GENERATE(
      MODEL `your-project.ai_lab.gemini_model`,
      STRUCT('商品説明から{"color":"","size":"","material":""}の形式でJSON出力してください。\n説明: ' || description AS prompt)
    ).text,
    '$.color'
  ) AS color
FROM `your-project.your_dataset.products`;
```

モデルの返答に ```json ... ``` のコードフェンスが付いたり、余分なテキストが混ざるとパースが壊れます。

**OK: AI.GENERATE_TABLEでスキーマを強制**

```sql
SELECT *
FROM
  AI.GENERATE_TABLE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT product_id, description
      FROM `your-project.your_dataset.products`
      WHERE description IS NOT NULL
    ),
    input_columns  => ['description'],
    output_schema  => JSON '{"color": "string", "size": "string", "material": "string"}',
    STRUCT('商品説明文から色・サイズ・素材を抽出してください。' AS prompt)
  );
```

`output_schema` を指定することで、出力が自動的に指定の型に変換されます。

---

### パターン4: 入力を前処理してコンテキストを絞る

長大なテキストをそのまま渡すと出力が不安定になります。入力側で必要な情報に絞ることが重要です。

```sql
WITH trimmed_reviews AS (
  SELECT
    review_id,
    -- 改行・タブをスペースに統一し、200文字に切り詰める
    SUBSTR(
      REGEXP_REPLACE(review_text, r'[\r\n\t]+', ' '),
      1, 200
    ) AS review_trimmed
  FROM `your-project.your_dataset.product_reviews`
  WHERE CHAR_LENGTH(TRIM(review_text)) >= 10
)
SELECT
  review_id,
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT(
      '以下のレビューが購入を推奨しているか？「yes」か「no」のみ出力してください。\nレビュー: '
      || review_trimmed AS prompt
    )
  ).text AS is_recommend_raw
FROM trimmed_reviews;
```

:::message
入力に改行や特殊文字が多いと、プロンプトの構造がモデルに誤認されることがあります。事前に `REGEXP_REPLACE` で正規化しておくのが安全です。
:::

---

### パターン5: 出力の後処理でNULLと揺れを吸収する

どれだけプロンプトを整えても一定の揺れは残ります。後処理で吸収する設計にしておくことで、分析クエリ全体が壊れません。

```sql
WITH raw_sentiment AS (
  SELECT
    review_id,
    LOWER(TRIM(
      AI.GENERATE(
        MODEL `your-project.ai_lab.gemini_model`,
        STRUCT(
          '感情を「positive」「neutral」「negative」の3値から1つのみ出力してください。\nレビュー: '
          || review_text AS prompt
        )
      ).text
    )) AS sentiment_raw
  FROM `your-project.your_dataset.product_reviews`
)
SELECT
  review_id,
  sentiment_raw,
  CASE
    WHEN sentiment_raw LIKE '%positive%' THEN 'positive'
    WHEN sentiment_raw LIKE '%negative%' THEN 'negative'
    WHEN sentiment_raw LIKE '%neutral%'  THEN 'neutral'
    ELSE 'unknown'
  END AS sentiment
FROM raw_sentiment;
```

`LOWER(TRIM(...))` で大文字/スペースの揺れを正規化し、`LIKE` で部分一致を許容することで想定外の出力を `unknown` に倒します。

---

## GA4データとの組み合わせ例

感情分析結果とGA4の購買行動を結合して「ネガティブレビューが多い商品はCVRが下がるか」を検証する例です。

```sql
WITH review_sentiment AS (
  SELECT
    product_id,
    COUNTIF(sentiment = 'positive') AS positive_count,
    COUNTIF(sentiment = 'negative') AS negative_count,
    COUNTIF(sentiment = 'unknown')  AS unknown_count,
    COUNT(*)                        AS total_reviews,
    SAFE_DIVIDE(
      COUNTIF(sentiment = 'negative'),
      COUNT(*)
    )                               AS negative_ratio
  FROM (
    SELECT
      product_id,
      CASE
        WHEN LOWER(TRIM(
          AI.GENERATE(
            MODEL `your-project.ai_lab.gemini_model`,
            STRUCT('感情を「positive」「neutral」「negative」から1つのみ出力してください。\nレビュー: ' || review_text AS prompt)
          ).text
        )) LIKE '%negative%' THEN 'negative'
        WHEN LOWER(TRIM(
          AI.GENERATE(
            MODEL `your-project.ai_lab.gemini_model`,
            STRUCT('感情を「positive」「neutral」「negative」から1つのみ出力してください。\nレビュー: ' || review_text AS prompt)
          ).text
        )) LIKE '%positive%' THEN 'positive'
        ELSE 'neutral'
      END AS sentiment
    FROM `your-project.your_dataset.product_reviews`
    WHERE CHAR_LENGTH(TRIM(review_text)) >= 10
  )
  GROUP BY product_id
),
ga4_cvr AS (
  SELECT
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'item_id'
    )                   AS product_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    )                   AS ga_session_id,
    event_name
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN ('view_item', 'purchase')
    AND (
      SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'
    ) IS NOT NULL
),
cvr_by_product AS (
  SELECT
    product_id,
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNTIF(event_name = 'view_item')
    ) AS cvr
  FROM ga4_cvr
  GROUP BY product_id
)
SELECT
  r.product_id,
  r.negative_ratio,
  r.total_reviews,
  ROUND(c.cvr * 100, 2) AS cvr_pct
FROM review_sentiment AS r
LEFT JOIN cvr_by_product AS c USING (product_id)
WHERE r.total_reviews >= 5
ORDER BY r.negative_ratio DESC
LIMIT 20;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` でキー名 `ga_session_id` の値を取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## よくある失敗と対処法

| 失敗パターン | 原因 | 対処法 |
|---|---|---|
| 出力に説明文が混じる | プロンプトに出力形式を明示していない | 「〜のみ出力」「説明文不要」を追加 |
| JSONのコードフェンスが付く | モデルがMarkdown形式で返している | `AI.GENERATE_TABLE` に移行するか `REGEXP_EXTRACT` で抽出 |
| NULL行が多い | 入力テキストが空・短すぎる | 事前に `CHAR_LENGTH >= N` でフィルタ |
| 分類が細かく割れる | ラベルの粒度が細かすぎる・類似ラベルがある | ラベルを5〜7個程度に絞り説明文を付ける |
| 同じ内容でも行によって出力が違う | temperatureが高い | `temperature = 0` をオプションで指定する |

---

## temperatureを0に固定する

再現性を高めたい分類・抽出タスクでは `temperature = 0` を指定します。

```sql
SELECT
  product_id,
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT('感情を「positive」「neutral」「negative」から1つのみ出力してください。\nレビュー: ' || review_text AS prompt),
    STRUCT(0 AS temperature)
  ).text AS sentiment_raw
FROM `your-project.your_dataset.product_reviews`
WHERE CHAR_LENGTH(TRIM(review_text)) >= 10;
```

---

## まとめ

- SQL内プロンプトは「大量行の並列処理」と「結果をSQLで利用する」という制約があるため、出力の安定が最優先
- 出力形式の明示・選択肢の列挙・`AI.GENERATE_TABLE` の活用・入力の前処理・後処理による揺れ吸収の5パターンを組み合わせる
- `temperature = 0` で再現性を高める
- 失敗を想定した設計（`unknown` へのフォールバック）が後続クエリの品質を守る

次回（第17回）は AI関数のコスト最適化 — トークン課金を膨らませない設計 を解説します。

---

## 参考

- [AI.GENERATE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate)
- [AI.CLASSIFY function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_classify)
- [AI.GENERATE_TABLE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate_table)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
