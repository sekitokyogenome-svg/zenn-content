"""Google広告のオフラインコンバージョンをBigQuery経由で自動化する

出典記事: articles/google-ads-offline-conversion-bigquery-auto.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

from google.ads.googleads.client import GoogleAdsClient
from google.cloud import bigquery
from datetime import datetime, timezone

# クライアントの初期化
bq_client = bigquery.Client(project="your_project")
ads_client = GoogleAdsClient.load_from_storage("google-ads.yaml")
customer_id = "1234567890"  # ハイフンなし

def fetch_conversions_from_bq():
    """BigQueryからアップロード対象のコンバージョンを取得する"""
    query = """
        SELECT
            gclid,
            conversion_time,
            conversion_name,
            conversion_value,
            currency_code
        FROM
            `your_project.ads_dataset.offline_conversions_ready`
        WHERE
            DATE(conversion_time) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    """
    rows = bq_client.query(query).result()
    return list(rows)

def upload_offline_conversion(row):
    """1件のコンバージョンデータをGoogle広告APIに送信する"""
    service = ads_client.get_service("ConversionUploadService")
    click_conversion = ads_client.get_type("ClickConversion")

    click_conversion.gclid = row["gclid"]
    click_conversion.conversion_action = ads_client.get_service(
        "ConversionActionService"
    ).conversion_action_path(customer_id, "YOUR_CONVERSION_ACTION_ID")

    # conversion_timeはUTC形式で指定（例: "2026-07-31 12:00:00+00:00"）
    dt = row["conversion_time"].replace(tzinfo=timezone.utc)
    click_conversion.conversion_date_time = dt.strftime("%Y-%m-%d %H:%M:%S+00:00")
    click_conversion.conversion_value = float(row["conversion_value"] or 0)
    click_conversion.currency_code = row["currency_code"]

    request = ads_client.get_type("UploadClickConversionsRequest")
    request.customer_id = customer_id
    request.conversions.append(click_conversion)
    request.partial_failure = True

    response = service.upload_click_conversions(request=request)
    if response.partial_failure_error:
        print(f"[WARN] Partial failure: {response.partial_failure_error}")
    return response

def main():
    conversions = fetch_conversions_from_bq()
    print(f"{len(conversions)} 件のコンバージョンをアップロードします")
    for row in conversions:
        upload_offline_conversion(row)
        print(f"アップロード完了: gclid={row['gclid']}")

if __name__ == "__main__":
    main()
