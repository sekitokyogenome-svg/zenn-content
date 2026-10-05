---
title: "ObjectRefで画像・PDFなど非構造化データをSQLから扱う"
emoji: "🖼️"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "objectref", "sql"]
published: true
---

## はじめに

シリーズ第15回です。

前回（第14回）では `AI.FORECAST` と TimesFM を使った学習不要の時系列予測を解説しました。今回は **`ObjectRef`** を取り上げます。

これまでのシリーズで扱ってきた `AI.GENERATE` や `AI.CLASSIFY` などの AI 関数は、テキストや数値を入力として受け取るものでした。しかし ECサイトでは商品画像・PDFカタログ・お問い合わせ添付ファイルなど、テキスト以外の非構造化データが大量に存在します。`ObjectRef` はこれらのファイルを BigQuery SQL の中から直接参照し、AI 関数に渡せるようにする仕組みです。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## ObjectRef とは

`ObjectRef` は Cloud Storage（GCS）上のファイルを BigQuery SQL から参照するための型です。画像（JPEG・PNG・WebP）・PDF・音声ファイルなどを `STRUCT` 型で包み、AI 関数に渡せるようにします。

### ObjectRef の基本構造

```sql
STRUCT(
  'gs://your-bucket/path/to/file.jpg' AS uri,
  'image/jpeg'                         AS content_type
)
```

| フィールド | 説明 |
|---|---|
| `uri` | GCS の URI（`gs://` で始まる） |
| `content_type` | MIMEタイプ（`image/jpeg`・`application/pdf` など） |

---

## 事前準備：Cloud Resource Connection の作成

`ObjectRef` を使う AI 関数の実行には Cloud Resource Connection が必要です。第2回のセットアップ済みの接続をそのまま利用できます。

```sql
CREATE OR REPLACE MODEL `your-project.ai_lab.gemini_model`
REMOTE WITH CONNECTION `your-project.asia-northeast1.vertex-ai-conn`
OPTIONS (
  endpoint = 'gemini-2.0-flash'
);
```

また、BigQuery サービスアカウントに対して GCS バケットへの `roles/storage.objectViewer` 権限を付与しておく必要があります。

---

## 商品画像をSQLで分析する

### 画像の内容をテキストで説明させる

```sql
SELECT
  product_id,
  image_uri,
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT(
      image_uri AS uri,
      'image/jpeg' AS content_type
    ),
    STRUCT('この商品画像に写っているものを100文字以内で説明してください。' AS prompt)
  ).text AS description
FROM `your-project.your_dataset.product_images`
WHERE
  image_uri IS NOT NULL
LIMIT 50;
```

### 商品カテゴリを自動分類する

```sql
SELECT
  product_id,
  image_uri,
  AI.CLASSIFY(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT(
      image_uri AS uri,
      'image/jpeg' AS content_type
    ),
    labels => ['アパレル', 'フード', '家電', '日用品', 'スポーツ', 'その他'],
    STRUCT('画像の商品ジャンルをラベルから1つ選んでください。' AS prompt)
  ).label AS category_ai
FROM `your-project.your_dataset.product_images`
WHERE image_uri IS NOT NULL;
```

`AI.CLASSIFY` に `ObjectRef` を渡すことで、テキスト説明なしでも画像から直接分類できます。

---

## PDFをSQLで解析する

### PDFカタログからテキストを抽出する

仕入れカタログや規約PDFをそのまま解析する例です。

```sql
SELECT
  document_id,
  document_uri,
  AI.GENERATE(
    MODEL `your-project.ai_lab.gemini_model`,
    STRUCT(
      document_uri AS uri,
      'application/pdf' AS content_type
    ),
    STRUCT('このPDFから商品名・価格・在庫数の一覧をJSONで出力してください。' AS prompt)
  ).text AS extracted_json
FROM `your-project.your_dataset.supplier_catalogs`
WHERE document_uri IS NOT NULL;
```

### AI.GENERATE_TABLE でPDFを構造化テーブルに変換する

`AI.GENERATE_TABLE` を使うと PDF の内容を直接構造化データに変換できます。

```sql
SELECT *
FROM
  AI.GENERATE_TABLE(
    MODEL `your-project.ai_lab.gemini_model`,
    (
      SELECT
        document_id,
        STRUCT(
          document_uri AS uri,
          'application/pdf' AS content_type
        ) AS pdf_ref
      FROM `your-project.your_dataset.supplier_catalogs`
      WHERE document_uri IS NOT NULL
    ),
    input_columns => ['pdf_ref'],
    output_schema => JSON '{"product_name": "string", "price": "integer", "stock": "integer"}'
  );
```

