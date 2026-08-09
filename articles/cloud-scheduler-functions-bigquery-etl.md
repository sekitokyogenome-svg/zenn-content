---
title: "Cloud Scheduler × Cloud Functions × BigQueryで完全サーバーレスなETLを構築する"
emoji: "⚙️"
type: "tech"
topics: ["bigquery","googlecloud","python","dataengineering","sql"]
published: false
book_only: true
---

## はじめに

「毎朝9時になったら、昨日のGA4データをBigQueryに集計して、Googleスプレッドシートに書き出したい」――そんなご要望をEC事業者やWebコンサルタントの方からよくいただきます。しかし、その実現のために専用のサーバーを立てて24時間稼働させるのは、コスト面でも管理面でも負担が大きいのが実情です。

そこで活用したいのが、Google Cloudが提供するサーバーレスサービスの組み合わせです。Cloud Scheduler（定期実行）× Cloud Functions（処理ロジック）× BigQuery（データ分析基盤）を連携させることで、サーバーの管理なしに自動ETL（Extract・Transform・Load）パイプラインを構築できます。

本記事では、この3サービスの役割と連携方法を整理しながら、GA4データの集計を例に実装手順をご説明します。エンジニアでない方にも全体像が伝わるよう、概念から丁寧に解説していきますので、ぜひ最後までお読みください。

## サーバーレスETLの全体像と各サービスの役割

まず、3つのサービスがどのような役割を担うかを整理しておきましょう。

| サービス | 役割 | 料金の目安 |
|---|---|---|
| Cloud Scheduler | cron形式で定期的にHTTPリクエストを送信 | 月3ジョブまで無料 |
| Cloud Functions | HTTPリクエストをトリガーにPythonコードを実行 | 月200万回まで無料 |
| BigQuery | SQLによるデータ集計・格納 | 月10GBクエリまで無料 |

処理の流れは次のとおりです。

1. Cloud Schedulerが毎朝9時にCloud FunctionsのエンドポイントへHTTP POSTを送信
2. Cloud FunctionsがPythonコードを実行し、BigQueryに対してSQLクエリを発行
3. BigQueryがGA4エクスポートテーブルを集計し、結果をサマリーテーブルへ書き込む

この構成の利点は、実行中のみ課金が発生し、アイドル時のコストがほぼゼロである点です。1日1回・数秒で完了するバッチ処理であれば、Google Cloudの無料枠の範囲内に収まるケースも多くあります。

## Cloud Functionsの実装 — PythonでBigQueryを呼び出す

Cloud FunctionsにデプロイするPythonコードの例を示します。`google-cloud-bigquery` ライブラリを使用して、BigQueryにクエリを発行し、集計結果を別テーブルへ書き込む処理です。

```python
import functions_framework
from google.cloud import bigquery
from datetime import date, timedelta

PROJECT_ID = "your-project-id"
DATASET_ID = "your_dataset"
GA4_TABLE  = f"{PROJECT_ID}.analytics_XXXXXXXX.events_*"
DEST_TABLE = f"{PROJECT_ID}.{DATASET_ID}.daily_session_summary"

@functions_framework.http
def run_etl(request):
    """HTTP Cloud Function: 前日のGA4データを集計してサマリーテーブルへ書き込む"""
    client = bigquery.Client(project=PROJECT_ID)

    yesterday = (date.today() - timedelta(days=1)).strftime("%Y%m%d")

    query = f"""
    SELECT
      event_date,
      collected_traffic_source.manual_medium AS medium,
      collected_traffic_source.manual_source AS source,
      COUNT(DISTINCT
        (SELECT value.string_value
         FROM UNNEST(event_params) AS ep
         WHERE ep.key = 'ga_session_id')
      ) AS sessions
    FROM `{GA4_TABLE}`
    WHERE _TABLE_SUFFIX = '{yesterday}'
      AND event_name = 'session_start'
    GROUP BY 1, 2, 3
    """

    job_config = bigquery.QueryJobConfig(
        destination=DEST_TABLE,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )

    job = client.query(query, job_config=job_config)
    job.result()  # 完了まで待機

    return f"ETL completed for {yesterday}", 200
```

:::message
`analytics_XXXXXXXX` の部分はGA4のBigQueryエクスポートで発行されるプロパティIDに置き換えてください。プロパティIDはGA4管理画面の「BigQueryリンク」設定から確認できます。
:::

コードのポイントをまとめると次のとおりです。

- `ga_session_id` は `event_params` カラムを `UNNEST` して取得しています。GA4のBigQueryエクスポートではイベントパラメータがネストされた配列で格納されるため、直接カラム参照はできません。
- 流入元（参照元・メディア）は `collected_traffic_source.manual_source` / `manual_medium` から取得します。これはGA4がセッション単位で付与するトラフィックソース情報です。
- `write_disposition=WRITE_APPEND` を指定することで、毎日の結果を蓄積型で追記していきます。

