# ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る

## はじめに

「昨日の売上はどうだった？」という問いに、翌朝のSlack通知や手作業でのCSV集計で答えていませんか？ECサイトを運営していると、受注が入るたびにリアルタイムで数字を把握したい場面は少なくありません。特にキャンペーン施策の効果検証や在庫管理の判断では、数時間のタイムラグが意思決定の質に直結します。

ShopifyにはWebhookという仕組みがあり、注文・キャンセル・顧客登録などのイベントが発生した瞬間に外部サービスへ通知を送ることができます。この通知をGoogle Cloud Functionsで受け取り、BigQueryに書き込むだけで、リアルタイムに近い売上データ基盤が構築できます。

本記事では、ShopifyのWebhookをトリガーとして、Cloud Functions（Python）でデータを受け取り、BigQueryへ格納するまでの一連の流れを解説します。エンジニアでない方でも概要をつかめるよう、コードの意味を丁寧に説明しながら進めます。

## Shopify Webhookとは何か

WebhookはShopify側からの「プッシュ通知」です。通常のAPIでは、こちらから定期的に「新しい注文はありますか？」と問い合わせる（ポーリング）必要がありますが、Webhookでは「注文が入ったら自動で通知する」という仕組みになっています。

Shopifyの管理画面（設定 → 通知 → Webhook）から、通知を送るイベントと送信先URL（エンドポイント）を設定します。たとえば `orders/create`（注文作成）イベントを選ぶと、注文が入るたびにJSON形式のデータが指定したURLへ送られます。

送られてくるデータには、注文ID・商品名・金額・顧客情報・配送先・割引コードなど、受注に関わるほぼすべての情報が含まれています。これをそのまま保存しておけば、後からどんな切り口でも分析できる生データになります。

<!-- ここから有料 -->

## Cloud Functionsで受信エンドポイントを作る

Cloud Functionsは、Google Cloudが提供するサーバーレス実行環境です。「サーバーレス」とはサーバーの管理が不要という意味で、コードをデプロイするだけでHTTPエンドポイントが生成され、リクエストが来たときだけ起動します。

以下のPythonコードは、ShopifyからのWebhookリクエストを受け取り、BigQueryへ書き込む基本的な実装です。

```python
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
```

> `SHOPIFY_WEBHOOK_SECRET` はShopify管理画面のWebhook設定画面で確認できる署名シークレットです。Cloud FunctionsのSecret Manager連携、またはランタイム環境変数として設定してください。コード内にハードコーディングしないよう注意してください。

## BigQueryのテーブルを設計する

BigQueryにデータを書き込む前に、受け取るテーブルのスキーマを定義しておく必要があります。以下のDDLは最小限の構成例です。

```sql
CREATE TABLE IF NOT EXISTS `your-project-id.shopify_raw.orders` (
  order_id       STRING,
  total_price    FLOAT64,
  currency       STRING,
  email          STRING,
  financial_status STRING,
  created_at     STRING,
  ingested_at    TIMESTAMP
)
OPTIONS(
  description = "Shopify Webhookから取得した受注データ"
);
```

テーブルへの挿入は上記PythonコードのStreaming Insert（`insert_rows_json`）で行います。Streaming Insertは数秒以内にクエリで参照できる状態になるため、リアルタイム分析に向いています。

本番運用ではパーティショニング（`ingested_at` を基準にした日付パーティション）やクラスタリング（`financial_status` など）を設定すると、クエリコストを大幅に削減できます。

## Cloud Functionsのデプロイと設定

ローカル環境にGoogle Cloud SDKを導入済みであれば、以下のコマンドでデプロイできます。

```bash
gcloud functions deploy shopify-webhook \
  --runtime python311 \
  --trigger-http \
  --allow-unauthenticated \
  --region asia-northeast1 \
  --set-env-vars BQ_PROJECT_ID=your-project-id,BQ_DATASET=shopify_raw,BQ_TABLE=orders \
  --set-secrets SHOPIFY_WEBHOOK_SECRET=shopify-webhook-secret:latest \
  --source .
```

デプロイが完了すると、`https://asia-northeast1-your-project-id.cloudfunctions.net/shopify-webhook` のようなURLが発行されます。このURLをShopifyのWebhook設定画面の「URL」欄に貼り付け、対象イベントとして `orders/create` を選択して保存します。

> `--allow-unauthenticated` を指定するとインターネットから誰でもアクセスできる状態になります。ShopifyのHMAC署名検証をコード内で実装していれば不正データの書き込みは防げますが、Cloud Armorなどでさらに保護する方法も検討してください。

## BigQueryで売上を集計・分析する

データが蓄積されてきたら、BigQueryのSQLで様々な切り口から分析できます。以下は日別の売上サマリーを出す例です。

```sql
SELECT
  DATE(TIMESTAMP(created_at)) AS order_date,
  COUNT(DISTINCT order_id)   AS order_count,
  ROUND(SUM(total_price), 0) AS total_revenue,
  currency
FROM
  `your-project-id.shopify_raw.orders`
WHERE
  financial_status = 'paid'
  AND DATE(TIMESTAMP(created_at)) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  order_date, currency
ORDER BY
  order_date DESC;
```

GA4のBigQueryエクスポートと組み合わせる場合、Shopifyの注文データとGA4のセッションデータをセッションIDや流入元で結合することで、「どの広告経由で購入されたか」といったアトリビューション分析も可能になります。GA4の流入元を参照する際は、以下のように `collected_traffic_source` カラムと `UNNEST(event_params)` を活用します。

```sql
SELECT
  ep.value.string_value AS ga_session_id,
  t.manual_medium       AS medium,
  t.manual_source       AS source,
  COUNT(*)              AS sessions
FROM
  `your-project-id.analytics_XXXXXXX.events_*`,
  UNNEST(event_params) AS ep
JOIN UNNEST([collected_traffic_source]) AS t
WHERE
  ep.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
GROUP BY
  ga_session_id, medium, source;
```

このセッションIDを使ってShopifyの注文データとJOINすれば、「どのチャネルが売上に貢献しているか」を数値で把握できます。

## まとめ

本記事では、ShopifyのWebhookをトリガーとして、Cloud Functions（Python）でデータを受け取り、BigQueryへリアルタイムに格納する構成を解説しました。

要点を整理します。

- **Webhook** はShopifyから自動でデータをプッシュしてくれる仕組みです。定期的なAPI呼び出しが不要になります。
- **Cloud Functions** はサーバー管理不要のHTTPエンドポイントで、Webhookの受け口として最適です。HMAC検証で不正リクエストを弾くことが重要です。
- **BigQuery** に蓄積されたデータは、SQLで自由に集計・分析できます。GA4データとの結合で流入チャネル別の売上把握も可能です。

次のアクションとして、まずはShopify開発ストアとGoogle Cloudの無料枠を活用して小規模なプロトタイプを作ってみることをお勧めします。データが蓄積されてきたら、Looker Studioでダッシュボードを構築すると、経営判断に活かせるリアルタイム可視化環境が整います。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
