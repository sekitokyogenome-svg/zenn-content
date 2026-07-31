---
title: "BigQueryのAIエージェント全体像2026 — 何があって、どう使い分けるのか"
emoji: "🗺️"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "gemini", "dataengineering"]
published: false
publish_queue: true
publish_order: 1
---

## はじめに

BigQuery に AI 関連の機能が一気に増えました。`AI.GENERATE`、Conversational Analytics、Data Engineering Agent、MCP サーバー、Knowledge Catalog……名前は目に入るものの、**どれが何をするもので、自分の仕事のどこに刺さるのか**が整理されていない、という状態の方は多いと思います。私もそうでした。

この記事はシリーズ全50回の第1回として、**BigQuery の AI 機能を地図にする**ことを目的にします。個々の使い方は次回以降で扱うので、ここでは「何があるか」「どう選ぶか」に絞ります。

:::message
機能の GA / プレビュー状況は変化が速い領域です。本記事は 2026年7月時点で確認できた情報に基づいています。実際に採用を決める際は、必ず公式ドキュメントで最新のステータスとリージョン対応を確認してください。
:::

---

## 大きく3階層で捉える

細かい機能名を並べる前に、構造を掴むのが先です。BigQuery の AI 機能は、**役割の違う3つの層**に分けると一気に見通しが良くなります。

```text
┌─────────────────────────────────────────────┐
│ 層3：エージェント                              │
│   人間の代わりに「手順を考えて実行する」        │
│   Conversational Analytics / Data Engineering │
│   Agent / Data Science Agent / Data Prep      │
├─────────────────────────────────────────────┤
│ 層2：AI SQL関数                               │
│   SQLの中で「1行ごとにモデルを呼ぶ」            │
│   AI.GENERATE / AI.CLASSIFY / AI.IF /         │
│   AI.SCORE / AI.FORECAST / AI.EMBED           │
├─────────────────────────────────────────────┤
│ 層1：基盤                                     │
│   文脈と接続を供給する                          │
│   Knowledge Catalog / Vertex AI接続 /          │
│   ObjectRef / ベクトルインデックス / MCP        │
└─────────────────────────────────────────────┘
```

**層2（AI SQL関数）は「道具」**で、あなたが SQL を書いて明示的に呼びます。処理は決定論的な構造の中に埋め込まれます。

**層3（エージェント）は「作業者」**で、目的を伝えると手順自体を組み立てます。便利ですが、何をするか完全には事前に分かりません。

**層1（基盤）は両者の土台**です。ここが弱いとエージェントは的外れな答えを返し、AI 関数はコストばかり食います。地味ですが、実は最も効きます。

この3層のどこの話をしているのかを意識すると、公式ドキュメントも読みやすくなります。

---

## 層2：AI SQL関数 — SQLの中でモデルを呼ぶ

普段 BigQuery で SQL を書いている人にとって、最も参入しやすいのがここです。

### 生成系

| 関数 | 何をするか |
|---|---|
| `AI.GENERATE` | プロンプトに対して生成結果を返す。戻り値は STRUCT |
| `AI.GENERATE_TABLE` | 列定義を指定して、テーブルとして構造化結果を受け取る |
| `AI.GENERATE_BOOL` | true / false を返す |
| `AI.GENERATE_INT` | 整数を返す |
| `AI.GENERATE_DOUBLE` | 浮動小数点数を返す |

`AI.GENERATE` が STRUCT を返すのに対し、`AI.GENERATE_TABLE` は**自分で定義した列構成のテーブル**を返します。非構造化テキストから「商品名・価格・カテゴリ」を抜き出して表にする、といった用途はこちらが素直です。

型付きの `AI.GENERATE_BOOL` 系は、結果を後段の SQL でそのまま計算に使えるのが利点です。文字列で返ってきた "true" をパースする、という無駄がなくなります。

### 分析系（マネージドAI関数）

ここが個人的に「SQL の書き方そのものが変わる」と感じた部分です。

| 関数 | 使う場所 | 何ができるか |
|---|---|---|
| `AI.IF` | `WHERE` / `ON` | 意味に基づいてフィルタ・結合する |
| `AI.CLASSIFY` | `GROUP BY` | 自然言語で定義した軸で分類する |
| `AI.SCORE` | `ORDER BY` | 自然言語の基準でランク付けする |

従来、「クレームっぽい問い合わせだけ抽出する」には、キーワードリストを作って `LIKE` を並べるしかありませんでした。`AI.IF` はこれを `WHERE AI.IF('この問い合わせはクレームか', text)` のような形で表現できます。

