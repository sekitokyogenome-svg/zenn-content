"""ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る

出典記事: articles/shopify-webhook-cloud-functions-bigquery-realtime.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import functions_framework
import json
import hmac
import hashlib
import base64
import os
from google.cloud import bigquery
from datetime import datetime, timezone

SHOPIFY_SECRET = os.environ.get("SHOPIFY_WEBHOOK_SECRET", "")
BQ_PROJECT = os.environ.get("BQ_PROJECT_ID", "your-project-id")
BQ_DATASET = os.environ.get("BQ_DATASET", "shopify_raw")
BQ_TABLE = os.environ.get("BQ_TABLE", "orders")

def verify_shopify_hmac(data: bytes, hmac_header: str) -> bool:
    """ShopifyのHMACシグネチャを検証する"""
    digest = hmac.new(
        SHOPIFY_SECRET.encode("utf-8"),
        data,
        digestmod=hashlib.sha256
    ).digest()
    computed = base64.b64encode(digest).decode("utf-8")
    return hmac.compare_digest(computed, hmac_header)

@functions_framework.http
def shopify_webhook(request):
    # シグネチャ検証
    hmac_header = request.headers.get("X-Shopify-Hmac-Sha256", "")
    body = request.get_data()
    if not verify_shopify_hmac(body, hmac_header):
        return ("Unauthorized", 401)

    # JSONパース
    payload = json.loads(body)
    order_id = str(payload.get("id", ""))
    total_price = float(payload.get("total_price", 0))
    currency = payload.get("currency", "")
    email = payload.get("email", "")
    created_at = payload.get("created_at", "")
    financial_status = payload.get("financial_status", "")

    # BigQueryへ書き込み
    client = bigquery.Client(project=BQ_PROJECT)
    table_ref = f"{BQ_PROJECT}.{BQ_DATASET}.{BQ_TABLE}"
    rows = [{
        "order_id": order_id,
        "total_price": total_price,
        "currency": currency,
        "email": email,
        "financial_status": financial_status,
        "created_at": created_at,
        "ingested_at": datetime.now(timezone.utc).isoformat(),
    }]
    errors = client.insert_rows_json(table_ref, rows)
    if errors:
        return (f"BigQuery error: {errors}", 500)
    return ("OK", 200)
