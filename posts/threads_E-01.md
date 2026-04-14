ShopifyにGA4のeコマース計測を入れたのに、売上データがGA4に反映されない。そんな状況に陥っていませんか。

GTMでGA4 eコマース計測をShopifyに設定する際には、いくつかの落とし穴があります。今回公開した記事では、その全手順をまとめました。

・GA4 eコマースの4大イベント（view_item / add_to_cart / begin_checkout / purchase）の役割
・dataLayerに正しくpushするためのJavaScriptコード例
・pushの前に必須の「ecommerce: null」クリア処理
・Shopifyのチェックアウトページはカスタムピクセルでないと取れない理由
・GTMのタグ・トリガー・変数の具体的な設定手順
・GTMプレビューモードとGA4 DebugViewを使った動作確認の方法
・purchaseの二重カウント防止策（transaction_id活用）

正確な計測基盤があってはじめて、売上改善策の効果検証が可能になります。設定でお困りの方はぜひ記事をご覧ください。

https://zenn.dev/web_benriya/articles/gtm-ga4-ecommerce-tracking-shopify

#GTM #GA4eコマース
