---
title: "Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する"
emoji: "🔧"
type: "tech"
topics: ["googleanalytics","bigquery","ec","shopify","gtm"]
published: true
---

## はじめに

「Shopifyの管理画面の売上とGA4のコンバージョン数が全然違う…」「GA4でecommerce_purchaseのイベントは飛んでいるのに、注文数が実際より少ない」――このような状況に直面したことはないでしょうか。

ShopifyとGA4を組み合わせてECサイトを運用する際、売上データや注文数のズレは非常によく起こる問題です。原因が一つではなく、計測の仕組みや設定の複数箇所に問題が潜んでいることが多いため、「どこから調べればいいかわからない」と困惑されている方も少なくありません。

本記事では、ShopifyとGA4のデータ不一致が発生する主な原因を整理したうえで、GTMの設定見直しからBigQueryを使ったデータ検証まで、段階的な確認・修正方法をご説明します。EC運営のご担当者やWebコンサルタントの方に向けて、できる限り実践的な内容を心がけています。

---

## データが合わない主な原因を整理する

Shopify × GA4でデータが一致しないケースは、大きく以下の4つに分類されます。

**1. Shopifyの「Additional Scripts」廃止による計測漏れ**

以前はShopifyの「チェックアウト設定 → Additional Scripts」にGA4の計測コードを直接埋め込む方法が主流でした。しかし2023年以降、Shopify Plusでない場合このエリアが廃止・制限されたことで、サンキューページ（order_status）でのpurchaseイベントが取得できなくなるケースが増えています。

**2. GTM経由のイベントとShopify Pixel（Web Pixels）の二重実装**

ShopifyにはShopify Pixelという独自のイベント計測機能があります。GA4の公式連携としてShopify Pixelを有効にしつつ、GTMでも独自にpurchaseイベントを送信している場合、1回の購入が2回カウントされることがあります。

**3. サードパーティアプリによるリダイレクト**

Shopifyでは決済時にPayPayやAmazon Payなどの外部決済画面へ遷移するケースがあります。外部決済から戻るURLにGA4のパラメーターが引き継がれないと、セッションが途切れてコンバージョンが記録されなくなります。

**4. ブラウザの制限・広告ブロッカー**

iOS・SafariのITPやuBlock等の広告ブロッカーによって、一定割合のGA4タグがブロックされます。Shopify管理画面の売上にはこの影響がありませんが、GA4側のカウントは低く出る傾向があります。

:::message
まず「二重計測」か「計測漏れ」かを切り分けることが先決です。GA4の数値がShopifyより多い場合は二重計測、少ない場合は計測漏れを疑います。
:::

---

## GTMの設定を確認・修正する

Shopify × GTMでエコマース計測を行う場合、以下のポイントを順番に確認してください。

### サンキューページのトリガー設定

最も多いミスは、purchaseイベントを発火させるトリガーが`/thank_you`または`/orders/`のURLに対して正しく設定されていないケースです。

GTMのプレビューモードを使って、実際に注文テストを行い、`purchase`イベントが**1回だけ**発火しているかを確認してください。2回以上発火している場合は、ShopifyPixelとGTMの両方でイベントが送られている可能性があります。

### DataLayerのpushタイミング

Shopifyのテーマでは、LiquidテンプレートからdataLayerにecommerceオブジェクトをpushするタイミングが、GTMのGA4イベントタグより後になっていると、空のecommerceデータが送信されてしまいます。

GTMの「タグの順序付け」機能を使い、dataLayerのpush（カスタムHTMLタグ）が**GA4イベントタグより先に**実行されるよう設定しましょう。

### Shopify Pixelとの共存設定

Shopify管理画面の「カスタマーイベント」からGA4のPixelを有効にしている場合は、GTM側のpurchaseイベントを無効にするか、どちらか一方に統一することをお勧めします。両方を有効にしたまま運用するには、重複排除の仕組みが必要です。

---

## BigQueryでデータのズレを定量的に検証する

