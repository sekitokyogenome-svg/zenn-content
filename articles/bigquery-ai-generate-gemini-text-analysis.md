---
title: "AI.GENERATE関数でBigQueryから直接Geminiを呼び出してテキスト分析する方法"
emoji: "⚡"
type: "tech"
topics: ["bigquery","gemini","sql","googlecloud","ai"]
published: false
---

## はじめに

「お客様レビューが毎月数百件たまっているのに、読み切れていない」「問い合わせフォームのテキストをざっくり分類したいが、手作業では追いつかない」――こうしたお悩みを抱えるEC事業者やWebコンサルタントの方は少なくないのではないでしょうか。

テキストデータの分析は、これまでPythonやExcel上での手作業が中心でした。しかし、BigQueryにすでにデータが蓄積されているのであれば、わざわざデータを外部へ取り出さなくてもAI分析が行える時代になっています。

Google CloudのBigQueryには「AI.GENERATE」関数が用意されており、SQL文の中でGeminiモデルを呼び出してテキスト生成・分類・感情分析などを実行できます。Pythonコードを書かなくても、SQLを書ける方であれば比較的スムーズに導入できるのが大きな特徴です。

本記事では、AI.GENERATE関数の基本的な使い方から、GA4のBigQueryエクスポートデータと組み合わせた実践的なクエリ例まで、非エンジニアの方にもわかりやすく解説します。

---

## AI.GENERATE関数とは何か

AI.GENERATEは、BigQuery上でGeminiなどの生成AIモデルをSQL関数として呼び出せるGoogle Cloud固有の機能です。BigQuery ML（BQML）の一部として提供されており、事前にモデルの接続設定（リモートモデル）を行うことで、SELECT文の中でAIを呼び出せるようになります。

主な用途としては、以下のようなものが挙げられます。

- 自由記述テキストのカテゴリ分類
- レビュー・コメントのポジティブ／ネガティブ判定
- 問い合わせ内容の要約
- 翻訳や表記ゆれの正規化

従来のSQL関数と異なり、入力に自然言語のプロンプト（AIへの指示文）を渡せる点が最大の強みです。「このテキストをポジティブ・ネガティブ・中立のいずれかに分類してください」のように指示するだけで、AIが判定結果を返してくれます。

:::message
AI.GENERATEはBigQuery ML機能の一部です。利用にはBigQuery ML APIの有効化と、Vertex AI APIへのアクセス権限が必要です。また、モデル呼び出しに応じた費用が発生しますので、本番運用前にコスト試算を行うことを推奨します。
:::

---

## 事前準備：リモートモデルの作成

AI.GENERATE関数を使うには、BigQuery上にGeminiへの接続設定（リモートモデル）を作成する必要があります。以下のSQLを一度実行するだけで準備は完了です。

```sql
-- リモートモデルの作成（初回のみ）
CREATE OR REPLACE MODEL `your_project.your_dataset.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection_id`
OPTIONS (ENDPOINT = 'gemini-1.5-flash');
```

`your_project`・`your_dataset`・`your_region`・`your_connection_id` の部分はご自身のGoogle Cloud環境に合わせて書き換えてください。接続ID（Connection ID）は、BigQueryのコンソールから「外部接続」メニューで確認・作成できます。

なお、Vertex AI APIへのアクセス権限が接続サービスアカウントに付与されていないとエラーになります。Google Cloudコンソールの「IAMと管理」画面で、サービスアカウントに「Vertex AI ユーザー」ロールを付与しておきましょう。

---

## 基本的な使い方：テキスト分類クエリ

リモートモデルが作成できたら、実際にAI.GENERATEを呼び出してみましょう。以下は、商品レビューのテキストを感情（ポジティブ・ネガティブ・中立）に分類するシンプルなクエリ例です。

```sql
SELECT
  review_id,
  review_text,
  ml_generate_text_llm_result AS sentiment
FROM
  AI.GENERATE(
    MODEL `your_project.your_dataset.gemini_model`,
    (
      SELECT
        review_id,
        review_text,
        CONCAT(
          '以下のレビューテキストをポジティブ・ネガティブ・中立のいずれかに分類してください。',
          '分類結果のみを一語で返してください。\n\nレビュー: ',
          review_text
        ) AS prompt
      FROM
        `your_project.your_dataset.reviews`
    ),
    STRUCT(0.0 AS temperature, 1 AS max_output_tokens)
  );
```

