---
title: "dbt × BigQueryで再現可能なデータパイプラインを構築する入門【GA4データ編】"
emoji: "🔧"
type: "tech"
topics: ["bigquery","dbt","googleanalytics","dataengineering","sql"]
published: false
---

## はじめに

「毎月のレポート作成に何時間もかけているのに、担当者が変わったら誰もSQLを読めなかった」「Googleスプレッドシートで集計していたら、どれが最新版かわからなくなった」——こういった経験はないでしょうか。

GA4のデータをBigQueryにエクスポートして活用している場合、データ変換のロジックがバラバラな場所に散らばりがちです。SQLファイルをローカルに置いている人もいれば、BigQuery上のビューとして保存している人もいます。その結果、「なぜこの数字になるのか」を説明できる人がいなくなるという問題が起きやすくなります。

この記事では、**dbt（data build tool）** と **BigQuery** を組み合わせることで、GA4データの変換ロジックをコードとして管理し、再現性の高いデータパイプラインを構築する方法を紹介します。dbtはエンジニアでなくても比較的取り組みやすいツールです。Gitの基本操作とSQLの読み書きができれば、本記事の内容を実践していただけます。

---

## dbtとは何か、なぜGA4分析に有効なのか

dbt（data build tool）は、データウェアハウス上でSQLを使ってデータ変換を行うためのツールです。従来はBigQueryのコンソール上でSQLを手動実行することが多かったかと思いますが、dbtを使うと以下のような変化が生まれます。

- **変換ロジックをSQLファイルとして管理できる**：どのSQLがどのテーブルを作るのかが一目でわかります
- **依存関係を自動解決してくれる**：「このテーブルを作る前にあのテーブルが必要」という順序をdbtが自動的に把握します
- **テストを記述できる**：「このカラムにNULLが入っていないか」「この値は一意か」といったデータ品質のチェックを自動化できます

GA4のBigQueryエクスポートデータは、1イベントが1行として保存されるネストされた構造を持っています。セッションIDや流入元などは直接カラムとして存在せず、`UNNEST`を使って展開する必要があります。このような複雑な変換処理こそ、dbtで管理するメリットが大きい場面です。

---

## dbtプロジェクトのセットアップとBigQuery接続

まずdbtをインストールし、BigQueryに接続する設定を行います。Pythonの環境（3.8以上）が前提となります。

```bash
pip install dbt-bigquery
dbt init my_ga4_project
```

初期化後、`~/.dbt/profiles.yml` にBigQueryの接続情報を記述します。サービスアカウントのJSONキーを使う方法が一般的です。

```yaml
my_ga4_project:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: your-gcp-project-id
      dataset: dbt_ga4_dev
      keyfile: /path/to/your/service-account.json
      threads: 4
      timeout_seconds: 300
      location: asia-northeast1
```

接続確認は以下のコマンドで行えます。

```bash
dbt debug
```

`All checks passed!` と表示されれば接続成功です。`dbt_ga4_dev` というデータセットがBigQuery上に自動で作成され、dbtが生成するテーブルやビューの置き場所になります。

---

## GA4イベントデータからセッション・流入元を抽出するモデルを作る

dbtでは、変換ロジックを「モデル」と呼ばれるSQLファイルとして記述します。`models/` ディレクトリ配下に `.sql` ファイルを置くだけで、dbtがBigQuery上のテーブルまたはビューとして作成してくれます。

GA4のBigQueryエクスポートテーブルからセッション単位のデータを作る例を見てみましょう。GA4のテーブルは `events_YYYYMMDD` という日付シャーディング形式で保存されています。

```sql
-- models/staging/stg_ga4_sessions.sql

WITH raw_events AS (
  SELECT
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得する
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `your-gcp-project-id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
),

sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_date) AS session_date,
    MIN(event_timestamp) AS session_start_ts,
    MAX(medium) AS medium,
    MAX(source) AS source
  FROM raw_events
  WHERE ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT * FROM sessions
```

このSQLを `models/staging/stg_ga4_sessions.sql` として保存し、`dbt run --select stg_ga4_sessions` を実行するだけで、BigQuery上にテーブルが生成されます。一度コードに落とせば、誰でも同じ結果を再現できます。

:::message
`collected_traffic_source.manual_medium` と `manual_source` は、GA4が手動タグ付け（UTMパラメータ）を自動的にセッション開始時のイベントに紐付けて格納したものです。Google広告経由のクリックには `gclid` が使われますが、メール施策やSNSの計測でUTMパラメータを付与している場合はこちらのカラムに値が入ります。
:::

---

## dbtのテスト機能でデータ品質を自動チェックする

データパイプラインを運用する上で見落とされがちなのが、データ品質の継続的な監視です。dbtにはSQLを書かなくてもデータ品質を検証できる「スキーマテスト」機能があります。

モデルと同じ `models/staging/` ディレクトリに `schema.yml` というファイルを作成します。

```yaml
# models/staging/schema.yml

version: 2

models:
  - name: stg_ga4_sessions
    description: "GA4のsession_startイベントをセッション単位に整形したステージングモデル"
    columns:
      - name: ga_session_id
        description: "セッションID（event_paramsより取得）"
        tests:
          - not_null
      - name: user_pseudo_id
        description: "匿名ユーザーID"
        tests:
          - not_null
      - name: session_date
        description: "セッション開始日"
        tests:
          - not_null
```

`dbt test` を実行すると、`ga_session_id` や `user_pseudo_id` にNULLが含まれていないかをBigQuery上で自動的に検証してくれます。テストが失敗した場合はエラーとして報告されるため、データの異常に早期に気づける仕組みを作ることができます。

:::message
dbtのテストはCIパイプライン（GitHub ActionsやCloud Buildなど）と組み合わせることで、SQLに変更を加えたタイミングで自動的にテストを実行する体制を構築できます。本番環境への変更を慎重に行いたい場合に特に有効です。
:::

---

## まとめ

本記事では、dbt × BigQueryを使ってGA4データを扱う再現可能なデータパイプラインを構築する基本的な手順を紹介しました。要点を整理します。

- **dbtはSQLをコードとして管理するツール**：BigQueryのコンソールに散らばっていたSQLをプロジェクトとして一元管理できます
- **GA4のga_session_idはUNNEST経由で取得**：直接カラムとしては存在しないため、`UNNEST(event_params)` による展開が必要です
- **流入元の取得には`collected_traffic_source`を使用**：UTMパラメータ経由の流入は`manual_medium`と`manual_source`に格納されています
- **スキーマテストでデータ品質を継続的に監視**：NULLチェックや一意性チェックをYAMLで定義するだけで自動化できます

次のステップとしては、セッションデータと購入イベントデータを結合した「コンバージョン分析モデル」を作成したり、dbt Cloudを使ってスケジュール実行の仕組みを整えたりすることが考えられます。段階的にモデルを追加していくことで、組織のデータ活用レベルを着実に高めていくことができます。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
