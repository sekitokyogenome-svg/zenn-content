---
title: "BigQuery AI機能の料金とクォータ — 動かす前に知るべきコスト構造"
emoji: "💸"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "cost"]
published: false
publish_queue: true
publish_order: 2
---

## はじめに

シリーズ第2回です。前回は BigQuery の AI 機能を3層に整理しました。今回は**動かす前に必ず理解しておくべきコスト構造**を扱います。

なぜ2回目にこれを持ってくるのか。理由は単純で、**この領域で最も多い事故が請求金額の想定外の膨張**だからです。しかもその事故は、たった1行の SQL で起こせます。

```sql
-- これを1000万行のテーブルで実行すると、1000万回モデルが呼ばれる
SELECT AI.GENERATE(('要約して: ', body), ...) FROM `your-project.dataset.reviews`;
```

BigQuery を使い慣れている人ほど危険です。「スキャン量さえ見ておけば大丈夫」という従来の感覚が、**そのままでは通用しない**からです。

:::message
具体的な単価は変動しますし、リージョン・モデルによっても異なります。本記事では**金額そのものではなくコストの構造と測り方**を扱います。実際の単価は必ず公式の料金ページで最新の値を確認してください。
:::

---

## 従来のBigQueryコストとの決定的な違い

### 従来：スキャンしたバイト数で決まる

オンデマンド課金の BigQuery は、**クエリが読んだバイト数**で課金されます。だからこそ我々は以下を叩き込まれてきました。

- `SELECT *` を避ける
- パーティションで日付を絞る
- クラスタリングを効かせる

これらはすべて「**読む量を減らす**」ための技術です。行数そのものは、直接には課金要因ではありませんでした。100万行を読んでも、狭い列だけなら安く済みます。

### AI関数：処理した行数で決まる

AI 関数は違います。**1行ごとにモデルを呼び出し、その入出力トークンに対して課金されます。**

ここで発想の転換が必要です。

| | 効くもの | 効かないもの |
|---|---|---|
| 従来のSQL | 列を絞る、パーティション | 行数を減らしても列が広ければ無意味 |
| AI関数 | **行数を減らす** | 列を絞っても行数が多ければ無意味 |

つまり **`WHERE` で行を減らすことが、そのままコスト削減になる**。これは従来の BigQuery 最適化とは別の軸の話です。

さらに、AI 関数を使ったクエリでは**両方のコストが同時に発生します**。テーブルを読むスキャン料金と、行ごとのモデル呼び出し料金の両方です。

---

## コストを構成する3要素

### 1. 入力トークン

プロンプトとして渡した文字列の量です。**列の値が長いほど高くなります。**

レビュー本文をそのまま渡す場合、1件が100文字なのか2000文字なのかで、10倍以上の差が出ます。長文を扱うときは、前処理で切り詰めることを検討してください。

```sql
-- 本文が長すぎる場合は切り詰めてから渡す
SUBSTR(body, 1, 500)
```

もちろん切り詰めれば精度は落ちるので、そこはトレードオフです。**まず短くして試し、精度が足りなければ伸ばす**という順序が安全です。逆順にすると、精度が足りているのに無駄に払い続ける構成ができあがります。

### 2. 出力トークン

生成された文字列の量です。プロンプトで出力量を制御できます。

```sql
-- 「20文字以内」と明示するだけで出力トークンが抑えられる
'このレビューを20文字以内で要約してください。レビュー: '
```

要約タスクで文字数上限を指定するのは、精度のためだけでなく**コスト管理としても効きます**。

分類タスクなら、そもそも自由文を返させないのが正解です。`AI.GENERATE_BOOL` や `AI.CLASSIFY` を使えば出力は最小限になります。「ポジティブかネガティブか答えてください」と `AI.GENERATE` に聞いて長文の理由を返させるのは、コストの無駄です。

### 3. 行数

最も効くのがこれです。**10万行なら10万回**呼ばれます。

---

## 事故を防ぐ4つの習慣

### 習慣1：必ず LIMIT から始める

新しいプロンプトを試すときは、例外なく1行から始めます。

```sql
-- ❌ いきなり全件
SELECT AI.GENERATE(...) FROM `your-project.dataset.reviews`;

-- ✅ まず1行
SELECT AI.GENERATE(...) FROM `your-project.dataset.reviews` LIMIT 1;

-- ✅ 次に10行で出力のばらつきを確認
SELECT AI.GENERATE(...) FROM `your-project.dataset.reviews` LIMIT 10;
```

:::message alert
`LIMIT` の位置に注意してください。サブクエリで AI 関数を適用してから外側で `LIMIT` を掛けると、**内側では全件処理されます**。`LIMIT` は AI 関数を適用するのと同じ階層、あるいはより内側に置いてください。
:::

```sql
-- ❌ 危険：内側で全件にAI関数が適用される可能性がある
SELECT * FROM (
  SELECT AI.GENERATE(...) AS r FROM `your-project.dataset.reviews`
) LIMIT 10;

-- ✅ 安全：先に絞ってからAI関数を当てる
SELECT AI.GENERATE(...) AS r
FROM (SELECT body FROM `your-project.dataset.reviews` LIMIT 10);
```

### 習慣2：AI関数の前に行を絞る

AI 関数は「絞った後」に当てます。

