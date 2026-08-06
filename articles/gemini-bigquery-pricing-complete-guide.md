---
title: "Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】"
emoji: "💰"
type: "tech"
topics: ["bigquery","gemini","googlecloud","ai","cost"]
published: true
---

## はじめに

「BigQueryでAIを使ってみたら、月末に想定外の請求が届いた」――そのような声を耳にする機会が増えています。Googleが提供する**Gemini in BigQuery**は、SQLクエリの補完や自然言語でのデータ分析が行える便利な機能ですが、料金体系が複雑なため、うっかり高額課金につながるケースが少なくありません。

特に中小ECサイトの経営者やWebコンサルタントの方々にとって、GA4のデータをBigQueryで分析できる点は非常に魅力的です。一方で、「AIアシスト機能を試しに有効にしたら、いつの間にか費用が積み上がっていた」という状況は避けたいところでしょう。

本記事では、Gemini in BigQueryの料金体系を体系的に整理し、思わぬ課金を防ぐための設定方法や運用のポイントを丁寧に解説します。料金の仕組みを正しく理解した上で、費用対効果の高い使い方を見つける一助となれば幸いです。

---

## Gemini in BigQueryとは？機能と提供形態の整理

Gemini in BigQueryとは、GoogleのAIモデル「Gemini」をBigQueryのコンソールやAPIに組み込んだ機能群の総称です。主な機能として以下が挙げられます。

- **Gemini コード補完（旧: Duet AI）**: BigQueryのコンソール上でSQLを書く際にコードの候補を自動提示する
- **Gemini によるデータインサイト**: テーブルやクエリ結果を自然言語で要約・説明する
- **Gemini モデルの呼び出し（ML.GENERATE_TEXT / ML.UNDERSTAND_TEXT）**: SQLの中から直接Geminiを呼び出してテキスト生成や分析を行う
- **BigQuery Studio との統合**: ノートブック形式でデータ探索とAI分析を組み合わせる

これらの機能は提供形態が異なり、「UIの補助機能」として使う場合と、「SQLから直接Geminiモデルを呼び出す」場合とで料金の考え方がまったく異なります。まずはこの2つを区別することが、料金体系を理解する第一歩です。

---

## 料金体系の全体像：無料枠と課金対象の境界線

Gemini in BigQueryの料金は、大きく以下の3つの軸で考える必要があります。

### 1. Gemini for Google Cloud（サブスクリプション）

BigQueryコンソール上のコード補完・自然言語サジェストなどのUI補助機能は、**Gemini for Google Cloud** というサブスクリプションに含まれています。2024年以降、Google Workspaceまたは独立したサブスクリプション（月額ユーザー単価）として提供されており、無料トライアル期間が設けられることがあります。

試用期間が終了した後も気づかずに利用し続けると、ユーザー数×月額の費用が発生します。組織内で複数人が有効化している場合、合算するとそれなりの金額になります。

### 2. BigQuery ML による Gemini モデル呼び出し（従量課金）

SQLクエリから`ML.GENERATE_TEXT`などの関数を使ってGeminiを呼び出す場合、**入出力トークン数に応じた従量課金**が発生します。これはBigQuery MLの料金体系に基づいており、処理するデータ量とトークン数の両方がコストに影響します。

たとえば、以下のようなクエリでGA4のセッションメモを自動要約するケースを考えます。

```sql
SELECT
  user_pseudo_id,
  ML.GENERATE_TEXT(
    MODEL `myproject.mydataset.gemini_model`,
    STRUCT(
      CONCAT('次のページパスを要約してください: ', page_location) AS prompt
    )
  ).ml_generate_text_llm_result AS summary
FROM
  `myproject.analytics_123456789.events_*`
WHERE
  event_name = 'page_view'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
LIMIT 1000;
```

このクエリでは、1,000行分のプロンプトをGeminiに送信するため、入力トークン数が大量に発生します。大規模なテーブルに対して実行すると、**数千円〜数万円単位の課金が1回のクエリで生じる**ことも珍しくありません。

### 3. BigQuery のクエリ処理費用（スキャン課金）

Gemini呼び出しとは別に、BigQuery自体のクエリスキャン費用も発生します。オンデマンド料金では**$6.25/TiB**（2025年時点）が基本となります。GA4のデータが数年分蓄積されている場合、スキャン対象を絞り込まずに実行すると、この費用だけで高額になります。

---

## 思わぬ課金が発生する主なパターン

料金の仕組みを理解しても、実際の運用では見落としがちなケースがあります。代表的なパターンを3つ紹介します。

### パターン1：全期間テーブルへのML関数適用

