---
title: "BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話"
emoji: "🛒"
type: "tech"
topics: ["bigquery","googlecloud","machinelearning","ec","ai"]
published: false
---

## はじめに

「おすすめ商品」の枠を設けているものの、全ユーザーに同じ商品が表示されていませんか？ Amazonや楽天のように「あなたへのおすすめ」を実現したいけれど、専用ツールの月額費用が高すぎて手が出せない、という悩みを抱えているEC担当者は多いのではないでしょうか。

実は、Google Cloud の BigQuery と Vertex AI を組み合わせることで、大規模なMLエンジニアリングの知識がなくても、ユーザーの行動データに基づくパーソナライズドレコメンドエンジンを構築できます。本記事では、GA4のBigQueryエクスポートデータを起点に、商品レコメンドの仕組みを自作する流れを解説します。

前提として、GA4のBigQueryエクスポートが設定済みであること、Google Cloudプロジェクトが存在することをご確認ください。費用感としては、月に数百万PVのECサイトであっても、BigQueryのストレージ・クエリ費用は月数千円程度に収まるケースが多く、既製のレコメンドSaaSと比べてコストを大幅に抑えられる可能性があります。

---

## Step 1: GA4の閲覧・購入ログをBigQueryで整形する

まず、GA4からBigQueryにエクスポートされた生データを、レコメンドエンジンが扱いやすい形に整形します。ここでは「ユーザーがどの商品を閲覧・購入したか」のログを抽出します。

:::message
GA4のBigQueryエクスポートテーブルでは、`ga_session_id` はトップレベルに存在しません。`UNNEST(event_params)` を通じてネストされたパラメータから取得する必要があります。
:::

```sql
-- ユーザーごとの商品閲覧・購入ログを抽出
WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    -- eコマースアイテム情報
    item.item_id,
    item.item_name,
    item.item_category,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    event_timestamp
  FROM
    `your_project.analytics_XXXXXXX.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name IN ('view_item', 'purchase')
    AND item.item_id IS NOT NULL
)
SELECT
  user_pseudo_id,
  ga_session_id,
  item_id,
  item_name,
  item_category,
  traffic_medium,
  traffic_source,
  COUNTIF(event_name = 'view_item') AS view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM session_base
GROUP BY 1, 2, 3, 4, 5, 6, 7
```

このクエリにより、ユーザーIDと商品IDの組み合わせ、および閲覧回数・購入回数が得られます。購入は閲覧よりも強いシグナルとして扱うため、後工程でスコアに重みをつけて利用します。

---

## Step 2: ユーザー×商品のインタラクションマトリクスを作成する

レコメンドエンジンの核となるのは、「誰がどの商品にどれだけ関心を持ったか」を数値化したインタラクションマトリクスです。前ステップのデータをもとに、暗黙的フィードバック（閲覧・購入）をスコア化します。

```sql
-- インタラクションスコアの計算（閲覧=1点、購入=5点として加算）
CREATE OR REPLACE TABLE `your_project.ml_dataset.user_item_interactions` AS
SELECT
  user_pseudo_id,
  item_id,
  item_name,
  item_category,
  -- 購入を閲覧より重視したスコア設計
  LEAST((view_count * 1.0 + purchase_count * 5.0), 10.0) AS interaction_score
FROM (
  SELECT
    user_pseudo_id,
    item_id,
    item_name,
    item_category,
    SUM(view_count) AS view_count,
    SUM(purchase_count) AS purchase_count
  FROM `your_project.ml_dataset.raw_interactions`
  GROUP BY 1, 2, 3, 4
)
WHERE
  -- 一定のインタラクションがあるユーザーのみ対象
  view_count + purchase_count >= 2
```

スコアに上限（ここでは10点）を設けているのは、特定のヘビーユーザーがモデルに過剰な影響を与えるのを防ぐためです。スコア設計はビジネスの性質に応じて調整してください。

---

## Step 3: BigQuery MLで協調フィルタリングモデルを学習する

BigQuery ML（BQML）を使えば、SQLだけで機械学習モデルを学習できます。ここでは、行列分解（Matrix Factorization）を用いた協調フィルタリングを利用します。

```sql
-- BigQuery MLで協調フィルタリングモデルを作成
CREATE OR REPLACE MODEL `your_project.ml_dataset.item_recommender`
OPTIONS (
  model_type = 'matrix_factorization',
  user_col = 'user_pseudo_id',
  item_col = 'item_id',
  rating_col = 'interaction_score',
  feedback_type = 'implicit',  -- 暗黙的フィードバック
  num_factors = 16,
  l2_reg = 0.1
) AS
SELECT
  user_pseudo_id,
  item_id,
  interaction_score
