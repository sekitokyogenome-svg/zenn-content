---
title: "AI.GENERATE_TABLEで非構造化テキストを構造化データに変換する"
emoji: "📋"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第6回です。

前回（第5回）では `AI.GENERATE` の引数・戻り値の STRUCT・実務パターンを整理しました。今回は **`AI.GENERATE_TABLE`** を取り上げます。

EC 事業をデータで動かしているとき、非構造化データが分析の障壁になる場面は多くあります。商品レビュー・CS 問い合わせ・フォーム自由記述・SNS コメント――これらを集計しようとすると、まず「テキストをどう列にバラすか」という前処理が必要です。`AI.GENERATE` でも実現できますが、JSON を出力させてパースする手順が面倒です。`AI.GENERATE_TABLE` はその工程をまとめて引き受けてくれます。

:::message
本記事は 2026年7月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.GENERATE_TABLE とは

`AI.GENERATE_TABLE` は、**テキストを解析して、あらかじめ定義した列構成のテーブルに直接変換する**関数です。

`AI.GENERATE` との違いを一言でいうと：

| 関数 | 出力 | 向いているタスク |
|---|---|---|
| `AI.GENERATE` | `candidates[0].content`（文字列1列） | 要約・分類・自由生成 |
| `AI.GENERATE_TABLE` | 定義した列を持つ行（STRUCT ではなく通常の列） | 情報抽出・構造化 |

「商品名・価格・評価スコアをレビューテキストから抽出したい」「CS 問い合わせから問題カテゴリ・緊急度・担当部署を同時に抽出したい」といった用途では `AI.GENERATE_TABLE` の方がシンプルです。

---

## 基本構文

```sql
AI.GENERATE_TABLE(
  MODEL model_name,
  input_query,
  TABLE SCHEMA (
    column_name_1 column_type_1 OPTIONS (description = '説明'),
    column_name_2 column_type_2 OPTIONS (description = '説明'),
    ...
  )
  [, STRUCT(temperature AS temperature, ...)]
)
```

### TABLE SCHEMA の書き方

```sql
TABLE SCHEMA (
  category       STRING  OPTIONS (description = '問い合わせカテゴリ: 返品・交換/配送/在庫・取り寄せ/決済・請求/その他'),
  urgency        STRING  OPTIONS (description = '緊急度: 高/中/低'),
  product_name   STRING  OPTIONS (description = '問い合わせ対象の商品名。不明な場合は NULL'),
  summary        STRING  OPTIONS (description = '問い合わせ内容の50字以内の要約')
)
```

`description` がモデルへの指示になります。選択肢を具体的に列挙するか、「不明な場合は NULL」のような条件を書いておくと出力が安定します。

---

## 使用例①：CS 問い合わせの一括構造化

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.inquiry_structured` AS
SELECT
  inquiry_id,
  received_at,
  raw_text,
  category,
  urgency,
  product_name,
  summary
FROM
  AI.GENERATE_TABLE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT
        inquiry_id,
        received_at,
        inquiry_body AS raw_text,
        CONCAT(
          '以下の問い合わせテキストを解析して、指定された列に情報を抽出してください。\n\n',
          inquiry_body
        ) AS prompt
      FROM `your-project.your_dataset.raw_inquiries`
      WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    ),
    TABLE SCHEMA (
      category     STRING OPTIONS (description = '問い合わせカテゴリ: 返品・交換/配送/在庫・取り寄せ/決済・請求/その他'),
      urgency      STRING OPTIONS (description = '緊急度: 高/中/低'),
      product_name STRING OPTIONS (description = '対象商品名。不明な場合は NULL'),
      summary      STRING OPTIONS (description = '問い合わせ内容の要約（50字以内）')
    ),
    STRUCT(0.0 AS temperature)
  );
```

`AI.GENERATE` との最大の違いは、結果が `ml_generate_text_result` という STRUCT ではなく、`category`・`urgency`・`product_name`・`summary` という通常の列として返ってくる点です。後続の SQL でそのまま `GROUP BY category` や `WHERE urgency = '高'` が書けます。

---

## 使用例②：GA4 フォーム送信データとの結合

GA4 の `form_submit` イベントと外部の問い合わせテーブルを結合して、セッション文脈を保ちながら構造化します。

