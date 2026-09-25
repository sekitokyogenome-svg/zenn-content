---
title: "AI.IFでWHERE句に意味を持ち込む — セマンティックフィルタ入門"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: true
---

## はじめに

シリーズ第8回です。

前回（第7回）では `AI.GENERATE_BOOL` / `AI.GENERATE_INT` / `AI.GENERATE_DOUBLE` を使った型付き判定をSQLに組み込む方法を解説しました。今回は **`AI.IF`** を取り上げます。

`AI.IF` は WHERE 句や CASE 式に「意味の条件」を書くための関数です。キーワードの完全一致や正規表現ではなく、自然言語で記述した条件をもとに行を絞り込めます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## AI.IF とは

`AI.IF` は BOOL 値を返す AI 関数です。テキスト列に対して自然言語で記述した条件を評価し、条件を満たす場合に TRUE を返します。

```sql
AI.IF(
  MODEL model_name,
  text_expression,
  STRUCT(condition AS condition [, temperature AS temperature])
)
```

| 引数 | 説明 |
|---|---|
| `model_name` | 使用するリモートモデルのリソース名 |
| `text_expression` | 評価対象のテキスト列またはサブクエリ |
| `STRUCT(condition AS condition)` | 自然言語で書いた条件文 |

戻り値は BOOL なので、`WHERE AI.IF(...) = TRUE` のような形で直接フィルタに使えます。

---

## 従来のキーワードフィルタとの違い

キーワードフィルタは文字の一致しか見ません。

```sql
-- キーワードフィルタ（「返品」という文字列にしか反応しない）
WHERE inquiry_body LIKE '%返品%'
   OR inquiry_body LIKE '%返金%'
```

「商品が届いたが壊れていて交換してほしい」のような表現は `返品` も `返金` も含まないため、ここにはかかりません。

`AI.IF` を使うと意図で絞り込めます。

```sql
WHERE AI.IF(
  MODEL `your-project.ai_lab.gemini_model`,
  inquiry_body,
  STRUCT('商品の不良・破損・返品・返金・交換に関する問い合わせである' AS condition)
) = TRUE
```

「届いたものが壊れていた」「色が違う」「サイズが合わなかったので送り返したい」のような多様な表現をまとめて拾えます。

---

## 基本的な使い方

### CS問い合わせから返品・不良を抽出する

```sql
SELECT
  inquiry_id,
  received_at,
  inquiry_body
FROM `your-project.your_dataset.raw_inquiries`
WHERE
  DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND AI.IF(
    MODEL `your-project.ai_lab.gemini_model`,
    inquiry_body,
    STRUCT(
      '商品の不良・破損・返品・返金・交換・お届け遅延に関する問い合わせである' AS condition,
      0.0 AS temperature
    )
  ) = TRUE;
```

### GA4イベントデータと組み合わせる

GA4 のサイト内検索クエリから、購買意図の強い検索ワードだけを抽出する例です。

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
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'search'
)
SELECT
  search_term,
  medium,
  COUNT(*) AS search_count
FROM search_events
WHERE
  search_term IS NOT NULL
  AND AI.IF(
    MODEL `your-project.ai_lab.gemini_model`,
    search_term,
    STRUCT(
      '購入意欲が高く、商品を今すぐ買いたい、または購入を強く検討している検索ワードである' AS condition,
      0.0 AS temperature
    )
  ) = TRUE
GROUP BY search_term, medium
ORDER BY search_count DESC
LIMIT 50;
```

:::message
GA4 の `ga_session_id` は `UNNEST(event_params)` で取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## CASE 式での活用

フィルタとしてではなく、分岐のラベル付けに使う方法です。

```sql
SELECT
  review_id,
  product_id,
  review_text,
  CASE
    WHEN AI.IF(
      MODEL `your-project.ai_lab.gemini_model`,
      review_text,
      STRUCT('配送・梱包に関する不満が含まれている' AS condition, 0.0 AS temperature)
    ) = TRUE THEN '配送・梱包'
    WHEN AI.IF(
      MODEL `your-project.ai_lab.gemini_model`,
      review_text,
      STRUCT('商品の品質・素材・耐久性に関する不満が含まれている' AS condition, 0.0 AS temperature)
    ) = TRUE THEN '品質・素材'
    WHEN AI.IF(
      MODEL `your-project.ai_lab.gemini_model`,
      review_text,
      STRUCT('価格や割引・コストパフォーマンスに関する不満が含まれている' AS condition, 0.0 AS temperature)
    ) = TRUE THEN '価格・CP'
    ELSE 'その他'
  END AS complaint_category
