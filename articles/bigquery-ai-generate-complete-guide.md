---
title: "AI.GENERATE完全ガイド — 引数・戻り値STRUCT・実務での使いどころ"
emoji: "🔧"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第5回、フェーズ2の第1回です。

前回（第4回）では `ML.GENERATE_TEXT` から新世代の `AI.*` 関数への移行を整理しました。今回からフェーズ2として、個々の AI 関数を掘り下げていきます。最初は **`AI.GENERATE`** です。

`AI.GENERATE` は AI SQL 関数群の中で最も汎用性が高く、他の関数が提供しない細かい制御を必要とする場面で使います。引数の意味を正確に理解していないと「なぜかランダムな答えが返ってくる」「トークンが足りなくて出力が切れる」「コストが予想外に膨らむ」といったトラブルが起きやすい関数でもあります。本記事でいったん腰を据えて仕様を押さえておくと、フェーズ2の後半の関数たちも理解しやすくなります。

:::message
本記事は 2026年7月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.GENERATE の立ち位置を再確認する

第1回で整理した3層構造を思い出してください。

```text
層3：エージェント  ← 手順ごと任せる
層2：AI SQL関数   ← SQLの中で1行ずつモデルを呼ぶ  ← 今ここ
層1：基盤         ← 文脈と接続を供給する
```

`AI.GENERATE` は層2の中でも「プロンプトを自分で書く」タイプです。第1回で述べたように、**マネージド関数（`AI.CLASSIFY`・`AI.IF`・`AI.SCORE`）が提供しない細かい制御が必要なときに使う**位置づけです。

実務での使い分けの原則は以下のとおりです。

| 状況 | 使うもの |
|---|---|
| 分類・フィルタ・ランク付けが目的 | まず `AI.CLASSIFY` / `AI.IF` / `AI.SCORE` を試す |
| 出力フォーマットを構造化したい | `AI.GENERATE_TABLE` を検討する |
| 上記で要件が満たせない、または細かい制御が要る | `AI.GENERATE` を使う |

`AI.GENERATE` から入りたくなる気持ちは分かりますが、マネージド関数の方がプロンプト設計の手間が省けてコストも安定します。まず「マネージド関数で行けないか」を確認してから `AI.GENERATE` に降りる、という順序を習慣にしてください。

---

## 基本構文

```sql
AI.GENERATE(
  MODEL model_name,
  input_query,
  [ STRUCT(
      temperature       AS temperature,
      max_output_tokens AS max_output_tokens,
      top_p             AS top_p,
      top_k             AS top_k
  ) ]
)
```

各引数を順に説明します。

---

## 引数①：MODEL

```sql
MODEL `your-project.your_dataset.your_model`
```

`CREATE MODEL ... REMOTE WITH CONNECTION` で事前に作成したリモートモデルオブジェクトを指定します。接続セットアップは第2回（IAM・Vertex AI 接続）で扱ったとおりです。

第4回で説明したように `AI.GENERATE` は **モデルオブジェクト不要のモード（接続名を直接指定するモード）** も試験的に存在しますが、本番利用では明示的なモデルオブジェクトを作っておく方が管理しやすいです。

---

## 引数②：input_query（サブクエリ）

```sql
(
  SELECT
    id,
    CONCAT('次のテキストを要約してください: ', body) AS prompt
  FROM
    `your-project.your_dataset.articles`
  WHERE
    created_date = CURRENT_DATE()
)
```

サブクエリには必ず `prompt` という名前の列を含める必要があります。この列の値が Gemini に渡されるプロンプトです。それ以外の列（上の例では `id`）は**そのまま出力に引き継がれます**。

これは `ML.GENERATE_TEXT` とまったく同じ挙動です。結果テーブルには `prompt`、その他の引き継がれた列、そして戻り値の STRUCT が並びます。

---

## 引数③：STRUCT（オプション）

制御パラメータをまとめた STRUCT です。省略すると各パラメータのデフォルト値が使われます。

### temperature

```sql
STRUCT(0.0 AS temperature, ...)
```