```sql
WITH session_info AS (
  SELECT
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    user_pseudo_id
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'form_submit'
)
SELECT
  s.ga_session_id,
  s.medium,
  t.category,
  t.urgency,
  t.summary
FROM
  AI.GENERATE_TABLE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT
        i.inquiry_id,
        i.ga_session_id,
        CONCAT(
          'このCS問い合わせを解析してください。\n\n問い合わせ本文: ',
          i.inquiry_body
        ) AS prompt
      FROM `your-project.your_dataset.form_inquiries` AS i
      INNER JOIN session_info AS s ON i.ga_session_id = s.ga_session_id
      WHERE DATE(i.received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    ),
    TABLE SCHEMA (
      category STRING OPTIONS (description = '問い合わせカテゴリ: 返品・交換/配送/在庫・取り寄せ/決済・請求/その他'),
      urgency  STRING OPTIONS (description = '緊急度: 高/中/低'),
      summary  STRING OPTIONS (description = '50字以内の要約')
    ),
    STRUCT(0.0 AS temperature)
  ) AS t
INNER JOIN session_info AS s ON t.ga_session_id = s.ga_session_id;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。直接カラムとして存在しないため注意してください。流入元の取得には `collected_traffic_source.manual_medium` を使います。
:::

---

## AI.GENERATE との使い分け判断フロー

```text
抽出したい情報が複数列ある
    ↓ Yes
AI.GENERATE_TABLE を使う

    ↓ No（1列でよい）
出力形式が自由文か
    ↓ Yes → AI.GENERATE
    ↓ No（分類・判定・ランクなど） → AI.CLASSIFY / AI.IF / AI.SCORE
```

複数の情報を同時に取り出したい場合、`AI.GENERATE` で JSON を出力させて `JSON_VALUE` でパースする方法でも実現できますが、手順が増える上にパースエラーのリスクもあります。`AI.GENERATE_TABLE` の方がコードが短く、エラーも出にくいです。

---

## コスト管理のポイント

### 前段で行を絞る

`AI.GENERATE` と同じく、サブクエリの WHERE で処理対象を最小化してください。

```sql
-- 悪い例：全件処理
FROM AI.GENERATE_TABLE(MODEL ..., (SELECT ... FROM inquiries), ...)

-- 良い例：当日分のみ
FROM AI.GENERATE_TABLE(MODEL ...,
  (SELECT ... FROM inquiries
   WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)),
  ...)
```

### TABLE SCHEMA の description を短くする

`description` の文字数はプロンプトのトークンに加算されます。選択肢を列挙する場合でも 100 字以内を目安にしてください。

### 結果をテーブルに保存する

同じ行を繰り返し処理しないよう `CREATE TABLE AS SELECT` でマテリアライズし、追加分のみ差分処理する設計にします。

---

## よくあるトラブルと対処

### 列の値が NULL ばかりになる

`description` の指示が不十分です。モデルがどのフィールドに何を入れればよいかを理解できていないため、抽出に失敗して NULL を返します。選択肢を明記するか、例示を追加してください。

### 特定の列だけ空文字になる

出力トークン数の不足か、description の指示が他の列と矛盾しています。`max_output_tokens` を増やし、各列の description が互いに独立して意味をなすか確認してください。

### 行数が元のテーブルと合わない

`AI.GENERATE_TABLE` はモデルの出力が空だった行をスキップする場合があります。`LEFT JOIN` で元テーブルと突合して欠損を検出するか、前段フィルタで空文字を除外してください。

---

## まとめ

- **`AI.GENERATE_TABLE`** は非構造化テキストから複数列を同時に抽出するときに使う
- `TABLE SCHEMA` の `description` がモデルへの指示になる。具体的に書くほど安定する
- `AI.GENERATE` との使い分けは「1列か複数列か」で判断する
- GA4 との組み合わせでは `UNNEST(event_params)` と `collected_traffic_source.manual_medium` を忘れずに使う
- コスト管理は前段フィルタ＋結果のマテリアライズが基本

次回は `AI.GENERATE_BOOL` / `AI.GENERATE_INT` / `AI.GENERATE_DOUBLE` を扱います。型付きの判定を SQL に埋め込む方法で、`AI.GENERATE` の出力を数値・真偽値に変換する手間が省けます。

---

## 参考

- [AI.GENERATE_TABLE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate_table)
- [Extract structured data from unstructured text | Google Cloud](https://cloud.google.com/bigquery/docs/extract-structured-data)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
