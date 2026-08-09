---
title: "BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する"
emoji: "🧠"
type: "tech"
topics: ["bigquery","gemini","machinelearning","ec","googlecloud"]
published: false
---

## はじめに

「広告費をかけているのに、なぜ売上が安定しないのだろう」——そうお感じになるEC事業者様は少なくないと思います。アクセスは集まっても、購買に至るお客様と離脱してしまうお客様の違いが、データの中に埋もれたままになっているケースがよく見受けられます。

GA4とBigQueryを連携させると、ページ閲覧やカート追加などの行動ログが毎日自動でデータウェアハウスに蓄積されていきます。このデータをうまく活用できれば、「今後7日以内に購買する見込みが高いお客様」をあらかじめ予測し、メールやリターゲティング広告のターゲットを絞り込むことができます。

本記事では、BigQuery MLとGeminiを組み合わせて購買予測モデルを構築する手順を、SQLを中心にご紹介します。機械学習の専門知識がなくても、SQLが読める方であれば概要を把握しながら実装を進めていただけるように構成しています。エンジニアリングリソースが限られた中小EC事業者様や、クライアントへの提案材料を探しているWebコンサルタントの方にとって、参考になれば幸いです。

## BigQuery MLとGeminiの役割分担を理解する

BigQuery MLは、BigQuery上のデータに対してSQLだけで機械学習モデルを訓練・予測できるGoogleのサービスです。Pythonや専用の機械学習フレームワークを学ばなくても、`CREATE MODEL`文を実行するだけでモデルが作成されます。

一方のGeminiは、Google CloudのAIサービス群に統合された大規模言語モデルです。BigQuery MLとGeminiを組み合わせると、構造化データによる予測結果と自然言語による分析・説明生成を一つのワークフローにまとめることができます。たとえば、「購買確率が高いセグメントの特徴をGeminiに言語化させる」といった使い方が可能です。

本記事では次のような流れで進めます。

1. GA4エクスポートデータから特徴量を作成する
2. BigQuery MLでロジスティック回帰モデルを訓練する
3. 予測結果をGeminiで解釈・要約する

## 特徴量テーブルを作成する（GA4エクスポートデータの加工）

GA4のBigQueryエクスポートでは、`events_*`テーブルにユーザーの行動ログが蓄積されています。このテーブルから、ユーザーごとの行動集計値（特徴量）と購買フラグを作成します。

以下のSQLでは、過去30日間のセッションを集計し、各ユーザーの行動パターンと購買有無をまとめています。`ga_session_id`はイベントパラメータの中に格納されているため、`UNNEST(event_params)`を経由して取得している点に注意してください。また、流入元の情報は`collected_traffic_source`フィールドから取得します。

```sql
WITH base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source  AS traffic_source
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
features AS (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT ga_session_id)                             AS session_count,
    COUNTIF(event_name = 'page_view')                        AS page_view_count,
    COUNTIF(event_name = 'view_item')                        AS view_item_count,
    COUNTIF(event_name = 'add_to_cart')                      AS add_to_cart_count,
    COUNTIF(event_name = 'begin_checkout')                   AS begin_checkout_count,
    MAX(CASE WHEN traffic_medium = 'email'   THEN 1 ELSE 0 END) AS has_email_session,
    MAX(CASE WHEN traffic_medium = 'cpc'     THEN 1 ELSE 0 END) AS has_paid_search_session,
    MAX(CASE WHEN event_name = 'purchase'    THEN 1 ELSE 0 END) AS label
  FROM base
  GROUP BY user_pseudo_id
)
SELECT * FROM features;
```

このクエリの結果を`your_project.your_dataset.ec_user_features`として保存しておきます。

```sql
CREATE OR REPLACE TABLE `your_project.your_dataset.ec_user_features` AS
-- 上記のSELECT文をそのまま貼り付けてください
;
```

:::message
`your_project.analytics_XXXXXXX`の部分はGA4プロパティに対応する実際のデータセット名に置き換えてください。BigQueryのデータセット一覧から確認できます。
:::

## BigQuery MLでロジスティック回帰モデルを訓練する

特徴量テーブルが用意できたら、`CREATE MODEL`文でモデルを作成します。今回はシンプルなロジスティック回帰（`LOGISTIC_REG`）を使用します。二値分類（購買する／しない）に適したアルゴリズムです。

```sql
CREATE OR REPLACE MODEL `your_project.your_dataset.purchase_prediction_model`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label'],
  auto_class_weights = TRUE,
  data_split_method = 'AUTO_SPLIT'
) AS
SELECT
  session_count,
  page_view_count,
  view_item_count,
  add_to_cart_count,
  begin_checkout_count,
  has_email_session,
  has_paid_search_session,
  label
FROM
  `your_project.your_dataset.ec_user_features`;
```

