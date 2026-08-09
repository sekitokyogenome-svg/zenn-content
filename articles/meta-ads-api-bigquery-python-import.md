---
title: "Meta広告APIからBigQueryにデータを自動取得するPythonスクリプトの作り方"
emoji: "📊"
type: "tech"
topics: ["bigquery","python","googlecloud","advertising","dataengineering"]
published: false
---

## はじめに

Facebook広告やInstagram広告を運用していると、「毎朝レポートをダウンロードしてExcelに貼り付ける」という作業が日課になっている方も多いのではないでしょうか。広告費の増加とともに、キャンペーン数・広告セット数が増えると、この手作業は数十分〜1時間以上かかることもあります。

「もっとデータを深く分析したい」「GA4のデータと掛け合わせて広告効果を見たい」と感じていても、データがバラバラのまま散在していると、統合した分析はなかなか難しいものです。

そこで本記事では、Meta広告（Facebook・Instagram広告）のデータをAPIで自動取得し、Google BigQueryに蓄積するPythonスクリプトの実装方法をご紹介します。一度この仕組みを作っておけば、毎日のデータ収集は自動化でき、分析に集中できる環境が整います。エンジニアでなくても手順に沿って進められるよう、できるだけ丁寧に解説します。

---

## Meta広告APIとは？取得できるデータの概要

Meta広告APIは、Facebook・Instagramの広告データをプログラムから取得・操作するためのインターフェースです。Metaの広告マネージャー上で見られる数値は、基本的にAPIでも取得できます。

主に取得できるデータは以下のとおりです。

- **インプレッション数・リーチ数**
- **クリック数・CTR（クリック率）**
- **消化金額（spend）**
- **コンバージョン数・CPA**
- **動画再生数・再生率（動画広告の場合）**

取得の単位は「アカウント」「キャンペーン」「広告セット」「広告」と階層を選べます。また、日次・週次・月次などの期間指定も可能です。

:::message
Meta広告APIの利用には、Metaの開発者アカウント登録と、広告アカウントへのアクセス権を持つアクセストークンが必要です。取得手順はMeta for Developersの公式ドキュメントを参照してください。
:::

---

## 事前準備：認証情報とライブラリのセットアップ

### Metaアクセストークンの取得