```sql
-- ✅ 先に条件で絞り込み、対象を最小化してからAIに渡す
WITH target AS (
  SELECT id, body
  FROM `your-project.dataset.reviews`
  WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND LENGTH(body) >= 20          -- 短すぎるものは分析価値が低い
    AND rating <= 3                  -- 低評価のみ分析対象にする
)
SELECT id, AI.GENERATE(('要約: ', body), ...).result AS summary
FROM target;
```

「全件に当てないと意味がない」タスクは、実は多くありません。**分析目的を絞れば対象行も絞れます。**

### 習慣3：結果は必ずテーブルに保存する

前回も書きましたが、最重要なので繰り返します。

```sql
CREATE OR REPLACE TABLE `your-project.mart.reviews_analyzed` AS
SELECT id, AI.GENERATE(...).result AS summary, CURRENT_TIMESTAMP() AS generated_at
FROM target;
```

**AI 関数を含むクエリをビューにしてはいけません。** Looker Studio から参照すると、ダッシュボードが開かれるたびにモデルが呼ばれます。閲覧者10人 × 1日5回 = 50倍のコストです。

### 習慣4：差分だけ処理する

一度処理した行を再処理しないよう、未処理分だけを対象にします。

```sql
INSERT INTO `your-project.mart.reviews_analyzed`
SELECT
  s.id,
  AI.GENERATE(('要約: ', s.body), ...).result AS summary,
  CURRENT_TIMESTAMP() AS generated_at
FROM `your-project.dataset.reviews` s
LEFT JOIN `your-project.mart.reviews_analyzed` t USING (id)
WHERE t.id IS NULL;   -- まだ処理していない行だけ
```

日次バッチにするなら、この形が基本形になります。これを入れておかないと、毎日全件を再生成する構成になり、日を追うごとにコストが増えていきます。

---

## 自分の使用量を測る

推測ではなく実測するための手段を持っておきます。

### 実行したジョブを確認する

```sql
SELECT
  creation_time,
  job_id,
  total_bytes_processed,
  total_slot_ms,
  SUBSTR(query, 1, 200) AS query_preview
FROM `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
  AND UPPER(query) LIKE '%AI.GENERATE%'
ORDER BY creation_time DESC;
```

これで「どのクエリが」「いつ」「どれだけスキャンしたか」が分かります。

:::message
`INFORMATION_SCHEMA.JOBS` はスキャン量やスロット時間を教えてくれますが、**モデル呼び出しのトークン課金そのものを直接返すとは限りません**。モデル側の課金は請求データ側で確認するのが確実です。まずはこのクエリで「AI 関数を含むクエリが、いつ、何回、どれだけの規模で走ったか」を把握するところから始めてください。
:::

### 処理行数を先に見積もる

AI 関数を当てる前に、対象行数を数える癖をつけます。

```sql
-- AI関数を当てる予定の条件で、まず件数を確認する
SELECT COUNT(*) AS target_rows
FROM `your-project.dataset.reviews`
WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND rating <= 3;
```

**この数字がそのままモデル呼び出し回数です。** 数十万という数字が出たら、一度立ち止まって「本当に全部必要か」を考えます。サンプリングで足りるなら以下です。

```sql
-- 1%サンプリングで傾向だけ掴む
WHERE RAND() < 0.01
```

傾向を掴むだけなら全件処理は不要です。**探索フェーズはサンプル、確定してから全件**が定石です。

---

## 予算アラートを先に設定する

技術的な工夫より確実なのが、GCP 側の予算アラートです。**手を動かす前に設定してください。**

```bash
# 予算を作成（金額はご自身の許容範囲で）
gcloud billing budgets create \
  --billing-account=<BILLING_ACCOUNT_ID> \
  --display-name="BigQuery AI experiments" \
  --budget-amount=50USD \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100
```

実験フェーズでは特に、**小さい金額で予算を切っておく**ことをおすすめします。想定外の挙動に早く気づけます。50ドルで警告が来れば「何かおかしい」と分かりますが、設定していなければ月末まで気づきません。

---

## クォータについて

コストとは別に、**クォータ（実行数の上限）**も存在します。大量の行に AI 関数を当てると、レート制限に当たって途中で失敗することがあります。

対策の考え方はコスト対策と同じです。

- **一度に流す行数を分割する**（日次バッチで少しずつ）
- **差分処理にして1回あたりの量を小さく保つ**

つまり、コストのための設計がそのままクォータ対策になります。両方を別々に考える必要はありません。

具体的な上限値はプロジェクトやモデルによって変わるため、大規模に回す前に公式ドキュメントのクォータページを確認し、必要なら引き上げ申請をしてください。

---

## まとめ

- AI 関数は**行数で課金される**。従来のスキャン量課金とは別の軸
- コストは**入力トークン × 出力トークン × 行数**で決まる
- **`LIMIT` の位置に注意**。サブクエリの内側で全件処理される事故が起きる
- **AI 関数の前に `WHERE` で絞る**。これがそのままコスト削減になる
- **結果はテーブルに保存**。ビュー化は閲覧のたびに課金される
- **差分処理**にして、処理済みの行を再処理しない
- **予算アラートは手を動かす前に設定する**

次回は、実際に AI 機能を使うための IAM と Vertex AI 接続のセットアップを扱います。ここは権限まわりでつまずきやすいポイントが集中しているので、丁寧に潰していきます。