`events_*`のように全テーブルをワイルドカードで指定し、LIMITを付け忘れてML関数を呼び出すと、蓄積されたすべての行に対してGeminiが呼ばれます。10万行のデータがある場合、10万件分のトークン費用が一度に発生します。

### パターン2：テスト用プロジェクトへの課金有効化

「ちょっと試すだけ」のつもりで本番プロジェクトのBilling設定のままGeminiモデルを作成・実行し、想定より大規模なクエリを走らせてしまうケースです。テスト時は**`LIMIT`句で行数を制限してから実行**することが重要です。

### パターン3：自動スケジュールクエリへのML関数の組み込み

BigQueryのスケジュールクエリでML.GENERATE_TEXTを含むSQLを登録すると、毎日・毎週自動で課金が発生し続けます。スケジュール設定後に実行コストを確認しないまま放置すると、月末に予想外の請求につながります。

---

## 思わぬ課金を防ぐための設定と運用のポイント

課金リスクを最小化するために、以下の設定と運用を組み合わせることをお勧めします。

### 予算アラートの設定（必須）

Google Cloud ConsoleのBillingから**予算アラート**を設定し、月間予算の50%・90%・100%それぞれで通知メールを受け取るようにしましょう。異常な課金に早期に気づける仕組みです。

```bash
# gcloudコマンドで予算を作成する例（月額5,000円のアラート設定）
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="BigQuery月次予算" \
  --budget-amount=5000JPY \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100
```

### カスタムコストコントロール（プロジェクト単位のクォータ）

Google Cloud Consoleの「APIとサービス」→「割り当て」から、BigQuery APIの1日あたりのバイト処理上限を設定できます。一定量以上のスキャンをブロックすることで、大規模クエリの暴走を防ぎます。

### ML関数の実行前にDRY RUN（概算コスト確認）

BigQuery MLのジョブも、通常のクエリと同様にDRY RUNで事前スキャン量を確認できます。ただし、MLのトークン費用はDRY RUNでは正確に把握できないため、**まず`LIMIT 10`で小規模テストを実施し、1件あたりのコストを概算してから本番実行**するプロセスを習慣にしましょう。

### Gemini for Google Cloud のユーザー割り当て管理

コンソール補助機能を使うユーザーを限定したい場合、Google Admin Consoleでライセンスを特定のユーザーにのみ付与する設定が可能です。全社員に自動付与されている状態は、費用の観点から見直しの余地があります。

---

## GA4×BigQueryでGeminiを活用するコスト最適化の考え方

GA4のBigQueryエクスポートデータをGeminiで分析する場合、コストを抑えながら効果的に活用するための考え方を整理します。

### データを絞り込んでからモデルに渡す

Geminiに渡すデータは、事前のSQLフィルタリングで最小限に絞り込みます。たとえば、直帰率の高いセッションのページパスのみを対象にする場合、以下のようにサブクエリで先にフィルタリングします。

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `myproject.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name IN ('session_start', 'page_view')
  GROUP BY
    1, 2, 3, 4
)
SELECT
  user_pseudo_id,
  ga_session_id,
  medium,
  source
FROM
  session_data
WHERE
  event_count = 1  -- セッション内イベントが1件のみ（直帰の近似）
LIMIT 500;
```

このように事前に行数を絞り込んだ結果のみをGeminiに渡すことで、トークン費用を大幅に抑えられます。

### 用途に応じてモデルを使い分ける

Geminiには複数のバリアントがあり、`gemini-1.5-flash`などの軽量モデルは`gemini-1.5-pro`と比べてトークン単価が低く設定されています。要約・分類・ラベリングなどのシンプルなタスクにはFlashを使い、複雑な推論が必要な場合のみProを選択する使い分けが費用対効果の向上につながります。

---

## まとめ

Gemini in BigQueryの料金は、UIの補助機能（サブスクリプション）とMLモデル呼び出し（従量課金）、そして通常のクエリスキャン費用の3層構造になっています。それぞれの課金条件を混同したまま利用を始めると、月末に想定外の請求を受けるリスクがあります。

**本記事のポイントを3点に絞ると以下のとおりです。**

1. Geminiの補助機能（コード補完）とSQL内のML関数は課金体系が異なる
2. MLモデルの呼び出しは必ず小規模テストを先に行い、コスト感をつかんでから本番実行する
3. 予算アラートとクォータ設定を組み合わせて、課金の上限を仕組みで守る

コストをコントロールしながらGeminiを活用できれば、GA4データの分析深度を高め、マーケティングや購買導線の改善に役立てる余地が大きく広がります。まずは予算アラートの設定から始め、小さな実験を積み重ねていくことをお勧めします。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