重要なのは、これらが **マネージド**である点です。プロンプト設計・モデル選択・パラメータ調整を BigQuery 側が引き受けます。自分でプロンプトを書き込む `AI.GENERATE` に比べ、結果が安定しやすい代わりに細かい制御は効きません。**まずマネージド関数で試し、要件に合わなければ `AI.GENERATE` に降りる**、という順序が実務的です。

### 予測系

`AI.FORECAST` は、Google Research の事前学習済みモデル **TimesFM** を使います。ポイントは**モデルを自分で作らなくてよい**ことです。

従来の `CREATE MODEL ... ARIMA_PLUS` は、学習させて評価して、という手順が必要でした。`AI.FORECAST` は時系列データを渡すだけで予測が返ります。EC の売上予測のような「そこまで作り込まなくていいが、傾向は掴みたい」用途では、こちらの方が圧倒的に早く着地します。

### 埋め込み・ベクトル検索

| 機能 | 役割 |
|---|---|
| `AI.EMBED` / `AI.GENERATE_EMBEDDING` | テキストや画像をベクトル化する |
| ベクトルインデックス | 大量ベクトルの近似最近傍検索を高速化する |
| 自律型エンベディング生成 | 新規データ投入時にベクトルを自動生成・同期する |

「類似商品レコメンド」「表記ゆれに強い検索」はこの系統です。特に**自律型エンベディング生成**は、データが増えるたびに埋め込みを作り直すパイプラインを自前で組む手間を消してくれるので、運用負荷が大きく変わります。

---

## 層3：エージェント — 手順ごと任せる

### Conversational Analytics（データエージェント）

自然言語でデータに問いかけると、エージェントが SQL を組み立てて答えます。**データソースと、用途ごとの指示（instructions）のセット**としてエージェントを定義するのが特徴です。

ここが肝で、単なる Text-to-SQL とは違います。「当社では『アクティブユーザー』を過去28日以内に購入した人と定義する」といった**業務固有の文脈を指示として持たせられる**ため、社内の定義に沿った答えを返せます。

社内向けに「GA4 の数字を誰でも聞ける窓口」を作る、といった使い方に向きます。

### Data Engineering Agent

パイプラインの構築・改修・移行・トラブルシュートを担当します。自然言語で「このCSVを読み込んで日次で集計テーブルを作って」と言えばパイプラインを生成し、既存のパイプラインの修正もできます。BigQuery Pipelines と Dataform で利用できます。

Knowledge Catalog と連携して文脈を参照するため、層1の整備が効いてくる代表例です。

### Data Science Agent

データ読み込み・特徴量エンジニアリング・モデル学習・評価までをプロンプトで回します。層2の AI 関数が「1つの処理」を担うのに対し、こちらは**一連のワークフロー**を担当します。

### Data Preparation Agent

データのクレンジング・整形を任せる担当です。分析の前工程、いわゆる「データの掃除」に時間を溶かしている人ほど効果が大きい領域です。

---

## 層1：基盤 — ここが効く

### Knowledge Catalog

Gemini ベースのデータカタログで、**構造化・非構造化データからセマンティクスを自動抽出してコンテキストグラフを作る**ものです。エージェントはこれを参照することで、社内の「正」に基づいた回答ができるようになり、ハルシネーションが減ります。

エージェントの回答精度に不満が出たとき、多くの場合の原因はモデルではなくここです。**テーブル名とカラム名だけ渡されたエージェントが、業務の意味を推測できるはずがない**、というのは考えてみれば当然の話です。

### MCP（Model Context Protocol）

BigQuery には**マネージドのリモート MCP サーバー**があり、AI アプリケーションや LLM から BigQuery に接続できます。データセット・テーブルの一覧取得、スキーマ参照、自然言語からの SQL 生成・実行といったツールが標準で提供されます。

さらに **MCP Toolbox for Databases** を使うと、自分で定義したクエリをツールとしてエージェントに渡せます。「このパラメータを受け取ってこの集計を返す」という業務ロジックを、エージェントから安全に呼べる形で公開できるわけです。

これは Claude Code のような外部のエージェントから BigQuery を触る場合の主要な経路になります。

### ObjectRef

画像・PDF などの非構造化データを、SQL および Python から扱えるようにするデータ型です。オブジェクトテーブルの上に構築されており、これによって「商品画像を SQL から直接扱う」ようなことが可能になります。

---

## どれを使うべきか：判断の指針

機能が多いので、迷ったときの指針を置いておきます。

