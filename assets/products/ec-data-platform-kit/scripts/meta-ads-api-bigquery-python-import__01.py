"""Meta広告APIからBigQueryにデータを自動取得するPythonスクリプトの作り方

出典記事: articles/meta-ads-api-bigquery-python-import.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