FROM
  `your_project.ml_dataset.user_item_interactions`
```

学習には数分〜数十分かかります。`num_factors` はモデルの表現力に関わるパラメータで、商品数が少ない場合は8〜16程度から試すとよいでしょう。

学習が完了したら、以下のクエリで特定ユーザーへのレコメンドを生成できます。

```sql
-- 特定ユーザーへのレコメンド上位5件を取得
SELECT
  user_pseudo_id,
  item_id,
  predicted_interaction_score_confidence
FROM
  ML.RECOMMEND(
    MODEL `your_project.ml_dataset.item_recommender`,
    (
      SELECT DISTINCT user_pseudo_id
      FROM `your_project.ml_dataset.user_item_interactions`
      WHERE user_pseudo_id = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    )
  )
ORDER BY predicted_interaction_score_confidence DESC
LIMIT 5
```

---

## Step 4: Vertex AI Feature Storeでレコメンド結果を配信する

BQMLで生成したレコメンド結果を実際のECサイトで活用するには、リアルタイムに近い速度でデータを取り出せる仕組みが必要です。Vertex AI Feature Store を使うと、BigQueryのバッチ処理結果をオンラインサービング（低レイテンシ取得）に対応したストアへ同期できます。

```python
from google.cloud import aiplatform

PROJECT_ID = "your_project"
LOCATION = "asia-northeast1"

aiplatform.init(project=PROJECT_ID, location=LOCATION)

# Feature Storeの作成（初回のみ）
fs = aiplatform.featurestore.Featurestore.create(
    featurestore_id="ec_recommendations",
    online_store_fixed_node_count=1,
)

# エンティティタイプ（ユーザー）の作成
entity_type = fs.create_entity_type(
    entity_type_id="user",
    description="EC site user recommendation features",
)

# フィーチャー（レコメンド商品IDリスト）の作成
entity_type.create_feature(
    feature_id="recommended_item_ids",
    value_type="STRING_ARRAY",
    description="Top 5 recommended item IDs",
)
```

その後、BigQueryのレコメンド結果テーブルからFeature Storeへの同期をスケジュール実行（例: Cloud Schedulerで1日1回）する構成にすることで、前日の行動データに基づくレコメンドをWebサイトのAPIから取得できるようになります。

:::message
Vertex AI Feature StoreはBigQueryと同じGCPプロジェクト内で利用することで、データ転送コストを最小化できます。また、オンラインサービングノード数は最初は最小構成（1ノード）から始め、リクエスト数に応じて増やすことを検討してください。
:::

---

## Step 5: 流入元別にレコメンドの効果を検証する

レコメンドエンジンを導入したあとは、どの流入チャネルのユーザーがレコメンドをクリックしやすいか、購入につながりやすいかを分析することが重要です。GA4のBigQueryエクスポートデータを使って、流入元ごとのコンバージョン比較を行いましょう。

```sql
-- 流入元ごとのレコメンドクリック率・CVRを集計
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS total_users,
  COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%') AS recommend_clicks,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS recommend_ctr,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS cvr
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(promotions) AS promotion
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
GROUP BY 1, 2
ORDER BY recommend_ctr DESC
```

このような分析を通じて、たとえばメールマーケティング経由のユーザーはレコメンドのクリック率が高い一方で、SNS広告経由のユーザーは閲覧のみで離脱しやすい、といった傾向が見えてきます。チャネル別の特性に合わせてレコメンドの表示位置やタイミングを調整することで、施策の精度を高めることができます。

---

## まとめ

本記事では、BigQuery × Vertex AIを活用したECレコメンドエンジンの構築ステップを解説しました。要点を整理します。

- **Step 1**: GA4のBigQueryエクスポートから閲覧・購入ログを整形（`UNNEST(event_params)` でセッションIDを取得、流入元は `collected_traffic_source` から参照）
- **Step 2**: ユーザー×商品のインタラクションスコアをSQLで計算
- **Step 3**: BigQuery ML（行列分解）でレコメンドモデルを学習・推論
- **Step 4**: Vertex AI Feature Storeを使ってリアルタイム配信に対応
- **Step 5**: 流入元別のレコメンド効果をBigQueryで継続的に検証

次のアクションとしては、まずGA4のBigQueryエクスポートが有効になっているかを確認し、Step 1のSQLを自社データに合わせて試してみることをおすすめします。BigQuery MLは無料枠内でも小規模なモデルを試すことができるため、PoC（概念実証）のハードルは低めです。

本格的な本番運用に向けては、モデルの定期再学習スケジュールの設定や、A/Bテストによるレコメンド有無の効果比較なども検討すると、継続的な改善サイクルを回していけるでしょう。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
