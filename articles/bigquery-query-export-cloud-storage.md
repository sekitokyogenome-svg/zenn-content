---
title: "BigQueryのクエリ結果をCloud Storageに自動エクスポートして外部ツール連携する"
emoji: "📤"
type: "tech"
topics: ["bigquery","googlecloud","sql","dataengineering","python"]
published: false
---

## はじめに

BigQueryで集計したデータを、毎週手動でCSVにエクスポートして担当者へメール添付している——そのような作業に時間を取られていないでしょうか。分析結果はあるのに「届ける仕組み」が整っていないため、データ活用が一部の人だけで止まってしまうケースは少なくありません。

BigQueryには、クエリ結果をGoogle Cloud Storage（GCS）へ自動エクスポートする機能が備わっています。GCSに保存されたファイルは、スプレッドシートへの自動取り込み、外部BIツールへの連携、Slackへの通知など、さまざまなツールと組み合わせて活用できます。

本記事では、GA4のBigQueryエクスポートデータを例に、クエリ実行→GCSへのエクスポート→外部ツール連携という一連の流れをステップごとに解説します。SQLやPythonの経験が浅い方でも手順を追えるよう、コード例と注意点を丁寧に記載しました。

---

## なぜCloud Storageを経由するのか

BigQueryのデータを外部ツールへ渡す方法は複数あります。BigQuery APIを直接叩く方法もありますが、GCSを経由するアプローチには以下のメリットがあります。

- **ファイルとして残る**：CSV・JSON・Parquetなど任意の形式で保存できるため、後からでも参照・再利用が可能です。
- **権限管理がシンプル**：GCSバケットへのアクセス権を絞ることで、BigQueryプロジェクトへの直接アクセスを不要にできます。
- **多様なツールと親和性が高い**：Google スプレッドシート、Looker Studio、各種ETLツール、Pythonスクリプトなど、GCSからファイルを読み込む手段は豊富です。
- **スケジュール実行との相性が良い**：Cloud Schedulerと組み合わせると、決まった時間に自動でエクスポートされる仕組みを構築できます。

小規模なECサイトやWebサービスでも、一度仕組みを整えておくことで、レポーティングにかかる手間を大幅に削減できます。

---

## GA4データをBigQueryで集計するSQLの書き方

GA4のBigQueryエクスポートテーブルには独自の構造があります。特にイベントパラメータはネストされた配列になっているため、通常のSQLとは少し異なる書き方が必要です。

以下は、流入元・メディア別のセッション数と購入数を集計するSQLの例です。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC
;
```

:::message
`ga_session_id` はイベントテーブルの直接カラムとしては存在せず、`event_params` 配列の中に格納されています。`UNNEST(event_params)` で展開し、`ep.key = 'ga_session_id'` で絞り込んで取得してください。直接 `ga_session_id` を参照するとエラーになります。
:::

`collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` は、UTMパラメータで付与した流入元情報を参照するカラムです。GA4の自動的なチャネル分類ではなく、URLに手動設定したパラメータ値を正確に取得できます。

---

## BigQueryからCloud Storageへエクスポートする方法

BigQueryのクエリ結果をGCSへエクスポートするには、主に3つの方法があります。

### 方法1：BigQueryコンソールから手動エクスポート

最も手軽な方法です。クエリ実行後に「結果を保存」→「Cloud Storageにエクスポート」を選択し、バケット名とファイル形式を指定するだけで完了します。定期的な自動化は難しいですが、一時的なデータ出力には向いています。

### 方法2：クエリでテーブルを作成し、`bq extract` コマンドでエクスポート

コマンドラインツール `bq` を使う方法です。まずクエリ結果を一時テーブルに保存し、その後 `bq extract` でGCSへ書き出します。

```bash
# クエリ結果を一時テーブルに保存
bq query \
  --use_legacy_sql=false \
  --destination_table=your_project:temp_dataset.session_report \
  --replace=true \
  'SELECT ... FROM ...'

# 一時テーブルをGCSへエクスポート
bq extract \
  --field_delimiter=',' \
  --print_header=true \
  your_project:temp_dataset.session_report \
  gs://your-bucket/reports/session_report_$(date +%Y%m%d).csv
```

### 方法3：PythonのBigQueryクライアントライブラリを使う（推奨）

自動化・定期実行を見据えるなら、Pythonスクリプトによる実装がおすすめです。次のセクションで詳しく説明します。

---

## PythonでBigQuery→GCS自動エクスポートを実装する

`google-cloud-bigquery` ライブラリを使うと、クエリ実行からGCSエクスポートまでをコードで一括管理できます。Cloud FunctionsやCloud RunのジョブからこのスクリプトをCloud Schedulerで定期起動すれば、完全な自動化が実現します。

まずライブラリをインストールします。

```bash
pip install google-cloud-bigquery google-cloud-storage
```

次に、エクスポートスクリプトを実装します。

```python
from google.cloud import bigquery
from datetime import datetime