第6回（`AI.GENERATE_TABLE`）で解説した構造化変換を非構造化ファイルにも適用できます。

---

## 商品画像とGA4行動データを組み合わせる

商品画像の特徴と購買行動を結合して、「どんな見た目の商品がコンバージョンしやすいか」を分析する例です。

```sql
WITH image_features AS (
  SELECT
    product_id,
    AI.GENERATE(
      MODEL `your-project.ai_lab.gemini_model`,
      STRUCT(
        image_uri AS uri,
        'image/jpeg' AS content_type
      ),
      STRUCT('商品の背景色・モデルの有無・小物の有無をそれぞれ答えてください。形式: 背景色=XXX,モデル=有/無,小物=有/無' AS prompt)
    ).text AS image_feature_text
  FROM `your-project.your_dataset.product_images`
),
purchase_events AS (
  SELECT
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'item_id'
    )                                               AS product_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    )                                               AS ga_session_id,
    collected_traffic_source.manual_medium          AS medium,
    event_name
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN ('view_item', 'purchase')
),
cvr_by_product AS (
  SELECT
    product_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count,
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNTIF(event_name = 'view_item')
    )                                   AS cvr
  FROM purchase_events
  WHERE ga_session_id IS NOT NULL
  GROUP BY product_id
)
SELECT
  c.product_id,
  i.image_feature_text,
  c.view_count,
  c.purchase_count,
  ROUND(c.cvr * 100, 2) AS cvr_pct
FROM cvr_by_product AS c
LEFT JOIN image_features AS i USING (product_id)
ORDER BY c.cvr DESC
LIMIT 20;
```

:::message
GA4 の `ga_session_id` はイベントテーブルに直接カラムとして存在しません。`UNNEST(event_params)` でキー名 `ga_session_id` の値を取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## GCSのファイル一覧をBigQueryに取り込む

GCS に保存されている画像ファイルの URI 一覧をメタデータテーブルとして BigQuery に保持しておくと、`ObjectRef` と既存テーブルの結合が容易になります。

```sql
CREATE OR REPLACE EXTERNAL TABLE `your-project.your_dataset.product_images`
OPTIONS (
  format = 'NEWLINE_DELIMITED_JSON',
  uris = ['gs://your-bucket/metadata/product_images.jsonl']
);
```

または `bq` コマンドで GCS のオブジェクトリストを定期的に同期する方法も有効です。

---

## コスト管理

`ObjectRef` を含む AI 関数の呼び出しは、画像・PDFのトークン換算コストが加算されます。

| 対策 | 方法 |
|---|---|
| 処理対象を絞る | 全商品でなく新規追加・更新分だけ処理する |
| 結果をキャッシュする | 一度生成した説明文をテーブルに保存して再利用する |
| 解像度を落とす | 高解像度画像は GCS で事前にリサイズしてから渡す |
| PDF はページ範囲を指定する | 長大なPDFは必要なページのみ抽出して渡す |

商品画像数千点を一括処理する場合は事前にサンプル10〜20件でコストを試算し、月次処理に落とし込む設計を推奨します。

---

## まとめ

- `ObjectRef` は GCS 上の画像・PDF などを BigQuery SQL から直接参照できる仕組み
- `STRUCT(uri AS uri, content_type AS content_type)` の形式で AI 関数に渡す
- `AI.GENERATE`・`AI.CLASSIFY`・`AI.GENERATE_TABLE` と組み合わせることで非構造化データを構造化・分類できる
- GA4 の購買行動データと結合することで「どんな商品画像がCVRに貢献するか」を定量分析できる
- コストはファイルサイズとトークン数に比例するため、処理対象の絞り込みとキャッシュ設計が重要

次回（第16回）は SQL 内プロンプト設計のコツ — AI 関数の出力を安定させる書き方を解説します。

---

## 参考

- [Work with unstructured data using BigQuery ObjectRef | Google Cloud](https://cloud.google.com/bigquery/docs/object-ref-overview)
- [AI.GENERATE function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_generate)
- [Query unstructured data with AI functions | Google Cloud](https://cloud.google.com/bigquery/docs/query-unstructured-data)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