FROM `your-project.your_dataset.negative_reviews`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

ただし、各 `AI.IF` がモデル呼び出しを発生させるため、CASE の分岐数に比例してコストが上がります。分類が主目的であれば `AI.CLASSIFY` の方がトークン効率が良いケースがあります。

---

## `AI.IF` と `AI.CLASSIFY` / `AI.GENERATE_BOOL` の使い分け

| 関数 | 向いているケース |
|---|---|
| `AI.IF` | WHERE句や IF 条件として直接使いたい。条件が1〜2個で、記述のシンプルさを優先したい |
| `AI.CLASSIFY` | 複数のラベルに一度に分類したい。ラベルの候補リストが決まっている |
| `AI.GENERATE_BOOL` | プロンプトを自由に設計してBOOLを返したい。STRUCT の書き方が `AI.IF` より柔軟 |

条件が単一で「この行はXか否か」を判定するだけなら `AI.IF` が最もシンプルです。複数の意味軸で同時に仕分けたい場合は `AI.CLASSIFY` を使うと1回のモデル呼び出しで済みます。

---

## コスト管理のポイント

### 処理対象の行数を絞ってから呼ぶ

`AI.IF` はフィルタとして使いますが、サブクエリで先にレコード数を絞り込んでおくことが重要です。テーブル全件に対して直接呼ぶのは避けてください。

```sql
-- 悪い例：全件に対して AI.IF を呼ぶ
SELECT * FROM `your-project.your_dataset.all_inquiries`
WHERE AI.IF(...) = TRUE;

-- 良い例：日付・ステータスで先に絞り込む
WITH recent AS (
  SELECT * FROM `your-project.your_dataset.all_inquiries`
  WHERE DATE(received_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND status = 'open'
)
SELECT * FROM recent
WHERE AI.IF(...) = TRUE;
```

### 結果をマテリアライズして再利用する

同じデータに対して複数のクエリで `AI.IF` を呼ぶ場合は、一度 `CREATE TABLE AS SELECT` で結果を保存し、後続クエリはそのテーブルを参照します。

### condition の文は短く明確に

条件文が長くなるほどトークンが増えます。「〜である」という形で30〜50文字程度に収めると安定します。

---

## よくあるトラブルと対処

### 意図しない行がヒットする

条件文が曖昧な場合に起こります。「問い合わせである」のような広すぎる条件ではなく、「〇〇に関する不満・苦情を含む問い合わせである」のように対象を明確にしてください。

### NULL が混在している

`text_expression` に NULL が含まれると `AI.IF` は NULL を返します。`WHERE text_expression IS NOT NULL` を前段に加えてください。

### temperature のデフォルト値

`temperature` を省略した場合はモデルのデフォルト値が使われます。判定の安定性を重視するなら `0.0` を明示指定してください。

---

## まとめ

- `AI.IF` はWHERE句やCASE式に自然言語の条件を埋め込む関数
- キーワード一致では取りこぼしやすい「意図」ベースのフィルタが書ける
- GA4データとの組み合わせでは `UNNEST(event_params)` と `collected_traffic_source.manual_medium` を使う
- 分類が目的なら `AI.CLASSIFY`、BOOL が必要なら `AI.GENERATE_BOOL` との使い分けを意識する
- コスト対策は「前段フィルタで行数を絞る」「結果をマテリアライズする」の2点が基本

次回（第9回）は `AI.CLASSIFY` を取り上げます。GROUP BY の分類軸を自然言語で定義し、事前に列挙しきれなかったカテゴリを動的に振り分ける方法を解説します。

---

## 参考

- [AI.IF function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_if)
- [Semantic filtering with AI.IF | BigQuery | Google Cloud](https://cloud.google.com/bigquery/docs/ai-functions-overview)
- [Pricing for AI features | BigQuery | Google Cloud](https://cloud.google.com/bigquery/pricing#ai-functions)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ококонала からのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