## Cloud Functionsのデプロイ手順

ローカル環境またはCloud Shellから以下のコマンドでデプロイできます。

```bash
# 依存パッケージを記述した requirements.txt を用意する
echo "functions-framework==3.*
google-cloud-bigquery==3.*" > requirements.txt

# Cloud Functions（第2世代）としてデプロイ
gcloud functions deploy run-etl \
  --gen2 \
  --runtime=python312 \
  --region=asia-northeast1 \
  --source=. \
  --entry-point=run_etl \
  --trigger-http \
  --no-allow-unauthenticated \
  --service-account=etl-runner@your-project-id.iam.gserviceaccount.com \
  --timeout=300s
```

:::message
`--no-allow-unauthenticated` を指定することで、認証されたリクエストのみ受け付ける設定になります。Cloud SchedulerからのリクエストにはOIDCトークンを付与する必要がありますが、後述の設定で自動的に対応できます。
:::

デプロイが完了すると、コンソールにHTTPSエンドポイントのURLが表示されます。このURLをメモしておいてください。

## Cloud Schedulerの設定 — 毎朝9時に自動実行

Cloud Schedulerのジョブ設定はGUIからでも行えますが、gcloudコマンドで行う場合は次のとおりです。

```bash
gcloud scheduler jobs create http daily-etl-job \
  --location=asia-northeast1 \
  --schedule="0 9 * * *" \
  --time-zone="Asia/Tokyo" \
  --uri="https://asia-northeast1-your-project-id.cloudfunctions.net/run-etl" \
  --http-method=POST \
  --oidc-service-account-email=etl-runner@your-project-id.iam.gserviceaccount.com \
  --oidc-token-audience="https://asia-northeast1-your-project-id.cloudfunctions.net/run-etl"
```

`--schedule="0 9 * * *"` はcron式で「毎日9時0分」を意味します。`--time-zone="Asia/Tokyo"` を指定しないとUTCで実行されるため、日本時間で動かす際は明示的に設定してください。

Cloud Schedulerのジョブを作成したら、コンソールの「今すぐ実行」ボタンで動作確認を行うことを推奨します。Cloud FunctionsのログはCloud Loggingで確認でき、エラーが発生した場合は詳細なスタックトレースが出力されます。

## BigQueryの集計結果をスプレッドシートや可視化ツールへ連携する

サマリーテーブルにデータが蓄積されたら、そのデータをビジネス活用につなげましょう。BigQueryにはいくつかの出力先が選択肢として挙げられます。

**Looker Studioとの連携**

Looker Studio（旧データポータル）はBigQueryをネイティブデータソースとして接続できます。`daily_session_summary` テーブルを参照するだけで、流入元別のセッション数推移グラフを数クリックで作成できます。ダッシュボードは自動更新されるため、毎朝ETLが完了したあとにレポートを開くだけで最新データを確認できます。

**Googleスプレッドシートへのエクスポート**

Cloud FunctionsのコードにGoogleスプレッドシートへの書き込み処理を追加することも可能です。`gspread` ライブラリと `google-auth` を組み合わせることで、BigQueryの集計結果をスプレッドシートの特定シートへ直接書き出せます。非エンジニアのメンバーへの共有や、既存のExcelベースの業務フローとの橋渡しとして有効な選択肢です。

**アラート通知との組み合わせ**

Cloud Functionsの処理内でセッション数が前日比で大きく減少している場合にSlackやメールへ通知するロジックを追加することで、異常検知の仕組みとしても活用できます。ETLとアラートを同一のFunctionsにまとめると管理がシンプルになります。

## まとめ

本記事では、Cloud Scheduler × Cloud Functions × BigQueryを組み合わせたサーバーレスETLの構築方法を解説しました。要点を整理すると次のとおりです。

- **Cloud Scheduler** でcron形式の定期実行トリガーを設定する
- **Cloud Functions** にPythonでBigQueryクエリを発行する処理をデプロイする
- **BigQuery** でGA4のエクスポートテーブルを集計し、サマリーテーブルに蓄積する
- `ga_session_id` の取得には `UNNEST(event_params)` が必要、流入元は `collected_traffic_source` を使用する
- 認証は `--no-allow-unauthenticated` + OIDCトークンで適切に保護する

この構成の最大のメリットは、専用サーバーを持たずに定期バッチ処理を運用できることです。Google Cloudの無料枠を活用すれば、小規模な運用であれば月間コストをほぼゼロに近い水準に抑えることも期待できます。

次のステップとしては、エラー発生時のリトライ設定（Cloud Schedulerのリトライポリシー）や、Cloud Monitoringを用いたジョブ失敗アラートの整備が考えられます。まずは本記事の構成で動かしてみて、実運用の中でニーズに合わせて拡張していくとよいでしょう。

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