`temperature` を `0.0` に設定することで、AIの回答を安定させ、ランダムなブレを抑えることができます。分類タスクのように一貫した出力が求められる場合は低い値に設定するのが基本です。

`max_output_tokens` は返答の最大トークン数です。分類タスクであれば `1` 〜 `10` 程度で十分ですが、要約タスクの場合は `100` 〜 `300` 程度に増やしてください。

---

## GA4のBigQueryエクスポートデータと組み合わせる

GA4（Googleアナリティブス4）のデータをBigQueryにエクスポートしている場合、セッションやイベントに紐づくユーザー行動データとAI分析を組み合わせることができます。

以下のクエリ例では、GA4のイベントデータからセッションIDと流入元を取得した上で、フォーム送信テキスト（別テーブルに保存している想定）をGeminiで要約しています。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'form_submit'
)
SELECT
  s.user_pseudo_id,
  s.ga_session_id,
  s.medium,
  s.source,
  f.form_text,
  ml_generate_text_llm_result AS summary
FROM
  AI.GENERATE(
    MODEL `your_project.your_dataset.gemini_model`,
    (
      SELECT
        s.user_pseudo_id,
        s.ga_session_id,
        s.medium,
        s.source,
        f.form_text,
        CONCAT(
          '以下の問い合わせ内容を50字以内で要約してください。\n\n問い合わせ: ',
          f.form_text
        ) AS prompt
      FROM session_data AS s
      INNER JOIN `your_project.your_dataset.form_submissions` AS f
        ON s.ga_session_id = f.ga_session_id
    ),
    STRUCT(0.0 AS temperature, 100 AS max_output_tokens)
  ) AS ai_result
LEFT JOIN session_data AS s
  ON ai_result.ga_session_id = s.ga_session_id
LEFT JOIN `your_project.your_dataset.form_submissions` AS f
  ON ai_result.ga_session_id = f.ga_session_id;
```

このようにGA4の流入元（オーガニック検索・SNS広告・メールなど）と問い合わせ内容の要約を紐づけることで、「どの流入チャネルからどのような相談が多いか」といったマーケティングインサイトを得ることができます。

:::message
GA4のBigQueryエクスポートでは、`ga_session_id` はイベントテーブルに直接カラムとして存在しません。`UNNEST(event_params)` を使ってキー名 `ga_session_id` の値を取り出す必要があります。また、流入元の参照には `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使用してください。
:::

---

## 活用シーン：中小ECでの実践例

AI.GENERATEが特に役立つ場面を、EC運営の文脈でいくつか挙げてみます。

**商品レビューの自動タグ付け**
毎月蓄積される商品レビューに対して、「品質」「配送」「価格」「サービス」などのタグを自動付与できます。BigQueryのスケジュールクエリと組み合わせれば、毎朝自動で新規レビューを分類・蓄積する仕組みを構築することも可能です。

**問い合わせカテゴリの自動分類**
「返品について」「サイズの選び方」「配送遅延」など、問い合わせカテゴリをAIに判定させることで、担当者への振り分けや月次レポートの作成を効率化できます。

**ネガティブレビューの早期検知**
毎日のバッチ処理でネガティブ判定されたレビューを抽出し、Looker Studioのダッシュボードに表示することで、早期対応が必要な顧客の声を見逃しにくくなります。

いずれの活用シーンも、データがBigQueryに集約されていることが前提となります。まだGA4のBigQueryエクスポートを設定していない方は、まずその基盤構築から始めることをお勧めします。

---

## まとめ

AI.GENERATE関数を使うことで、BigQueryのSQL環境から直接Geminiを呼び出し、テキスト分析・分類・要約を実行できます。要点を整理すると以下の通りです。

- **事前準備**: Vertex AI APIを有効化し、BigQueryのリモートモデルを作成する
- **基本構文**: `AI.GENERATE(MODEL ..., (SELECT ... prompt FROM ...), STRUCT(...))` の形で記述する
- **GA4との連携**: `ga_session_id` はUNNESTで取得、流入元は `collected_traffic_source` を参照する
- **活用例**: レビュー分類・問い合わせ要約・ネガティブ検知など、EC運営のさまざまな場面で応用できる

Pythonを使わずにSQLだけで完結できる点は、非エンジニアにとって大きなメリットです。一方で、費用管理やプロンプト設計には一定の知識が必要なため、はじめは少量のデータでテストしながら運用ルールを整えていくことを推奨します。

自社のデータと組み合わせた具体的な活用方法が気になる方は、下記よりお気軽にご相談ください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
