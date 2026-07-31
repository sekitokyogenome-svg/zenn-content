---
title: "最初の一歩：AI.GENERATEを1クエリ動かしてみる"
emoji: "🚀"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "sql"]
published: false
publish_queue: true
publish_order: 5
---

## はじめに

シリーズ第5回です。前回までで全体像・料金・接続設定・Knowledge Catalog を扱いました。今回はいよいよ**実際に AI 関数を1本動かします**。

この記事のゴールは明確です。**自分のプロジェクトで `AI.GENERATE` が返ってくるところまで到達する**こと。それだけです。

機能の全体像を眺めているだけだと、いつまでも「知っている」止まりになります。1行でも自分の環境で動くと、そこから先の理解が一気に進みます。

:::message
AI 関数は**処理した行ごとにモデルを呼び出して課金されます**。この記事の手順は必ず `LIMIT` を付けた小さなデータで進めてください。いきなり本番テーブルの全件に当てないでください。
:::

---

## Step 0：前提の確認

進める前に、環境が整っているかを確認します。ここを飛ばして「動かない」と悩む時間が一番もったいないので、先に潰します。

```bash
PROJECT_ID=your-project
LOCATION=asia-northeast1   # 接続とデータセットのリージョンは揃える

# 1. 認証されているか
gcloud auth list

# 2. プロジェクトが正しいか
gcloud config set project "$PROJECT_ID"

# 3. 必要なAPIが有効か
gcloud services list --enabled --project="$PROJECT_ID" \
  | grep -E "bigquery|aiplatform|bigqueryconnection"
```

有効になっていなければ有効化します。

```bash
gcloud services enable \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  aiplatform.googleapis.com \
  --project="$PROJECT_ID"
```

:::message alert
**リージョンは最初に決めて揃えてください。** 接続・データセット・モデルのリージョンが食い違うと、エラーの原因として最も分かりにくい部類のものになります。後から直すのは面倒なので、最初に決め打ちするのが正解です。
:::

---

## Step 1：Vertex AI への接続を作る

BigQuery から Gemini を呼ぶには、**BigQuery と Vertex AI をつなぐ接続（connection）**が必要です。

```bash
bq mk --connection \
  --location="$LOCATION" \
  --project_id="$PROJECT_ID" \
  --connection_type=CLOUD_RESOURCE \
  gemini-conn
```

作成した接続には**専用のサービスアカウント**が自動で割り当てられます。これに Vertex AI を呼ぶ権限を与える必要があります。まずサービスアカウントを確認します。

```bash
bq show --connection --format=prettyjson \
  "$PROJECT_ID.$LOCATION.gemini-conn"
```

出力の `cloudResource.serviceAccountId` を控えて、権限を付与します。

```bash
SA="<上で確認したserviceAccountId>"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/aiplatform.user"
```

:::message
**ここが最頻出のつまずきポイントです。** 接続を作っただけでは動きません。接続のサービスアカウントに `roles/aiplatform.user` を付けるまでがワンセットです。権限の反映には少し時間がかかることがあるので、直後に失敗した場合は1〜2分待って再試行してください。
:::

---

## Step 2：作業用データセットとサンプルデータを用意する

本番データにいきなり当てないための、実験用の箱を作ります。

```bash
bq --location="$LOCATION" mk --dataset "$PROJECT_ID:ai_lab"
```

サンプルとして、EC のレビューを模した小さなテーブルを作ります。**5行だけ**です。

```sql
CREATE OR REPLACE TABLE `your-project.ai_lab.sample_reviews` AS
SELECT * FROM UNNEST([
  STRUCT(1 AS id, '届くのが早くて助かりました。梱包も丁寧でした。' AS body),
  STRUCT(2, 'サイズが思っていたより小さかった。説明にもう少し詳しく書いてほしい。'),
  STRUCT(3, '不良品が届きました。交換対応をお願いしたいです。'),
  STRUCT(4, 'リピート購入です。安定した品質で満足しています。'),
  STRUCT(5, '価格の割に質が良い。ただ色味が写真と少し違いました。')
]);
```

まず中身を確認します。

```sql
SELECT * FROM `your-project.ai_lab.sample_reviews`;
```

ここまでは AI を使っていません。**AI を呼ぶ前に、対象データが想定通りかを必ず目視する**のは基本動作です。おかしなデータに AI を当てて、おかしな結果に悩むのは時間の無駄なので。

---

## Step 3：最初の AI.GENERATE

いよいよ本番です。まず**1行だけ**で試します。

```sql
SELECT
  id,
  body,
  AI.GENERATE(
    ('このレビューを一言で要約してください。20文字以内。レビュー: ', body),
    connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
    endpoint => 'gemini-2.5-flash'
  ) AS result
FROM `your-project.ai_lab.sample_reviews`
WHERE id = 1;
```