| 値 | 挙動 |
|---|---|
| `0.0` | 確定的・再現性が高い |
| `0.5` 前後 | バランス型 |
| `1.0` 以上 | 多様性が増すが一貫性が下がる |

**分類・判定タスクには `0.0`**。要約・生成タスクでも `0.0`〜`0.2` に設定して安定させる方が実務では扱いやすいです。`1.0` 以上が有効なのは、意図的に多様な出力が欲しいクリエイティブ生成くらいです。

### max_output_tokens

```sql
STRUCT(..., 100 AS max_output_tokens)
```

モデルが返すトークン数の上限です。超えると出力が途中で切れます。

| 用途 | 目安 |
|---|---|
| 分類（ポジ/ネガ/中立） | 1〜10 |
| タグ付け（複数語） | 10〜30 |
| 50字以内の要約 | 50〜100 |
| 1段落の要約 | 150〜300 |
| 長文生成 | 300〜1000 |

少なく設定するほどコストが下がります。分類タスクで `max_output_tokens = 1024` にしている例を見かけますが、無駄が多いです。タスクに合わせて絞ってください。

### top_p・top_k

生成のランダム性を制御する追加パラメータです。多くの実務ケースでは `temperature` だけ調整すれば十分で、`top_p` と `top_k` まで触る必要はありません。モデルの挙動を細かくチューニングしたい場面まで触るのは後回しで構いません。

---

## 戻り値の STRUCT 構造

`AI.GENERATE` の戻り値は STRUCT です。`ml_generate_text_result` という列名で返ってきます（旧 `ML.GENERATE_TEXT` との互換性のためこの名前が使われています）。

```sql
-- 戻り値の構造
ml_generate_text_result STRUCT<
  candidates ARRAY<STRUCT<
    content       STRING,
    finish_reason STRING
  >>,
  prompt_feedback STRUCT<
    block_reason STRING
  >
>
```

多くの場合は最初の候補（`candidates[0]`）の `content` を取り出すだけで事足ります。

```sql
SELECT
  id,
  ml_generate_text_result.candidates[0].content AS generated_text
FROM
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT id, CONCAT('要約: ', body) AS prompt
      FROM `your-project.ai_lab.articles`
    ),
    STRUCT(0.0 AS temperature, 200 AS max_output_tokens)
  );
```

`finish_reason` には `STOP`（正常終了）や `MAX_TOKENS`（トークン上限で切れた）が入ります。出力が途中で切れているように見えるときは `finish_reason = 'MAX_TOKENS'` を確認し、`max_output_tokens` を増やしてください。

`prompt_feedback.block_reason` は、プロンプトがポリシー違反として拒否されたときに値が入ります。通常の業務データでは発生しませんが、外部から流れ込む自由テキストを処理するときは念のため確認しておく価値があります。

---

## GA4 データとの組み合わせパターン

### パターン1：問い合わせテキストの分類

GA4 のフォーム送信イベントと外部テーブルの問い合わせ本文を結合し、カテゴリを自動付与します。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
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
)
SELECT
  s.ga_session_id,
  s.medium,
  f.inquiry_text,
  gen.ml_generate_text_result.candidates[0].content AS category
FROM
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT
        s.ga_session_id,
        f.inquiry_text,
        CONCAT(
          '次の問い合わせ内容を以下のカテゴリのいずれかに分類してください。',
          'カテゴリ名のみを返してください。',
          'カテゴリ: 返品・交換、配送、在庫・取り寄せ、決済・請求、その他\n\n',
          '問い合わせ: ', f.inquiry_text
        ) AS prompt
      FROM session_data AS s
      INNER JOIN `your-project.your_dataset.form_inquiries` AS f
        ON s.ga_session_id = f.ga_session_id
    ),
    STRUCT(0.0 AS temperature, 10 AS max_output_tokens)
  ) AS gen
INNER JOIN session_data AS s ON gen.ga_session_id = s.ga_session_id
INNER JOIN `your-project.your_dataset.form_inquiries` AS f
  ON gen.ga_session_id = f.ga_session_id;
