---
title: "Google広告のオフラインコンバージョンをBigQuery経由で自動化する"
emoji: "📥"
type: "tech"
topics: ["bigquery","googleads","googlecloud","sql","advertising"]
published: false
---

## はじめに

Google広告を運用していると、「広告経由で問い合わせが来たけれど、実際に成約したのは2週間後だった」というケースに頻繁に遭遇します。このような場合、管理画面上のコンバージョン数はゼロのまま計上されず、広告の貢献度が正しく評価されません。その結果、費用対効果の悪い施策に予算が集中したり、本来は成果を上げている施策が停止されたりするリスクがあります。

こうした課題を解決する仕組みが「オフラインコンバージョンインポート（Offline Conversion Import / OCI）」です。Google広告の管理画面上で計測できないオフラインの成約情報を、後からGoogle広告に送信して機械学習の最適化に活用できます。

とはいえ、手動でCSVを毎日作成してアップロードするのは現実的ではありません。本記事では、BigQueryとGoogle広告APIを組み合わせて、オフラインコンバージョンのインポートを自動化するパイプラインを構築する方法を解説します。エンジニアでない方でもおおよその流れがつかめるよう、できるだけ丁寧に説明していきます。

## オフラインコンバージョンインポートとはなにか

### 仕組みの概要

オフラインコンバージョンインポートとは、Google広告で広告をクリックしたユーザーが、後日電話・対面・CRMシステム上で成約した際に、その事実をGoogle広告側へ通知する仕組みです。

具体的な流れは以下のとおりです。

1. ユーザーが広告をクリックすると、Google広告はそのクリックに固有のID（GCLID）を付与します。
2. 貴社のランディングページでこのGCLIDをフォームの隠しフィールドやCRMに保存します。
3. 後日、成約・商談化などのイベントが発生したとき、GCLIDと成約日時・コンバージョン名をセットでGoogle広告APIに送信します。
4. Google広告はそのデータを受け取り、機械学習モデルの最適化（tCPA・tROASなど）に反映します。

### なぜBigQueryを介するのか

多くの場合、GCLIDはGA4のイベントとともにBigQueryエクスポートに蓄積されています。一方、成約データはCRMやSFAに存在します。BigQueryを中継点にすることで、両者のデータを結合し、整形した上でAPIへ渡すワークフローを構築できます。Cloud SchedulerやCloud Functionsと組み合わせることで、人手を介さずに毎日自動実行させることが可能です。

## BigQueryでGCLIDとコンバージョンデータを準備する

### GA4 BigQueryエクスポートからGCLIDを取得する

GA4をBigQueryにエクスポートしている場合、`events_*` テーブルにGCLIDが格納されています。セッションIDはevent_paramsをUNNESTして取得します。また、流入元情報は `collected_traffic_source` 列から参照します。

```sql
-- GA4 BigQueryエクスポートからGCLIDを抽出するクエリ例
SELECT
  user_pseudo_id,
  event_date,
  event_timestamp,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'gclid') AS gclid,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
  AND collected_traffic_source.manual_medium = 'cpc'
```

このクエリでは、過去90日分のGoogle広告クリック（medium = 'cpc'）から発生したセッションのGCLIDを取得しています。GCLIDはevent_paramsの中に格納されているため、キーを指定してUNNESTで取り出しています。

### CRMデータと結合してコンバージョンテーブルを作る

CRMやSFAの成約データをBigQueryにインポートしておくことで、GCLIDと突き合わせができます。以下は結合クエリの例です。

```sql
-- GCLIDと成約データを結合してインポート用テーブルを作成
WITH gclid_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'gclid') AS gclid,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS click_date
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
),
conversions AS (
  SELECT
    user_email,
    contract_date,
    contract_value,
    crm_user_id
  FROM
    `your_project.crm_dataset.contracts`
  WHERE
    contract_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)
SELECT
  g.gclid,
  c.contract_date AS conversion_time,
  'Offline_Contract' AS conversion_name,
  c.contract_value AS conversion_value,
  'JPY' AS currency_code
FROM
  gclid_sessions g
  INNER JOIN `your_project.crm_dataset.users` u
    ON g.user_pseudo_id = u.ga_user_pseudo_id
  INNER JOIN conversions c
    ON u.user_email = c.user_email
WHERE
  g.gclid IS NOT NULL
```