:::message
関数の引数名やモデル名（`endpoint`）は更新が入る領域です。エラーになった場合は、公式リファレンスで現行のシグネチャと利用可能なモデル名を確認してください。**最初の1回だけは、ドキュメントを開きながら進めるのが結局は速い**です。
:::

`AI.GENERATE` の戻り値は **STRUCT** です。生成テキストそのものを取り出すには、フィールドを指定します。返り値の構造は、まず一度そのまま `SELECT` して目で確認するのが確実です。

```sql
-- STRUCTの中身を確認する
SELECT AI.GENERATE(
         ('こんにちは、と挨拶を返してください。'),
         connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
         endpoint => 'gemini-2.5-flash'
       ) AS raw_result;
```

構造が分かったら、必要なフィールドだけ取り出す形に整えます。

```sql
SELECT
  id,
  body,
  AI.GENERATE(
    ('このレビューを一言で要約してください。20文字以内。レビュー: ', body),
    connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
    endpoint => 'gemini-2.5-flash'
  ).result AS summary
FROM `your-project.ai_lab.sample_reviews`
WHERE id = 1;
```

**ここで結果が返ってきたら、この記事の目的は達成です。** 接続・権限・リージョン・シグネチャがすべて噛み合ったことの証明になります。

---

## Step 4：5行に広げる

1行で通ったら、`WHERE` を外して5行に広げます。

```sql
SELECT
  id,
  body,
  AI.GENERATE(
    ('このレビューを一言で要約してください。20文字以内。レビュー: ', body),
    connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
    endpoint => 'gemini-2.5-flash'
  ).result AS summary
FROM `your-project.ai_lab.sample_reviews`
ORDER BY id;
```

**5行だから5回モデルが呼ばれます。** この感覚を最初に体で覚えておくのが大事です。100万行のテーブルに同じことをすれば100万回呼ばれます。

---

## Step 5：結果を保存する（重要）

AI 関数の結果は、**必ずテーブルに保存してから使ってください**。

```sql
CREATE OR REPLACE TABLE `your-project.ai_lab.sample_reviews_summarized` AS
SELECT
  id,
  body,
  AI.GENERATE(
    ('このレビューを一言で要約してください。20文字以内。レビュー: ', body),
    connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
    endpoint => 'gemini-2.5-flash'
  ).result AS summary,
  CURRENT_TIMESTAMP() AS generated_at
FROM `your-project.ai_lab.sample_reviews`;
```

以降の分析やダッシュボードは、この**保存済みテーブル**を参照します。

これを徹底しないと何が起きるか。AI 関数を含むクエリをそのままビューにして Looker Studio から参照すると、**ダッシュボードが開かれるたびにモデルが呼ばれます**。閲覧者が10人いれば10倍です。AI 関数のコスト事故は、だいたいこのパターンで起きます。

`generated_at` を入れているのは、いつ生成した結果なのかを後から追えるようにするためです。モデルが更新されると出力が変わるので、生成時刻は残しておく価値があります。

---

## つまずいたときの切り分け順

エラーが出たとき、上から順に確認すると早く原因に辿り着けます。

**1. 権限エラー（Permission denied / 403系）**
接続のサービスアカウントに `roles/aiplatform.user` が付いているか。付けた直後なら1〜2分待つ。

**2. 接続が見つからない（Not found: Connection）**
`connection_id` のフルパスが正しいか。`projects/<PROJECT>/locations/<LOCATION>/connections/<NAME>` の形式です。プロジェクト番号ではなくプロジェクトIDを使っているかも確認。

**3. リージョン不一致**
接続・データセット・クエリ実行のリージョンが揃っているか。`asia-northeast1` で作った接続を US のデータセットから呼ぶことはできません。

**4. 引数名・モデル名のエラー**
リファレンスで現行のシグネチャを確認する。この領域は更新が入るため、古い記事のコードをそのまま使うと失敗します（この記事も含めて）。

**5. API が無効**
`aiplatform.googleapis.com` が有効か。Step 0 に戻る。

---

## まとめ

- **接続の作成＋サービスアカウントへの `roles/aiplatform.user` 付与**がワンセット。ここが最頻出のつまずき
- **リージョンは最初に決めて全部揃える**
- **必ず1行から始める**。`WHERE id = 1` で通してから広げる
- `AI.GENERATE` の戻り値は **STRUCT**。まず生のまま `SELECT` して構造を確認する
- **結果はテーブルに保存する**。ビューにして参照すると閲覧のたびに課金される

次回は `AI.GENERATE` の引数を掘り下げ、出力を安定させるための指定方法を扱います。今回は「動いた」で十分です。ここまで来れば、あとは対象を広げていくだけなので。