`auto_class_weights = TRUE`を指定しているのは、ECサイトでは購買ユーザーが全体の数%程度に留まることが多く、クラス不均衡が生じやすいためです。この設定により、少数クラス（購買あり）の重みを自動調整してモデルの偏りを抑えています。

訓練が完了したら、モデルの評価指標を確認します。

```sql
SELECT *
FROM ML.EVALUATE(MODEL `your_project.your_dataset.purchase_prediction_model`);
```

`roc_auc`が0.7以上であれば、実用的な予測精度の目安として参考にできます。ただし、精度の解釈はデータ量やサイトの特性によって異なるため、複数の指標を合わせて判断することを推奨します。

## 購買確率を予測してセグメントを抽出する

モデルが準備できたら、現在のアクティブユーザーに対して購買確率を予測します。

```sql
SELECT
  user_pseudo_id,
  predicted_label,
  predicted_label_probs
FROM
  ML.PREDICT(
    MODEL `your_project.your_dataset.purchase_prediction_model`,
    (
      SELECT
        user_pseudo_id,
        session_count,
        page_view_count,
        view_item_count,
        add_to_cart_count,
        begin_checkout_count,
        has_email_session,
        has_paid_search_session
      FROM
        `your_project.your_dataset.ec_user_features`
      WHERE
        label = 0  -- 未購買ユーザーのみ対象
    )
  )
ORDER BY
  (SELECT p.prob FROM UNNEST(predicted_label_probs) p WHERE p.label = '1') DESC
LIMIT 500;
```

このクエリは、未購買ユーザーの中から購買確率の高い順に500名を抽出するものです。この結果をメール配信ツールやGoogle Adsのカスタマーマッチにインポートすることで、精度の高いリターゲティングが実現できます。

## GeminiでセグメントのインサイトをAIに言語化させる

BigQuery MLの予測結果に対してGeminiを呼び出し、セグメントの特徴を自然言語で説明させることができます。BigQueryからGeminiを呼び出すには、`ML.GENERATE_TEXT`関数を使用します。

:::message
`ML.GENERATE_TEXT`を使用するには、あらかじめBigQueryの接続リソース（リモートモデル）を作成し、Vertex AIとの連携を設定する必要があります。Google CloudコンソールのBigQuery > 外部接続から設定できます。
:::

```sql
CREATE OR REPLACE MODEL `your_project.your_dataset.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection`
OPTIONS (endpoint = 'gemini-1.5-flash');
```

リモートモデルを作成したら、予測結果の集計データをプロンプトとしてGeminiに渡します。

```sql
SELECT
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS gemini_insight
FROM
  ML.GENERATE_TEXT(
    MODEL `your_project.your_dataset.gemini_model`,
    (
      SELECT
        CONCAT(
          '以下はECサイトにおける購買確率の高いユーザーセグメントの行動集計データです。',
          'このセグメントの特徴と、効果的なアプローチ方法を200文字以内で教えてください。\n\n',
          '平均セッション数: ', AVG(session_count),
          ', 平均商品閲覧数: ', AVG(view_item_count),
          ', カート追加率: ', COUNTIF(add_to_cart_count > 0) / COUNT(*),
          ', メール経由割合: ', AVG(has_email_session)
        ) AS prompt
      FROM
        `your_project.your_dataset.ec_user_features`
      WHERE
        label = 0
    ),
    STRUCT(0.3 AS temperature, 512 AS max_output_tokens)
  );
```

Geminiからの出力例（実際の結果はデータにより異なります）:

> 「商品閲覧数が多くカート追加経験のあるユーザーが中心です。購買直前の心理にあると考えられるため、送料無料クーポンや期間限定オファーのメール訴求が有効なアプローチになる可能性があります。」

このように、数値の集計結果をビジネス上の示唆として言語化できるのがGemini連携の利点です。レポーティングや上長への説明資料作成にも活用できます。

## まとめ

本記事では、BigQuery ML × Geminiを活用したEC向け購買予測モデルの構築手順をご紹介しました。要点を整理します。

- **特徴量の作成**: GA4エクスポートデータから`UNNEST(event_params)`でセッションIDを取得し、ユーザーごとの行動を集計する
- **モデル訓練**: `CREATE MODEL`のSQLだけでロジスティック回帰モデルを作成できる
- **予測と活用**: `ML.PREDICT`で購買確率を算出し、メール配信やリターゲティングのリストに活用する
- **Gemini連携**: `ML.GENERATE_TEXT`でセグメントの特徴をAIに言語化させ、インサイトをビジネス言語に変換する

次のアクションとして、まずはGA4とBigQueryのリンク設定を完了させ、`events_*`テーブルにデータが蓄積されていることを確認することをお勧めします。データが1ヶ月以上蓄積されてから特徴量を作成すると、より安定した予測精度が期待できます。構築に際してご不明な点があれば、お気軽にご相談ください。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】](https://zenn.dev/web_benriya/articles/gemini-bigquery-pricing-complete-guide)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
