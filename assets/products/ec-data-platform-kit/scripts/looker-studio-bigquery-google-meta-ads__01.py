"""Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する

出典記事: articles/looker-studio-bigquery-google-meta-ads.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
meta_ads_to_bq.py
目的: Meta Marketing APIから広告データを取得しBigQueryにロード
作成日: 2026-03-30
依存: facebook-business, google-cloud-bigquery, python-dotenv
"""

import os
from datetime import datetime, timedelta
from dotenv import load_dotenv
from facebook_business.api import FacebookAdsApi
from facebook_business.adobjects.adaccount import AdAccount
from google.cloud import bigquery

load_dotenv()

# Meta API初期化
FacebookAdsApi.init(
    app_id=os.getenv('META_APP_ID'),
    app_secret=os.getenv('META_APP_SECRET'),
    access_token=os.getenv('META_ACCESS_TOKEN')
)

def fetch_meta_ads_data(account_id, start_date, end_date):
    """Meta広告のキャンペーン日別データを取得"""
    account = AdAccount(f'act_{account_id}')
    params = {
        'time_range': {
            'since': start_date,
            'until': end_date
        },
        'time_increment': 1,
        'level': 'campaign'
    }
    fields = [
        'campaign_name',
        'spend',
        'impressions',
        'clicks',
        'actions',
        'action_values'
    ]

    try:
        insights = account.get_insights(params=params, fields=fields)
        rows = []
        for row in insights:
            purchases = 0
            purchase_value = 0
            if 'actions' in row:
                for action in row['actions']:
                    if action['action_type'] == 'purchase':
                        purchases = int(action['value'])
            if 'action_values' in row:
                for av in row['action_values']:
                    if av['action_type'] == 'purchase':
                        purchase_value = float(av['value'])
            rows.append({
                'date': row['date_start'],
                'campaign_name': row['campaign_name'],
                'spend': float(row.get('spend', 0)),
                'impressions': int(row.get('impressions', 0)),
                'clicks': int(row.get('clicks', 0)),
                'purchases': purchases,
                'purchase_value': purchase_value
            })
        return rows
    except Exception as e:
        print(f'Meta API取得エラー: {e}')
        return []

def load_to_bigquery(rows, table_id):
    """BigQueryにデータをロード"""
    client = bigquery.Client()
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField('date', 'DATE'),
            bigquery.SchemaField('campaign_name', 'STRING'),
            bigquery.SchemaField('spend', 'FLOAT'),
            bigquery.SchemaField('impressions', 'INTEGER'),
            bigquery.SchemaField('clicks', 'INTEGER'),
            bigquery.SchemaField('purchases', 'INTEGER'),
            bigquery.SchemaField('purchase_value', 'FLOAT'),
        ]
    )
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()
    print(f'{len(rows)}行をBigQueryにロード完了')