PROJECT_ID = "your_project"
DATASET_ID = "temp_dataset"
TABLE_ID = "session_report"
GCS_BUCKET = "your-bucket"
GCS_PREFIX = "reports"

def export_bq_to_gcs():
    client = bigquery.Client(project=PROJECT_ID)

    # 集計クエリ
    query = """
    SELECT
      collected_traffic_source.manual_medium AS medium,
      collected_traffic_source.manual_source AS source,
      COUNT(DISTINCT
        (SELECT ep.value.int_value
         FROM UNNEST(event_params) AS ep
         WHERE ep.key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases
    FROM
      `your_project.analytics_XXXXXXXXX.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    GROUP BY medium, source
    ORDER BY sessions DESC
    """

    # クエリ結果を一時テーブルへ保存
    dest_table = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"
    job_config = bigquery.QueryJobConfig(
        destination=dest_table,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    query_job = client.query(query, job_config=job_config)
    query_job.result()  # 完了まで待機
    print(f"クエリ完了: {dest_table} にデータを書き込みました")

    # GCSへエクスポート
    today = datetime.today().strftime("%Y%m%d")
    gcs_uri = f"gs://{GCS_BUCKET}/{GCS_PREFIX}/session_report_{today}.csv"
    extract_config = bigquery.ExtractJobConfig(
        field_delimiter=",",
        print_header=True,
    )
    extract_job = client.extract_table(
        dest_table,
        gcs_uri,
        job_config=extract_config,
    )
    extract_job.result()
    print(f"GCSエクスポート完了: {gcs_uri}")

if __name__ == "__main__":
    export_bq_to_gcs()
```

:::message
スクリプトを実行するサービスアカウントには、BigQueryへの `roles/bigquery.jobUser` と `roles/bigquery.dataEditor`、GCSバケットへの `roles/storage.objectCreator` 権限が必要です。最小権限の原則に従い、必要な権限のみを付与してください。
:::

---

## Cloud Schedulerで定期自動実行する

Pythonスクリプトをそのまま手動実行するだけでは自動化とは言えません。Cloud Schedulerと組み合わせることで、毎週月曜日の朝8時など、指定したタイミングで自動実行できます。

おすすめの構成は以下の通りです。

1. **Cloud Run Jobs**：上記のPythonスクリプトをDockerイメージ化してデプロイします。
2. **Cloud Scheduler**：Cronスケジュール形式でCloud Run Jobsを定期起動します。

```bash
# Cloud Schedulerジョブの作成例（毎週月曜 8:00 JST）
gcloud scheduler jobs create http weekly-bq-export \
  --schedule="0 8 * * 1" \
  --time-zone="Asia/Tokyo" \
  --uri="https://REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/PROJECT_ID/jobs/bq-export-job:run" \
  --oauth-service-account-email=your-sa@your-project.iam.gserviceaccount.com \
  --http-method=POST
```

GCSに保存されたCSVは、Google スプレッドシートの `IMPORTDATA` 関数や、Looker Studioのデータソース設定から直接参照できます。Slackへの通知が必要な場合は、GCSの「オブジェクト確定通知（Pub/Sub）」を使い、Cloud FunctionsでWebhookを叩く構成も選択肢の一つです。

---

## まとめ

本記事では、BigQueryのクエリ結果をCloud Storageへ自動エクスポートし、外部ツールと連携する方法を解説しました。要点を整理します。

- GCSを経由することで、ファイル形式の柔軟性・権限管理・外部ツール連携のしやすさが向上します。
- GA4のBigQueryデータを扱う際は、`ga_session_id` は `UNNEST(event_params)` 経由で取得し、流入元は `collected_traffic_source.manual_medium/manual_source` を参照します。
- PythonのBigQueryクライアントライブラリを使うことで、クエリ実行からエクスポートまでをコードで一元管理できます。
- Cloud Scheduler + Cloud Run Jobsの組み合わせで、完全な自動化が実現します。

まずはコンソールからの手動エクスポートを試し、仕組みを理解してから自動化へステップアップするのがおすすめです。データを「集めるだけ」ではなく「届ける仕組み」まで整えることで、分析結果がビジネスの意思決定に活かされやすくなります。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [BigQueryでGA4データをdbtで管理する入門](https://zenn.dev/web_benriya/articles/bigquery-ga4-dbt-management-intro)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
