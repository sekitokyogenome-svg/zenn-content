---
title: "BigQueryでAI機能を使うためのIAM・Vertex AI接続セットアップ"
emoji: "🔐"
type: "tech"
topics: ["bigquery", "googlecloud", "iam", "vertexai", "gemini"]
published: false
publish_queue: true
publish_order: 3
---

## はじめに

シリーズ第3回です。前回はコスト構造を扱いました。今回は**実際に AI 機能を使うための権限と接続のセットアップ**です。

この工程は地味ですが、**この領域で最も時間を溶かしやすい場所**でもあります。しかも厄介なことに、エラーメッセージが原因を素直に教えてくれません。「権限がありません」と言われても、どのサービスアカウントのどの権限なのかが分からない、というのが典型です。

そこで本記事では、**構造を理解した上で設定する**という順序を取ります。仕組みが分かっていれば、エラーが出ても自力で切り分けられるようになります。

---

## まず構造を理解する

BigQuery から Gemini を呼ぶとき、**あなたのアカウントが直接 Vertex AI を呼んでいるわけではありません。**

```text
あなた（ユーザー）
  │  ① BigQueryへのクエリ実行権限が必要
  ▼
BigQuery
  │  ② 接続（connection）を経由する
  ▼
接続専用のサービスアカウント   ← ここが盲点
  │  ③ Vertex AIを呼ぶ権限が必要
  ▼
Vertex AI (Gemini)
```

**権限が必要な主体が2つある**、というのがポイントです。

| 主体 | 必要な権限 | よくある誤解 |
|---|---|---|
| あなた | BigQuery のジョブ実行・データ参照 | ここは普段どおりなので問題になりにくい |
| **接続のサービスアカウント** | **Vertex AI の利用** | **見落とされる。自動では付かない** |

自分がプロジェクトのオーナーであっても、**接続のサービスアカウントに権限がなければ動きません**。これが「オーナー権限を持っているのに Permission denied になる」という混乱の正体です。

接続を作ると専用のサービスアカウントが自動生成されますが、**そのサービスアカウントに権限が自動で付与されることはありません**。作成と権限付与は別作業です。

---

## Step 1：API を有効にする

```bash
PROJECT_ID=your-project
LOCATION=asia-northeast1

gcloud config set project "$PROJECT_ID"

gcloud services enable \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  aiplatform.googleapis.com \
  --project="$PROJECT_ID"
```

有効化を確認します。

```bash
gcloud services list --enabled --project="$PROJECT_ID" \
  | grep -E "bigquery|aiplatform"
```

3つとも出てくればOKです。`bigqueryconnection.googleapis.com` が抜けていると接続そのものが作れません。

---

## Step 2：リージョンを決める

**先に決めてください。後から変えるのは面倒です。**

接続・データセット・クエリ実行のリージョンは**揃える必要があります**。バラバラだと動きません。

```text
接続       : asia-northeast1
データセット : asia-northeast1
クエリ実行  : asia-northeast1   ← すべて同じ
```

:::message alert
`asia-northeast1`（東京）で作った接続を、`US` マルチリージョンのデータセットから呼ぶことはできません。既存の GA4 エクスポート先データセットが `US` になっているケースは実際よくあるので、**AI 機能を使う前に既存データセットのリージョンを確認してください**。
:::

確認方法です。

```bash
bq show --format=prettyjson "$PROJECT_ID:your_dataset" | grep -i location
```

既存データセットが `US` で、接続を東京に作りたい場合は、どちらかに揃える必要があります。実務的には**既存データに合わせて接続を作る**のが手戻りが少ないです。データセットのリージョンは後から変更できず、作り直しとデータ移行が必要になるためです。

---

## Step 3：接続を作る

```bash
bq mk --connection \
  --location="$LOCATION" \
  --project_id="$PROJECT_ID" \
  --connection_type=CLOUD_RESOURCE \
  gemini-conn
```

`--connection_type=CLOUD_RESOURCE` が Vertex AI を呼ぶための接続種別です。

作成できたか確認します。

```bash
bq ls --connection --location="$LOCATION" --project_id="$PROJECT_ID"
```

---

## Step 4：接続のサービスアカウントを確認する

ここが本記事の山場です。

```bash
bq show --connection --format=prettyjson \
  "$PROJECT_ID.$LOCATION.gemini-conn"
```

出力の中にこういう部分があります。

```json
{
  "cloudResource": {
    "serviceAccountId": "bqcx-000000000000-xxxx@gcp-sa-bigquery-condel.iam.gserviceaccount.com"
  },
  "name": "projects/000000000000/locations/asia-northeast1/connections/gemini-conn"
}
```

この `serviceAccountId` が、**実際に Vertex AI を呼びに行く主体**です。あなたのアカウントではありません。

スクリプトで取り出すならこうします。

```bash
SA=$(bq show --connection --format=prettyjson \
      "$PROJECT_ID.$LOCATION.gemini-conn" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['cloudResource']['serviceAccountId'])")
echo "$SA"
```

---

## Step 5：サービスアカウントに権限を与える

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/aiplatform.user"
```

**この1コマンドを忘れると、ここまでの作業がすべて無駄になります。**

付与できたか確認します。

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA" \
  --format="table(bindings.role)"
```

`roles/aiplatform.user` が出てくればOKです。

:::message
IAM の変更は**即座に反映されないことがあります**。付与直後にクエリを叩いて失敗しても、慌てて設定を見直す前に1〜2分待って再試行してください。設定は正しいのに反映待ちだった、というケースは珍しくありません。
:::

