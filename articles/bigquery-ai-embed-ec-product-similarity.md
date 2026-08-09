---
title: "BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する"
emoji: "🔗"
type: "tech"
topics: ["bigquery","gemini","ai","ec","googlecloud"]
published: false
---

## はじめに

「この商品を見た人はこんな商品も見ています」——大手ECサイトでよく見かけるこのレコメンド機能、実は機械学習の専門知識がなくても、BigQueryだけで実現できるようになっています。

中小ECサイトを運営していると、「類似商品のレコメンドを出したいけれど、開発コストがかかりそうで手が出せない」というお声をよく聞きます。商品数が数百〜数千点あっても、人手でひとつひとつ関連商品を設定するのは現実的ではありません。

そこで活用したいのが、BigQueryに搭載された **AI.EMBED関数** です。Google CloudのGeminiモデルを活用し、商品名や説明文をベクトル（数値の配列）に変換することで、テキストの意味的な近さをもとに類似商品を自動で見つけ出せます。本記事では、EC運営者の方でも理解しやすいよう、仕組みから実装手順まで順を追って解説します。

---

## AI.EMBED関数とは何か

AI.EMBED関数は、2024年にBigQueryへ追加されたML系SQL関数のひとつです。文字列をAIモデルに渡し、その意味を表す「埋め込みベクトル（Embedding）」を返してくれます。

埋め込みベクトルとは、テキストの意味を数百〜数千次元の数値列として表現したものです。たとえば「綿100%の白いTシャツ」と「コットン素材のホワイトカットソー」は表現が異なりますが、意味的には近いため、ベクトル空間上でも近い位置に配置されます。この性質を利用することで、キーワードの一致に頼らない「意味ベースの検索」が実現できます。

AI.EMBED関数の主な特徴は以下のとおりです。

- **SQLだけで完結**：Pythonコードや外部APIの呼び出しが不要
- **Geminiモデルを利用**：Google CloudのVertex AIと連携しているため、別途モデルを用意する必要がない
- **スケーラブル**：商品数が増えても、BigQueryのバッチ処理でまとめて変換できる

なお、AI.EMBED関数の利用にはVertex AIのAPIを有効化することと、Gemini Embedding系のモデルへのアクセスが必要です。Google Cloudのプロジェクトで事前に設定を行ってください。

---

## 商品データをBigQueryに格納する

まず、ECサイトの商品データをBigQueryのテーブルに用意します。CSVやスプレッドシートから読み込む方法が一般的です。ここでは以下のようなシンプルなスキーマを想定します。

```sql
-- 商品マスタテーブルの作成例
CREATE OR REPLACE TABLE `your_project.ec_dataset.products` (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  description  STRING
);
```

商品名と説明文を組み合わせた文字列を埋め込みの対象にすると、カテゴリや素材・用途などの情報も反映されます。データのクレンジング（HTMLタグの除去や過剰な改行の削除）をあらかじめ行っておくと、精度が向上しやすくなります。

:::message
AI.EMBED関数は1回のクエリで処理できる行数に制限があります。商品数が多い場合は、WHERE句で分割して複数回実行するか、BigQuery Scheduled Queryで定期バッチとして運用することを検討してください。
:::

---

## AI.EMBEDで商品ベクトルを生成する

商品テーブルが用意できたら、AI.EMBED関数を使ってベクトルを生成し、別テーブルに保存します。

```sql
-- 商品ベクトルテーブルの作成
CREATE OR REPLACE TABLE `your_project.ec_dataset.product_embeddings` AS
SELECT
  product_id,
  product_name,
  category,
  ml_generate_embedding_result AS embedding
FROM
  ML.GENERATE_EMBEDDING(
    MODEL `your_project.ec_dataset.embedding_model`,
    (
      SELECT
        product_id,
        product_name,
        category,
        CONCAT(product_name, ' ', category, ' ', description) AS content
      FROM
        `your_project.ec_dataset.products`
    ),
    STRUCT(TRUE AS flatten_json_output)
  );
```

上記クエリでは `ML.GENERATE_EMBEDDING` を使用しています。これはAI.EMBEDに相当するBigQuery MLの関数で、事前にVertex AI接続モデルを登録しておく必要があります。モデルの登録は以下のSQLで行えます。

```sql
-- Vertex AI接続モデルの登録（初回のみ）
CREATE OR REPLACE MODEL `your_project.ec_dataset.embedding_model`
REMOTE WITH CONNECTION `your_project.us.vertex-ai-connection`
OPTIONS (ENDPOINT = 'text-embedding-004');
```

