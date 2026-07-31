---
title: "ML.GENERATE_TEXTからAI.*関数へ — 何が変わり、どう移行するか"
emoji: "🔄"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "bigqueryml"]
published: false
publish_queue: true
publish_order: 6
---

## はじめに

シリーズ第6回、フェーズ1の最終回です。

BigQuery で LLM を使う方法を調べると、**2つの世代の情報が混在**しています。

- 古い世代：`CREATE MODEL` でリモートモデルを作り、`ML.GENERATE_TEXT` で呼ぶ
- 新しい世代：`AI.GENERATE` などの AI 関数を直接呼ぶ

ネット上の記事は両方が混ざったまま存在しており、どちらを見ているのか意識しないと混乱します。「記事のとおりにやったのに動かない」の原因が、実は世代違いだった、というのはよくある話です。

今回はこの2つの違いを整理し、既存資産がある場合の移行の考え方を扱います。

---

## 何が違うのか

### 従来：モデルオブジェクトを作る

`ML.GENERATE_TEXT` を使うには、まず **BigQuery 上にモデルオブジェクトを作る**必要がありました。

```sql
-- ① リモートモデルを作成する
CREATE OR REPLACE MODEL `your-project.ai_lab.gemini_model`
REMOTE WITH CONNECTION `your-project.asia-northeast1.gemini-conn`
OPTIONS (ENDPOINT = 'gemini-2.0-flash');
```

```sql
-- ② そのモデルを指定して呼ぶ
SELECT *
FROM ML.GENERATE_TEXT(
  MODEL `your-project.ai_lab.gemini_model`,
  (SELECT id, CONCAT('要約してください: ', body) AS prompt
   FROM `your-project.ai_lab.sample_reviews`),
  STRUCT(0.2 AS temperature, 100 AS max_output_tokens)
);
```

**2段構え**です。モデルを作ってから、それを参照します。

### 現在：関数を直接呼ぶ

AI 関数は**モデルオブジェクトの作成が不要**です。接続とエンドポイントを直接指定します。

```sql
SELECT
  id,
  AI.GENERATE(
    ('要約してください: ', body),
    connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
    endpoint => 'gemini-2.5-flash'
  ).result AS summary
FROM `your-project.ai_lab.sample_reviews`;
```

**1段**になりました。

### 比較

| | `ML.GENERATE_TEXT` | AI 関数 |
|---|---|---|
| モデルオブジェクト | **必要**（`CREATE MODEL`） | 不要 |
| 呼び出し形式 | テーブル関数（`FROM ML.GENERATE_TEXT(...)`） | **スカラー関数**（`SELECT` の中に書ける） |
| 戻り値 | 行セット | STRUCT |
| `WHERE` 句での利用 | しにくい | `AI.IF` で可能 |
| モデル管理 | BigQuery 上のオブジェクトとして管理 | クエリ内で指定 |

**スカラー関数になったこと**が実務上いちばん大きい変化です。テーブル関数だった頃は、AI の呼び出しがクエリ構造を規定していました。今は普通の関数と同じように、`SELECT` の中にも `WHERE` の中にも書けます。

```sql
-- こういう書き方ができるようになった
SELECT id, body
FROM `your-project.ai_lab.sample_reviews`
WHERE AI.IF('このレビューは配送に関する不満を含むか', body);
```

`ML.GENERATE_TEXT` の時代には、いったん全件を生成して、その結果を外側でフィルタするしかありませんでした。**当てる前に絞れる**ようになったのは、コスト面でも意味があります。

---

## どちらを使うべきか

**新規に書くなら AI 関数**です。理由は明快で、記述量が少なく、SQL に自然に馴染み、マネージド関数（`AI.IF` / `AI.CLASSIFY` / `AI.SCORE`）が使えるからです。

ただし `ML.GENERATE_TEXT` が即座に不要になるわけではありません。以下のような場合は残す判断もあります。

- **既に本番で安定稼働している**。動いているものを触るリスクの方が大きい
- **モデルをオブジェクトとして一元管理したい**。どのモデルを使っているかを BigQuery 側で把握したいケース
- **細かいパラメータ制御が必要**。`temperature` などを明示的に調整している場合

3つ目は補足が必要です。AI 関数の中でも**マネージド関数（`AI.IF` / `AI.CLASSIFY` / `AI.SCORE`）はパラメータ調整を BigQuery 側が引き受けます**。安定した結果が得やすい反面、細かい制御はできません。制御が要るなら `AI.GENERATE` を使うか、`ML.GENERATE_TEXT` を残すことになります。

---

## 移行の手順

既存の `ML.GENERATE_TEXT` 資産がある場合の進め方です。

### Step 1：使用箇所を洗い出す

まず現状を把握します。

```sql
SELECT
  creation_time,
  job_id,
  user_email,
  SUBSTR(query, 1, 300) AS query_preview
FROM `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_type = 'QUERY'
  AND UPPER(query) LIKE '%ML.GENERATE_TEXT%'
ORDER BY creation_time DESC;
```

作成済みのモデルも確認します。

```sql
SELECT
  model_name,
  model_type,
  creation_time