1. [Meta for Developers](https://developers.facebook.com/) にアクセスし、アプリを作成します。
2. 「マーケティングAPI」を有効化します。
3. グラフAPIエクスプローラーで、`ads_read` スコープを含むアクセストークンを生成します。
4. 長期トークン（60日有効）に変換しておくと運用が楽になります。

### Google Cloudの準備

BigQueryへの書き込みには、サービスアカウントキーが必要です。

1. Google Cloud Consoleでプロジェクトを選択（または新規作成）します。
2. 「IAMと管理」→「サービスアカウント」からサービスアカウントを作成します。
3. 役割として「BigQuery データ編集者」「BigQuery ジョブ ユーザー」を付与します。
4. JSONキーをダウンロードし、安全な場所に保管します。

### Pythonライブラリのインストール

```bash
pip install facebook-business google-cloud-bigquery pandas pyarrow
```

---

## Pythonスクリプトの実装

以下は、Meta広告APIから広告セット単位の日次データを取得し、BigQueryに書き込むスクリプトの例です。

```python
import os
import json
from datetime import datetime, timedelta
import pandas as pd
from facebook_business.api import FacebookAdsApi
from facebook_business.adobjects.adaccount import AdAccount
from facebook_business.adobjects.adsinsights import AdsInsights
from google.cloud import bigquery
from google.oauth2 import service_account

# ---- 設定 ----
META_ACCESS_TOKEN = os.environ.get("META_ACCESS_TOKEN")
META_AD_ACCOUNT_ID = os.environ.get("META_AD_ACCOUNT_ID")  # "act_XXXXXXXXXX" 形式
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
BQ_DATASET = "meta_ads"
BQ_TABLE = "ad_insights_daily"
SERVICE_ACCOUNT_JSON = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")

# ---- Meta APIの初期化 ----
FacebookAdsApi.init(access_token=META_ACCESS_TOKEN)

# ---- 取得期間の設定（前日分）----
yesterday = (datetime.today() - timedelta(days=1)).strftime("%Y-%m-%d")

# ---- インサイトデータの取得 ----
def fetch_meta_insights(ad_account_id: str, date: str) -> list[dict]:
    account = AdAccount(ad_account_id)
    params = {
        "level": "adset",
        "time_range": {"since": date, "until": date},
        "time_increment": 1,
        "fields": [
            AdsInsights.Field.date_start,
            AdsInsights.Field.campaign_name,
            AdsInsights.Field.adset_name,
            AdsInsights.Field.impressions,
            AdsInsights.Field.clicks,
            AdsInsights.Field.spend,
            AdsInsights.Field.reach,
            AdsInsights.Field.ctr,
            AdsInsights.Field.cpc,
            AdsInsights.Field.conversions,
        ],
    }
    insights = account.get_insights(params=params)
    return [insight.export_all_data() for insight in insights]

# ---- BigQueryへの書き込み ----
def load_to_bigquery(rows: list[dict], project_id: str, dataset: str, table: str) -> None:
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_JSON,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
    client = bigquery.Client(project=project_id, credentials=credentials)

    df = pd.DataFrame(rows)
    # 型変換
    numeric_cols = ["impressions", "clicks", "spend", "reach", "ctr", "cpc"]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    table_ref = f"{project_id}.{dataset}.{table}"
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        autodetect=True,
    )
    job = client.load_table_from_dataframe(df, table_ref, job_config=job_config)
    job.result()
    print(f"{len(df)} 件のデータを {table_ref} に書き込みました。")

# ---- メイン処理 ----
if __name__ == "__main__":
    rows = fetch_meta_insights(META_AD_ACCOUNT_ID, yesterday)
    if rows:
        load_to_bigquery(rows, GCP_PROJECT_ID, BQ_DATASET, BQ_TABLE)
    else:
        print(f"{yesterday} のデータは0件でした。")
```

:::message
アクセストークンやサービスアカウントキーのパスは、スクリプト内に直接書かず、環境変数または Secret Manager などで管理することを推奨します。
:::

---

## BigQueryのテーブル設計と重複対策

上のスクリプトでは `WRITE_APPEND`（追記）モードを使用しています。毎日スクリプトを実行する運用では、同じ日付のデータが複数回追記されないよう、以下のような対策が有効です。

### 方法1：実行前に対象日付のデータを削除してから追記する

```python
def delete_existing_rows(client, project_id, dataset, table, date):
    query = f"""
        DELETE FROM `{project_id}.{dataset}.{table}`
        WHERE date_start = '{date}'
    """
    client.query(query).result()
    print(f"{date} の既存データを削除しました。")
```

メイン処理で `load_to_bigquery` の前に呼び出すことで、冪等性（何度実行しても同じ結果になる性質）を確保できます。

### 方法2：パーティションテーブルを使う

BigQueryの日付パーティションテーブルを利用すると、日次での上書きが管理しやすくなります。テーブル作成時に `date_start` カラムをパーティションキーに指定し、`WRITE_TRUNCATE` × パーティション指定で書き込む方法もあります。中長期的なデータ量増加を見越す場合は、パーティション設計を検討することをお勧めします。

---

## 定期実行の設定（Cloud Schedulerを使う場合）

スクリプトを毎日自動で動かすには、Google CloudのCloud Schedulerを使う方法が手軽です。

1. Pythonスクリプトを **Cloud Functions** または **Cloud Run** にデプロイします。
2. Cloud Schedulerでジョブを作成し、毎朝指定時刻にHTTPリクエストを送るよう設定します。

```bash
# Cloud Schedulerジョブの作成例（毎朝8時JST）
gcloud scheduler jobs create http meta-ads-daily-import \
  --schedule="0 8 * * *" \
  --time-zone="Asia/Tokyo" \
  --uri="https://REGION-PROJECT_ID.cloudfunctions.net/meta_ads_import" \
  --http-method=POST \
  --message-body="{}"
```

より手軽に試したい場合は、ローカルPCの **cron（Mac/Linux）** やWindowsの **タスクスケジューラ** でスクリプトを定期実行する方法もあります。ただし、PCが起動していないと実行されないため、安定運用にはクラウド環境の利用をお勧めします。

:::message
Cloud Functionsを使う場合、実行時間の上限（デフォルト60秒）に注意してください。広告アカウントの規模が大きい場合は、タイムアウトを延長するか、Cloud Runへの移行を検討してください。
:::

---

## まとめ

本記事では、Meta広告APIからBigQueryに日次データを自動取得するPythonスクリプトの実装手順を解説しました。要点を整理します。

- Meta広告APIを使うと、広告マネージャーの数値をプログラムで取得できる
- `facebook-business` ライブラリと `google-cloud-bigquery` ライブラリを組み合わせることで、データ収集からBigQuery格納までをPythonで一本化できる
- 重複データの防止には、実行前の削除処理またはパーティションテーブルの活用が有効
- Cloud SchedulerとCloud Functionsを組み合わせることで、完全自動化が実現できる

BigQueryにデータが蓄積されると、Looker Studioでのダッシュボード作成や、GA4のデータと結合した費用対効果の分析など、さらに幅広い活用が可能になります。まずは小さな広告アカウントで動作確認しながら、自社の運用に合った形に調整してみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
