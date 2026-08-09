"""Claude CodeでGA4のイベント設計書を自動生成する方法

出典記事: articles/claude-code-ga4-event-design-doc.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: event_catalog_builder.py
目的: GA4イベント一覧をBigQueryから取得しカタログデータを構築する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
import json

def fetch_event_summary(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """イベントのサマリー情報を取得する"""
    query = f"""
    SELECT
      event_name,
      COUNT(*) AS event_count,
      COUNT(DISTINCT user_pseudo_id) AS unique_users,
      MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_seen,
      MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_seen
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY event_name
    ORDER BY event_count DESC
    """
    return client.query(query).to_dataframe()

def fetch_event_params(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """イベントパラメータの詳細を取得する"""
    query = f"""
    SELECT
      event_name,
      ep.key AS param_key,
      CASE
        WHEN ep.value.string_value IS NOT NULL THEN 'string'
        WHEN ep.value.int_value IS NOT NULL THEN 'int'
        WHEN ep.value.float_value IS NOT NULL THEN 'float'
        ELSE 'unknown'
      END AS param_type,
      COUNT(*) AS occurrence_count
    FROM
      `{project_id}.{dataset}.events_*`,
      UNNEST(event_params) AS ep
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY event_name, param_key, param_type
    ORDER BY event_name, occurrence_count DESC
    """
    return client.query(query).to_dataframe()

def build_event_catalog(summary_df: pd.DataFrame, params_df: pd.DataFrame) -> list[dict]:
    """イベントカタログのデータ構造を構築する"""
    catalog = []
    for _, row in summary_df.iterrows():
        event_name = row['event_name']
        event_params = params_df[params_df['event_name'] == event_name]

        params_list = []
        for _, p in event_params.iterrows():
            params_list.append({
                'key': p['param_key'],
                'type': p['param_type'],
                'count': int(p['occurrence_count'])
            })

        catalog.append({
            'event_name': event_name,
            'event_count': int(row['event_count']),
            'unique_users': int(row['unique_users']),
            'first_seen': str(row['first_seen']),
            'last_seen': str(row['last_seen']),
            'category': classify_event(event_name),
            'params': params_list
        })

    return catalog

def classify_event(event_name: str) -> str:
    """イベントをカテゴリに分類する"""
    auto_events = [
        'first_visit', 'session_start', 'user_engagement',
        'page_view', 'scroll', 'click', 'file_download',
        'video_start', 'video_progress', 'video_complete',
        'view_search_results'
    ]
    ecommerce_events = [
        'view_item', 'view_item_list', 'select_item',
        'add_to_cart', 'remove_from_cart', 'view_cart',
        'begin_checkout', 'add_payment_info', 'add_shipping_info',
        'purchase', 'refund'
    ]

    if event_name in auto_events:
        return '自動収集イベント'
    elif event_name in ecommerce_events:
        return 'ecommerceイベント'
    elif event_name.startswith('gtm'):
        return 'GTM自動イベント'
    else:
        return 'カスタムイベント'