FROM `your-project.ai_lab.INFORMATION_SCHEMA.MODELS`
ORDER BY creation_time DESC;
```

dbt や Dataform で管理している場合は、リポジトリを検索した方が早いです。

```bash
grep -rn "ML.GENERATE_TEXT" models/ --include="*.sql"
```

### Step 2：並行稼働で結果を比較する

**いきなり差し替えないでください。** 出力が変わる可能性があります。

同じ入力に対して両方を実行し、結果を突き合わせます。

```sql
CREATE OR REPLACE TABLE `your-project.ai_lab.migration_compare` AS
WITH src AS (
  SELECT id, body
  FROM `your-project.ai_lab.sample_reviews`
  LIMIT 50                          -- まず小さく比較する
),
old_way AS (
  SELECT id, ml_generate_text_result AS old_result
  FROM ML.GENERATE_TEXT(
    MODEL `your-project.ai_lab.gemini_model`,
    (SELECT id, CONCAT('要約してください: ', body) AS prompt FROM src),
    STRUCT(0.2 AS temperature, 100 AS max_output_tokens)
  )
),
new_way AS (
  SELECT
    id,
    AI.GENERATE(
      ('要約してください: ', body),
      connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
      endpoint => 'gemini-2.5-flash'
    ).result AS new_result
  FROM src
)
SELECT s.id, s.body, o.old_result, n.new_result
FROM src s
LEFT JOIN old_way o USING (id)
LEFT JOIN new_way n USING (id);
```

比較したうえで、差分の傾向を見ます。

```sql
SELECT
  COUNTIF(old_result IS NULL) AS old_failed,
  COUNTIF(new_result IS NULL) AS new_failed,
  COUNTIF(old_result != new_result) AS differs,
  COUNT(*) AS total
FROM `your-project.ai_lab.migration_compare`;
```

:::message
**出力が完全一致することは期待しないでください。** 生成モデルは同じ入力でも揺れます。見るべきは「一致するか」ではなく、**「後工程で困る差が出ていないか」**です。要約の言い回しが変わるのは許容できても、分類ラベルが変わるなら後工程が壊れます。
:::

### Step 3：後工程への影響を確認する

生成結果を使っている下流を確認します。

- ダッシュボードの表示が壊れないか
- 分類結果でフィルタしている箇所はないか
- 文字数の前提を置いていないか

特に**分類・判定系は影響が大きい**です。ラベル文字列が微妙に変わるだけで、`WHERE category = 'クレーム'` のような条件が空振りします。

この機会に、**そもそも自由文で分類させるのをやめて `AI.CLASSIFY` に置き換える**方が筋が良いことも多いです。分類軸を明示的に定義でき、出力が安定します。

### Step 4：切り替えとクリーンアップ

問題がなければ切り替えます。切り替え後、しばらく様子を見てからモデルオブジェクトを削除します。

```sql
-- 十分な期間、新方式で安定してから実行する
DROP MODEL IF EXISTS `your-project.ai_lab.gemini_model`;
```

**すぐには消さないでください。** 切り戻しが必要になる可能性があります。モデルオブジェクト自体は保持コストがほぼ無いので、急いで消す理由はありません。

---

## 移行時のよくある落とし穴

**プロンプトの組み立て方が違う**
`ML.GENERATE_TEXT` はサブクエリで `prompt` という名前の列を作る必要がありました。AI 関数は引数に直接渡します。移行時にここの変換を機械的にやると、`CONCAT` の組み立てを間違えやすいので注意してください。

**戻り値の取り出し方が違う**
`ML.GENERATE_TEXT` は行セットを返し、`ml_generate_text_result` のような列に結果が入ります。AI 関数は STRUCT を返します。**まず生のまま `SELECT` して構造を確認する**のが確実です。

**リージョンと接続は共通**
ここは変わりません。既に `ML.GENERATE_TEXT` が動いているなら、接続とその権限は流用できます。前回の設定作業をやり直す必要はありません。

**コスト構造も変わらない**
どちらも行ごとにモデルを呼びます。第2回で扱ったコスト管理の原則（`LIMIT` から始める、前段で絞る、結果を保存する、差分処理する）は、そのまま適用されます。

---

## フェーズ1のまとめ

ここまでの6回で、以下が揃いました。

| 回 | 内容 |
|---|---|
| 第1回 | 全体像。基盤・SQL関数・エージェントの3層構造 |
| 第2回 | コスト構造。行数課金と事故を防ぐ4つの習慣 |
| 第3回 | IAM と接続。権限が必要な主体は2つある |
| 第4回 | Knowledge Catalog。文脈を供給しないと精度は上がらない |
| 第5回 | 最初の1クエリ。`AI.GENERATE` を動かす |
| 第6回 | 世代の違いと移行 |

準備は完了です。次回からフェーズ2に入り、AI SQL 関数を1つずつ掘り下げていきます。まずは `AI.GENERATE` の完全解説から始めます。

---

## まとめ

- BigQuery の LLM 利用には**2つの世代**があり、ネット上の情報は混在している
- `ML.GENERATE_TEXT` は**モデルオブジェクトが必要なテーブル関数**、AI 関数は**不要なスカラー関数**
- スカラー関数になったことで **`WHERE` 句で使える**ようになり、当てる前に絞れる
- **新規は AI 関数**。既存の安定稼働システムは急いで移行しなくてよい
- 移行は**並行稼働で比較してから**。出力の完全一致は期待しない
- **分類・判定系は影響が大きい**。この機会に `AI.CLASSIFY` への置き換えを検討する価値がある
