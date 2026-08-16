Shopifyの管理画面とGA4の注文数、なぜ合わないのでしょうか。

原因は一つではありません。複数の設定ポイントに問題が潜んでいます。

・GTMとShopify Pixelの二重実装で1注文が2回カウントされるケース
・サンキューページへのスクリプト制限でpurchaseイベントが飛ばないケース
・PayPay・Amazon Payなど外部決済でセッションが途切れるケース
・iOS/Safariや広告ブロッカーによる計測漏れ

まず切り分けるべきは「二重計測か、計測漏れか」。GA4の数値がShopifyより多ければ二重計測、少なければ計測漏れを疑います。

BigQueryのtransaction_idを使えば、同一注文IDが複数回送信されていないか定量的に確認できます。

GTMのプレビューモード、BigQueryのSQLクエリ、GA4の除外リファラー設定——それぞれの確認手順を段階的に解説しました。

https://zenn.dev/web_benriya/articles/shopify-ga4-ecommerce-data-mismatch-fix

#Shopify #GA4