この結果テーブルを `your_project.ads_dataset.offline_conversions_ready` のような形で保存しておくと、後続の処理から参照しやすくなります。

## Google広告APIへのアップロード処理を実装する

### Python + google-ads ライブラリを使った送信スクリプト

Google広告の公式Pythonライブラリを使ってオフラインコンバージョンをアップロードします。まずライブラリをインストールします。

```bash
pip install google-ads google-cloud-bigquery
```

次に、BigQueryから取得したデータをGoogle広告APIに送信するスクリプトを作成します。

```python
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
```

:::message
`google-ads.yaml` にはdeveloper_token・client_id・client_secret・refresh_tokenを記載します。本番環境ではSecret Managerを使って機密情報を管理することをお勧めします。
:::

## Cloud Schedulerで毎日自動実行する

### Cloud Functionsにスクリプトをデプロイする

上記Pythonスクリプトを `main.py` として保存し、Cloud Functionsにデプロイします。

```bash
gcloud functions deploy upload_offline_conversions \
  --runtime python311 \
  --trigger-http \
  --entry-point main \
  --region asia-northeast1 \
  --set-env-vars GCP_PROJECT=your_project \
  --timeout 300s
```

### Cloud Schedulerでトリガーを設定する

毎朝9時（JST）に実行するようにスケジュールを設定します。

```bash
gcloud scheduler jobs create http offline-conversion-daily \
  --schedule "0 0 * * *" \
  --uri "https://asia-northeast1-your_project.cloudfunctions.net/upload_offline_conversions" \
  --time-zone "Asia/Tokyo" \
  --http-method POST
```

:::message
Cloud SchedulerのcronはUTCで動作するため、JST 9:00に実行したい場合は `0 0 * * *`（UTC 0:00）を指定します。スケジュール設定時は必ずタイムゾーンを `Asia/Tokyo` に指定して意図した時刻に動作するよう確認してください。
:::

## 注意点とよくあるトラブル

### GCLIDの有効期限

GCLIDには有効期限があり、クリックから90日以内に送信する必要があります。また、コンバージョンの発生日時とアップロード日時の差が大きすぎると管理画面への反映が遅れる場合があります。CRMの成約データはなるべく早めにBigQueryへ取り込む仕組みを用意しておくとよいでしょう。

### コンバージョンアクションの事前設定

Google広告の管理画面で「インポート > 他のデータソースやCRM」からコンバージョンアクションを事前に作成しておく必要があります。APIで送信するコンバージョン名（`conversion_name`）は、このアクション名と一致させてください。

### partial_failureの処理

`partial_failure = True` を設定することで、1件のエラーがあっても他の件数は処理が継続されます。ログにエラーが記録された場合は、GCLIDの書式誤りや有効期限切れが原因であることが多いため、BigQuery側のデータ品質を定期的に確認することをお勧めします。

## まとめ

今回紹介したパイプラインを整理すると、以下のとおりです。

| ステップ | 役割 |
|---|---|
| GA4 BigQueryエクスポート | GCLIDとセッション情報の蓄積 |
| CRM → BigQuery | 成約データの格納 |
| BigQuery SQL | GCLIDと成約データの結合・整形 |
| Python スクリプト | Google広告APIへのアップロード |
| Cloud Functions + Cloud Scheduler | 毎日自動実行 |

このパイプラインを構築することで、毎日の手動作業をなくし、Google広告の機械学習に実際の成約データを継続的に反映させることができます。特にtCPAやtROASで入札を自動化している場合、データの質が最適化精度に直結するため、オフラインコンバージョンの整備は広告運用改善の土台となります。

次のアクションとして、まずはGA4のBigQueryエクスポートが有効になっているかを確認し、GCLIDがフォームやCRMに保存されているかをチェックするところから始めてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