```

:::message
GA4 の `ga_session_id` はイベントテーブルに直接カラムとして存在しません。`UNNEST(event_params)` でキー名 `ga_session_id` の値を取り出す必要があります。流入元は `collected_traffic_source.manual_medium` を使ってください。
:::

### パターン2：商品レビューの感情分析とスコア集計

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.review_sentiment` AS
SELECT
  product_id,
  review_id,
  review_text,
  gen.ml_generate_text_result.candidates[0].content AS sentiment,
  gen.ml_generate_text_result.candidates[0].finish_reason AS finish_reason
FROM
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT
        product_id,
        review_id,
        review_text,
        CONCAT(
          '以下のレビューをポジティブ・ネガティブ・中立のいずれかに分類してください。',
          '一語のみ返してください。\n\nレビュー: ',
          review_text
        ) AS prompt
      FROM `your-project.your_dataset.reviews`
      WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    ),
    STRUCT(0.0 AS temperature, 5 AS max_output_tokens)
  ) AS gen;
```

結果テーブルに保存することで、ダッシュボードからクエリするたびにモデルを呼ばずに済みます。これが「AI 関数の結果は必ずマテリアライズする」の実装例です。

---

## コストを抑える3つの設計原則

### 原則1：前段で行を絞る

AI.GENERATE に渡すサブクエリの `FROM` 句には `WHERE` を入れてください。テーブル全件に対して呼ぶと、行数×トークン数分の課金が発生します。

```sql
-- 悪い例：全件流す
SELECT ...
FROM AI.GENERATE(MODEL ..., (SELECT id, prompt FROM big_table), ...)

-- 良い例：前日分のみ
SELECT ...
FROM AI.GENERATE(MODEL ...,
  (SELECT id, prompt FROM big_table
   WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)),
  ...)
```

### 原則2：max_output_tokens を絞る

タスクに必要な最小限のトークン数を設定してください。分類タスクで 1000 トークンを確保するのはほぼ無駄です。

### 原則3：結果をテーブルに保存して再利用する

同じ行に対して AI を何度も呼ばないように、結果を `CREATE TABLE AS SELECT` でマテリアライズします。スケジュールクエリと組み合わせて「差分のみ処理」する設計が理想です。

---

## よくあるトラブルと対処

### 出力が途中で切れる

`finish_reason = 'MAX_TOKENS'` が原因です。`max_output_tokens` を増やしてください。

### 答えがバラバラで安定しない

`temperature` を下げてください。分類タスクなら `0.0` が基本です。プロンプトで「一語のみ返してください」のように出力形式を厳密に指定することも有効です。

### 料金が予想より多い

前段フィルタが甘い、または `max_output_tokens` が大きすぎます。クエリ実行前に `SELECT COUNT(*)` で対象行数を確認する習慣をつけてください。

### プロンプトが拒否される

`prompt_feedback.block_reason` を確認してください。外部から流れ込む自由テキストにはまれにポリシー違反と判定されるものが混ざります。前段でフィルタするか、プロンプトの書き方を調整してください。

---

## まとめ

`AI.GENERATE` の要点をまとめます。

- **MODEL**：事前に `CREATE MODEL` したリモートモデルを指定する
- **input_query**：サブクエリに `prompt` 列を含める。他の列は出力に引き継がれる
- **temperature**：分類タスクは `0.0`。生成タスクでも低め（0.0〜0.2）が扱いやすい
- **max_output_tokens**：タスクに合わせて最小限に絞る。分類なら1桁で十分
- **戻り値**：`ml_generate_text_result.candidates[0].content` が生成テキスト
- **コスト管理**：前段フィルタ＋max_output_tokens 絞り込み＋結果のマテリアライズが3原則

次回は `AI.GENERATE_TABLE` を扱います。非構造化テキストを定義した列構成の表に変換する関数で、`AI.GENERATE` では一手間かかった「JSON パースして列に分解する」をシンプルに解決できます。

---

## 参考

- [AI.GENERATE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate)
- [Generate text by using AI.GENERATE | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/generate-text-tutorial)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