GA4のデータをBigQueryにエクスポートしている場合、以下のSQLで実際の計測状況を確認できます。

### 日別のpurchaseイベント件数と売上を確認する

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  event_date
```

このクエリの`purchase_count`がShopifyの注文数と比較して大きく乖離している場合、二重計測または計測漏れのどちらかが発生しています。

### transaction_idの重複を確認する

二重計測が疑われる場合は、同一のtransaction_idが複数回送信されていないかをチェックします。

```sql
SELECT
  ep.value.string_value AS transaction_id,
  COUNT(*) AS send_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
  AND ep.key = 'transaction_id'
GROUP BY
  transaction_id
HAVING
  send_count > 1
ORDER BY
  send_count DESC
```

`send_count`が2以上の行があれば、同一注文が複数回カウントされています。

### 流入元別のpurchase数を確認する

どの流入元でコンバージョンが取れていないかを把握するには、collected_traffic_sourceを使います。

```sql
SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*` AS e
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND e.event_name = 'purchase'
GROUP BY
  medium,
  source
ORDER BY
  purchase_count DESC
```

特定のmedium（例: `cpc`や`email`）でpurchaseが極端に少ない場合、その流入経路でセッション切れが起きている可能性があります。

---

## Shopify側で実施できる追加対策

GA4側の設定だけでなく、Shopify側でも取り組める対策があります。

### チェックアウト拡張機能（Checkout Extensibility）の活用

ShopifyがCheckout Extensibilityに移行して以降、サンキューページへのカスタムスクリプト埋め込み方法が変わりました。Shopify Plusをご利用の場合は「チェックアウト拡張機能」の「Order Status Page」を使ってGA4のpurchaseイベントを送信することを検討してください。

Shopify Plus以外の場合は、**Shopify Web Pixels（カスタムPixel）** を利用することで、チェックアウト完了時のイベントを取得できます。カスタムPixelはJavaScriptでGA4のgtag.jsを呼び出す形で実装します。

### 外部決済のリダイレクト対策

PayPayやAmazon Pay等の外部決済を使用している場合、決済後のサンキューページURLにShopifyが自動付与するクエリパラメーター（`?checkout_token=`等）を確認してください。GA4の「除外するリファラー」設定に外部決済ドメインを追加することで、セッションの途切れを防ぐことができます。

GA4の管理画面 → データストリーム → 詳細設定 → 「除外するリファラー」から設定を行います。

:::message
外部決済ドメインの除外設定は、GA4のプロパティ設定画面から行います。GTMやBigQueryの設定ではないため、見落とされることがある箇所です。
:::

---

## まとめ

ShopifyとGA4のエコマースデータが一致しない主な原因と対策を整理すると、以下のようになります。

| 症状 | 主な原因 | 対策 |
|------|----------|------|
| GA4の数値がShopifyより多い | GTMとShopify Pixelの二重計測 | どちらか一方に統一する |
| GA4の数値がShopifyより少ない | サンキューページの計測漏れ | Checkout ExtensibilityまたはカスタムPixelを使用 |
| 特定流入元のコンバージョンが少ない | 外部決済によるセッション切れ | GA4の除外リファラーを設定 |
| データにばらつきがある | 広告ブロッカー・ITP | サーバーサイド計測の導入を検討 |

まず取り組むべき順序としては、①GTMプレビューで二重計測の有無を確認 → ②BigQueryのtransaction_id重複チェック → ③外部決済ドメインのリファラー除外設定、という流れが効果的です。

根本的な解決を図るには、GTM・GA4・Shopify Pixelの役割分担を明確にし、どのタグがどのイベントを担当するかを整理したドキュメントを残しておくことをお勧めします。設定が複雑になるほど、後から見直したときに「なぜこうなっているかわからない」という状況に陥りやすいためです。

データの正確性はECサイトの意思決定の基盤です。少しずつでも計測の精度を高め、施策判断に活かしていただければ幸いです。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