---

## Step 6：あなた自身の権限を確認する

接続側ばかり注目されますが、実行するあなたの権限も必要です。

| ロール | 用途 |
|---|---|
| `roles/bigquery.jobUser` | クエリを実行する |
| `roles/bigquery.dataViewer` | 対象データを読む |
| `roles/bigquery.dataEditor` | 結果テーブルを作る |
| `roles/bigquery.connectionUser` | **接続を使う** |

最後の `bigquery.connectionUser` が見落とされがちです。プロジェクトのオーナーなら包含されていますが、**権限を絞った運用アカウントで実行する場合は明示的に必要**になります。

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:you@example.com" \
  --role="roles/bigquery.connectionUser"
```

---

## Step 7：疎通確認

最小のクエリで確認します。

```sql
SELECT AI.GENERATE(
  ('「接続テスト成功」とだけ返してください。'),
  connection_id => 'projects/your-project/locations/asia-northeast1/connections/gemini-conn',
  endpoint => 'gemini-2.5-flash'
) AS result;
```

:::message
`connection_id` は**フルパス**で指定します。`projects/<プロジェクトID>/locations/<リージョン>/connections/<接続名>` の形式です。`bq show` の出力に出てくる `name` はプロジェクト**番号**表記になっていることがありますが、プロジェクト**ID**でも指定できます。どちらで書いたか分からなくなったときの混乱を避けるため、プロジェクトIDで統一するのがおすすめです。
:::

結果が返ってくれば、セットアップは完了です。

---

## エラー別の切り分け

実際に遭遇するエラーと、その原因を対応させておきます。

### `Permission denied` / `403`

**まず疑うのは接続のサービスアカウントです。** あなたの権限ではありません。

```bash
# 接続のSAに aiplatform.user が付いているか
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA" \
  --format="table(bindings.role)"
```

付いているのに失敗する場合は、反映待ちの可能性があるので少し待ちます。

### `Not found: Connection ...`

`connection_id` のパスが誤っています。以下を確認します。

- リージョン部分が接続を作ったリージョンと一致しているか
- 接続名のスペルが合っているか
- そもそも接続が存在するか（`bq ls --connection --location=...`）

### `Dataset ... not found in location ...` / リージョン関連

接続とデータセットのリージョンが食い違っています。両方のリージョンを確認してください。

```bash
bq show --format=prettyjson "$PROJECT_ID:your_dataset" | grep -i location
bq ls --connection --location="$LOCATION" --project_id="$PROJECT_ID"
```

### `API has not been used in project ... before or it is disabled`

`aiplatform.googleapis.com` が有効になっていません。Step 1 に戻ります。

### 引数名やモデル名のエラー

関数のシグネチャや利用可能なモデル名は更新が入ります。**公式リファレンスで現行の仕様を確認してください。** 古い記事のコードをそのままコピーして動かない、というのはこの領域では日常的に起こります。

---

## 環境を分けるなら

実務では、実験用と本番用を分けたくなります。接続はリージョンごと・用途ごとに複数作れます。

```bash
# 実験用
bq mk --connection --location="$LOCATION" --project_id="$PROJECT_ID" \
  --connection_type=CLOUD_RESOURCE gemini-conn-dev

# 本番用
bq mk --connection --location="$LOCATION" --project_id="$PROJECT_ID" \
  --connection_type=CLOUD_RESOURCE gemini-conn-prod
```

それぞれに別のサービスアカウントが割り当てられるので、**権限とコストを分離できます**。本番用の接続を使えるユーザーを絞れば、意図しない大量実行の抑止にもなります。

実験用は緩く、本番用は厳しく、という運用ができるのがこの分離の利点です。

---

## セットアップ確認スクリプト

毎回手で確認するのは面倒なので、まとめておきます。

```bash
#!/bin/bash
set -euo pipefail

PROJECT_ID=your-project
LOCATION=asia-northeast1
CONN=gemini-conn

echo "=== API有効化 ==="
gcloud services list --enabled --project="$PROJECT_ID" \
  | grep -E "bigquery\.|bigqueryconnection|aiplatform" || echo "  ⚠ 不足あり"

echo "=== 接続 ==="
bq ls --connection --location="$LOCATION" --project_id="$PROJECT_ID" || echo "  ⚠ 接続なし"

echo "=== 接続のサービスアカウント ==="
SA=$(bq show --connection --format=prettyjson "$PROJECT_ID.$LOCATION.$CONN" \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['cloudResource']['serviceAccountId'])")
echo "  $SA"

echo "=== SAのロール ==="
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA" \
  --format="value(bindings.role)" | sed 's/^/  /'
```

`roles/aiplatform.user` が出力に含まれていれば準備完了です。

---

## まとめ

- **権限が必要な主体は2つ**。あなたと、接続専用のサービスアカウント
- **接続を作っただけでは動かない**。SA への `roles/aiplatform.user` 付与までがワンセット
- **リージョンは最初に決めて全部揃える**。既存データセットのリージョンを先に確認する
- **`bigquery.connectionUser`** は権限を絞った運用アカウントで必要になる
- IAM 反映には**時間差がある**。直後の失敗は少し待って再試行
- 実験用と本番用で**接続を分ける**と、権限とコストを分離できる

次回は Knowledge Catalog を扱います。エージェントの回答精度を左右する、地味だが最も効く部分です。