`vertex-ai-connection` の部分は、BigQuery Studio上で作成したVertex AI接続リソース名に置き換えてください。接続の作成はBigQuery Studio → 外部接続から数分で設定できます。

:::message
`text-embedding-004` はGoogleが提供するテキスト埋め込みモデルのひとつです。日本語テキストにも対応しており、商品名や説明文の埋め込みに適しています。モデルの最新バージョンはGoogle Cloudのドキュメントでご確認ください。
:::

---

## コサイン類似度で類似商品を検索する

ベクトルが生成できたら、コサイン類似度を使って類似商品を見つけます。コサイン類似度とは、2つのベクトルがどれだけ同じ方向を向いているかを-1〜1の値で表したもので、1に近いほど意味が似ています。

```sql
-- 指定した商品に類似する上位5件を取得
DECLARE target_product_id STRING DEFAULT 'P001';

WITH target AS (
  SELECT embedding
  FROM `your_project.ec_dataset.product_embeddings`
  WHERE product_id = target_product_id
),
similarities AS (
  SELECT
    p.product_id,
    p.product_name,
    p.category,
    -- コサイン類似度の計算
    (
      SELECT SUM(a * b)
      FROM UNNEST(p.embedding) a WITH OFFSET i
      JOIN UNNEST((SELECT embedding FROM target)) b WITH OFFSET j
      ON i = j
    ) /
    (
      SQRT((SELECT SUM(POW(v, 2)) FROM UNNEST(p.embedding) v)) *
      SQRT((SELECT SUM(POW(v, 2)) FROM UNNEST((SELECT embedding FROM target)) v))
    ) AS cosine_similarity
  FROM `your_project.ec_dataset.product_embeddings` p
  WHERE p.product_id != target_product_id
)
SELECT
  product_id,
  product_name,
  category,
  ROUND(cosine_similarity, 4) AS similarity_score
FROM similarities
ORDER BY cosine_similarity DESC
LIMIT 5;
```

このクエリを実行すると、対象商品（ここではP001）に意味的に近い商品が類似度スコアの高い順に5件返ってきます。「綿素材の半袖シャツ」を基準にすると、「リネンの開襟シャツ」や「夏向けトップス」など、キーワードは違っても意味が近い商品が上位に並ぶようになります。

---

## GA4データと組み合わせた活用例

類似商品の検索機能は、GA4のBigQueryエクスポートと組み合わせることで、「よく見られている商品ページに類似した商品を推薦する」という施策に発展させることができます。

以下のクエリは、直近7日間に商品詳細ページを閲覧したセッションを取得し、どの商品が多く見られているかを集計する例です。

```sql
-- 直近7日間に閲覧された商品ページのセッション集計
SELECT
  ep.value.string_value AS product_id_viewed,
  COUNT(DISTINCT
    (SELECT ep2.value.string_value
     FROM UNNEST(event_params) ep2
     WHERE ep2.key = 'ga_session_id')
  ) AS session_count,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(event_params) ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'view_item'
  AND ep.key = 'item_id'
GROUP BY
  product_id_viewed,
  traffic_medium,
  traffic_source
ORDER BY
  session_count DESC
LIMIT 20;
```

この結果と先ほどの類似商品テーブルを JOIN することで、「SNS経由で訪問したユーザーが最もよく見ている商品Aに似た商品をレコメンド候補として抽出する」といった活用が可能です。マーケティング施策やメルマガのコンテンツ選定にも役立てられます。

:::message
GA4のBigQueryエクスポートでは、`ga_session_id` はイベントパラメータとして格納されており、トップレベルの列として直接参照することはできません。必ず `UNNEST(event_params)` を経由して取得してください。また、流入元の情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使用します。
:::

---

## まとめ

本記事では、BigQueryのAI.EMBED（ML.GENERATE_EMBEDDING）関数を活用したEC商品の類似度検索の実装手順を解説しました。要点を整理します。

- **AI.EMBED関数**を使うと、商品名や説明文をベクトルに変換し、意味的な類似性で商品を検索できる
- 実装はすべてSQL上で完結し、Python等の別言語の知識がなくても導入できる
- **コサイン類似度**を計算することで、類似商品をスコアリングして優先順位をつけられる
- **GA4のBigQueryエクスポート**と組み合わせると、実際の閲覧傾向に基づいたレコメンド候補の抽出まで発展できる

次のアクションとしては、まずサンプルとして10〜20件の商品データで動作確認を行い、類似度スコアの精度を見ながら `content` に渡すテキストの内容（商品名のみ・説明文のみ・両方の組み合わせ）を調整してみることをお勧めします。埋め込みベクトルを定期的に更新するスケジュールを組むことで、新商品追加にも対応しやすくなります。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
