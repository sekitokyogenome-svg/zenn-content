---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery","gemini","sql","googlecloud","ai"]
published: true
---

## はじめに

「BigQueryにデータが蓄積されているのに、SQLが書けないせいで活用できていない」——そんな悩みを抱えるEC事業者やウェブ担当者の方は少なくありません。GA4のデータをBigQueryに連携したものの、いざ分析しようとすると「どんなSQLを書けばいいのかわからない」という壁にぶつかるケースはよくあります。

Googleが提供する**Gemini in BigQuery**は、こうした課題へのひとつの解決策です。自然言語（日本語や英語）でやりたい分析を入力すると、AIがSQLを生成してくれる機能であり、コードを書き慣れていない方でも分析の第一歩を踏み出しやすくなります。

本記事では、Gemini in BigQueryの基本的な使い方から、GA4データを使った実践的なSQL生成例、活用する際に意識しておきたいポイントまでを整理してご紹介します。完全な自動化ツールではなく「AIを補助として使いながら分析を進める」という姿勢で臨むのが、うまく活用するコツです。

---

## Gemini in BigQueryとは

Gemini in BigQueryは、Google CloudのBigQueryコンソール上で利用できるAIアシスタント機能です。BigQueryのクエリエディタに統合されており、以下のような操作をサポートします。

- **自然言語からSQLを生成する**（SQL生成）
- **既存SQLの説明・解説をしてくれる**（SQL説明）
- **エラーが発生したSQLの修正を提案してくれる**（エラー修正）

利用にはGoogle CloudプロジェクトでGeminiの機能を有効化し、適切な権限を付与する必要があります。2026年時点では、BigQueryコンソール右上の「Gemini」パネルからアクセスする形が一般的です。

:::message
Gemini in BigQueryの利用には別途費用が発生する場合があります。Google Cloudの料金ページで最新の情報をご確認ください。
:::

---

## 自然言語からSQLを生成する基本的な手順

実際にGemini in BigQueryを使ってSQLを生成する流れを見ていきましょう。

**手順の概要**

1. BigQueryコンソールにアクセスし、クエリエディタを開く
2. 右上のGeminiアイコンをクリックしてパネルを展開する
3. 「Generate SQL」や「SQL生成」の入力欄に分析内容を入力する
4. 生成されたSQLをエディタに挿入し、内容を確認・修正してから実行する

入力する際は、**どのテーブルを対象に、何を集計・分析したいのか**をできるだけ具体的に書くと、より意図に近いSQLが生成されやすくなります。テーブル名を明示するか、テーブルをあらかじめ選択した状態でプロンプトを入力するのがポイントです。

たとえば次のように入力します。

```text
GA4のイベントテーブル（analytics_XXXXXXXXX.events_*）を使って、
2025年7月の日別セッション数を集計してください。
```

生成されたSQLはあくまで「下書き」です。実行前にカラム名・テーブル名・日付範囲を確認し、ご自身の環境に合わせて修正してください。

---

## GA4データを使った実践SQL例

GA4のBigQueryエクスポートデータは構造がやや複雑なため、Geminiが生成したSQLをそのまま使うと誤った結果になることがあります。ここでは、よく使われる分析パターンと正しいSQL記述のポイントをご紹介します。

### セッション数の日別集計

GA4ではセッションIDを直接カラムとして参照できません。`event_params`の中にネストされているため、`UNNEST`を使って展開する必要があります。

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `プロジェクトID.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date;
```

:::message
`ga_session_id`は`event_params`の中にネストされているため、`UNNEST(event_params)`経由で取得します。カラムとして直接参照するとエラーになりますのでご注意ください。
:::

### 流入チャネル別のセッション数集計

流入元（参照元・メディア）を分析する場合は、`collected_traffic_source`フィールドを使用します。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `プロジェクトID.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC
LIMIT 20;
```

`collected_traffic_source.manual_medium`と`collected_traffic_source.manual_source`を使うことで、UTMパラメータに基づいた流入チャネルを正しく取得できます。Geminiが生成するSQLでは`traffic_source.medium`や`traffic_source.source`といった旧フィールドが使われることもあるため、GA4のBigQueryエクスポートスキーマに合わせて修正が必要な場合があります。

---

## Gemini生成SQLを使う際の注意点

AIが生成したSQLをそのまま本番環境で実行することはお勧めしません。以下のポイントを意識して、人の目で確認する習慣をつけましょう。

**1. テーブル名とプロジェクトIDを確認する**

生成されたSQLにはサンプルのプロジェクトIDやテーブル名が含まれることがあります。ご自身の環境のIDに書き換えてから実行してください。

**2. 日付範囲の指定を確認する**

`_TABLE_SUFFIX`を使ったワイルドカードクエリの場合、日付の指定ミスによって意図しない範囲のデータを読み込む可能性があります。特に大きなテーブルではコスト増につながるため、実行前に確認してください。

**3. 集計ロジックを小さなクエリで検証する**

複雑なSQLは、まず一部のデータ（`LIMIT 100`など）に対して実行し、期待通りの結果が返ってくるかを確認してから全量に適用するのが安全です。

**4. GA4のスキーマ変更に注意する**

GA4のBigQueryエクスポートスキーマはGoogleによってアップデートされることがあります。Geminiの学習データが最新スキーマに追いついていない場合、古いフィールド名を使ったSQLが生成されることもあります。公式ドキュメントと照らし合わせて確認しましょう。

---

## 非エンジニアがGemini in BigQueryを活用するためのコツ

SQLの知識がほとんどない方でも、以下を意識することで活用の幅が広がります。

**プロンプトは「何を知りたいか」を日本語で具体的に書く**

「セッション数を教えて」ではなく「2025年7月の流入チャネル別セッション数を多い順に上位10件で教えて」のように、集計軸・期間・並び順などを明示すると精度が上がります。

**生成されたSQLを「SQL説明」機能で理解する**

GeminiにはすでにあるSQLを説明させる機能もあります。生成されたSQLを入力して「このSQLが何をしているか日本語で説明して」と依頼することで、内容を理解しながら学べます。

**テンプレートとして蓄積する**

うまく動作したSQLはチームの共有ドキュメントに保存しておきましょう。次回以降はそのテンプレートをベースにGeminiへ修正依頼をかける形で効率的に分析を進められます。

---

## まとめ

Gemini in BigQueryは、SQLに不慣れな方がデータ分析へ踏み出す際の心強い補助ツールです。本記事で紹介したポイントを振り返ります。

- Gemini in BigQueryはBigQueryコンソール上でSQLの生成・説明・修正をサポートするAI機能
- 自然言語で分析内容を具体的に入力することで、意図に近いSQLが生成されやすくなる
- GA4のBigQueryエクスポートデータでは、`ga_session_id`は`UNNEST(event_params)`経由、流入元は`collected_traffic_source.manual_medium/manual_source`で取得する
- 生成されたSQLは必ずテーブル名・日付範囲・集計ロジックを人の目で確認してから実行する
- うまく動いたSQLはテンプレートとして蓄積し、チームで再利用する

AIに任せきりにするのではなく、「AIが書いた下書きを人が確認・修正する」というプロセスを大切にすることが、精度の高い分析につながります。まずは小さな分析から試してみてください。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】](https://zenn.dev/web_benriya/articles/gemini-bigquery-pricing-complete-guide)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