| やりたいこと | 使うもの |
|---|---|
| 大量の行を一括で分類・抽出・生成したい | 層2：AI SQL関数 |
| 分類軸や基準を自然言語で決めたい | `AI.CLASSIFY` / `AI.IF` / `AI.SCORE` |
| 非構造化テキストを表にしたい | `AI.GENERATE_TABLE` |
| とりあえず時系列を予測したい | `AI.FORECAST` |
| 類似検索・レコメンドを作りたい | 埋め込み＋ベクトル検索 |
| 非エンジニアが自分で数字を見られるようにしたい | 層3：Conversational Analytics |
| パイプラインの構築・改修を早くしたい | 層3：Data Engineering Agent |
| 外部のAIツール（Claude Code等）から触りたい | 層1：MCP |
| エージェントの回答精度が上がらない | 層1：Knowledge Catalog |

判断に迷ったときの原則はひとつです。

**処理が定型で、件数が多く、再現性が要るなら層2（SQL関数）。探索的で、手順自体を任せたいなら層3（エージェント）。**

バッチ処理に層3を使うと、コストも実行時間も再現性も割に合いません。逆に、一度きりの調査に層2で作り込むのは時間の無駄です。ここを取り違えると、どちらの機能も「使えない」という印象になります。

---

## コストについての注意

具体的な料金体系は次回で扱いますが、方向性だけ先に共有します。

AI 関数は**処理した行ごとにモデルを呼ぶ**ため、`SELECT AI.GENERATE(...) FROM 巨大テーブル` は文字通りその行数だけ課金されます。BigQuery のスキャン量課金の感覚とは別軸のコストが乗る、という点は最初に理解しておくべきです。

実務では以下が基本動作になります。

- **必ず `LIMIT` を付けて試す。** いきなり全件流さない
- **AI 関数は前段で行を絞ってから当てる。** `WHERE` で対象を減らしてから AI に渡す
- **結果はテーブルに保存する。** 同じ行に何度もモデルを呼ばない

3つ目が特に重要です。AI 関数の呼び出し結果はマテリアライズして再利用する、という設計を最初から入れておかないと、ダッシュボードを開くたびに課金される構成ができあがります。

---

## このシリーズで扱うこと

全50回を5つのフェーズに分けています。

| フェーズ | 内容 | 回数 |
|---|---|---|
| 1 | 全体像と準備（料金・IAM・Knowledge Catalog・最初の1クエリ） | 6 |
| 2 | AI SQL関数の徹底解説（生成・分類・埋め込み・予測・検証） | 14 |
| 3 | エージェント（Conversational Analytics / DE / DS / MCP / ADK） | 12 |
| 4 | EC実務への適用（GA4・レビュー・商品・広告・予測） | 12 |
| 5 | 運用と品質（ハルシネーション対策・コスト監視・dbt・セキュリティ） | 6 |

順番に読めば「触ったことがない」から「本番で運用する」まで繋がる構成にしています。特にフェーズ4は、普段の GA4×BigQuery の仕事にそのまま接続する内容になる予定です。

---

## まとめ

- BigQuery の AI 機能は **基盤・SQL関数・エージェント の3層**で捉えると整理できる
- **層2（AI SQL関数）が最も入りやすい**。既存の SQL スキルがそのまま活きる
- **層3（エージェント）は手順ごと任せる**もの。定型バッチには向かない
- **層1（Knowledge Catalog / MCP）が精度を左右する**。ここを飛ばすとエージェントは的外れになる
- AI 関数は**行数で課金される**。`LIMIT` と事前フィルタと結果の保存が基本動作

次回は、動かす前に知っておくべき料金とクォータの構造を扱います。ここを理解しないまま全件に AI 関数を当てて請求で驚く、というのがこの領域で最もありがちな事故なので、先に潰しておきます。

## 参考

- [Introduction to AI in BigQuery | Google Cloud Documentation](https://docs.cloud.google.com/bigquery/docs/ai-introduction)
- [Unveiling new BigQuery capabilities for the agentic era | Google Cloud Blog](https://cloud.google.com/blog/products/data-analytics/unveiling-new-bigquery-capabilities-for-the-agentic-era)
- [Create data agents | BigQuery | Google Cloud Documentation](https://docs.cloud.google.com/bigquery/docs/create-data-agents)
- [Use the Data Engineering Agent to build and modify data pipelines](https://docs.cloud.google.com/bigquery/docs/data-engineering-agent-pipelines)
- [Use Knowledge Catalog with BigQuery](https://docs.cloud.google.com/bigquery/docs/use-knowledge-catalog)
- [Introduction to embeddings and vector search](https://docs.cloud.google.com/bigquery/docs/vector-search-intro)
- [The TimesFM model | BigQuery](https://docs.cloud.google.com/bigquery/docs/timesfm-model)
