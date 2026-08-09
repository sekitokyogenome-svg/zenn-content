---
title: "Shopify×GTM×GA4でカスタムピクセルを使った高精度エコマース計測を実装する"
emoji: "🏷️"
type: "tech"
topics: ["shopify","gtm","googleanalytics","ec","javascript"]
published: false
---

## はじめに

「Shopifyに標準のGA4連携を設定したのに、購入データがうまく取れていない」「GTMを使いたいが、Shopifyのチェックアウトページには外部スクリプトを直接埋め込めないと聞いた」——そのような悩みを抱えているEC運営者やWebコンサルタントの方は少なくないのではないでしょうか。

Shopifyは2023年以降、セキュリティおよびパフォーマンス上の理由から、チェックアウトページへの外部スクリプトの直接挿入を段階的に制限しています。この変更により、従来の方法でGTMタグをチェックアウト完了ページに仕込む手法が機能しなくなるケースが増えてきました。

そこで注目されているのが **Shopifyカスタムピクセル（Customer Events / Custom Pixels）** です。Shopifyが公式に提供するこの仕組みを使うと、サンドボックス環境でブラウザイベントを安全にキャプチャし、GTM経由でGA4へ購入データを送信できます。本記事では、カスタムピクセルの概要から実装手順、GA4でのデータ確認方法まで、ステップを追って説明します。

---

## Shopifyカスタムピクセルとは

カスタムピクセルは、Shopify管理画面の「設定 → カスタムピクセル」から追加できる、Shopify公式のイベント計測の仕組みです。`checkout_completed`や`page_viewed`、`product_viewed`など、あらかじめShopifyが定義した**標準イベント**と、運営者が独自に定義する**カスタムイベント**の両方を利用できます。

重要な点は、カスタムピクセルのコードは**サンドボックス化されたiframe内**で動作するという点です。直接DOMを操作することはできませんが、`analytics.subscribe()`というAPIを使ってShopifyのイベントストリームを購読し、イベントデータを取得できます。取得したデータは`window.parent.postMessage()`やdataLayerへのプッシュなど、適切な手段で外部のGTMコンテナに受け渡すことが可能です。

```javascript
// カスタムピクセルのコード例（Shopify管理画面に貼り付ける）
analytics.subscribe('checkout_completed', (event) => {
  const order = event.data.checkout;
  // GTMのdataLayerへデータを送信
  window.parent.postMessage({
    type: 'gtm_event',
    payload: {
      event: 'purchase',
      ecommerce: {
        transaction_id: order.order.id,
        value: parseFloat(order.totalPrice.amount),
        currency: order.totalPrice.currencyCode,
        items: order.lineItems.map((item, index) => ({
          item_id: item.variant.sku || item.variant.id,
          item_name: item.title,
          price: parseFloat(item.variant.price.amount),
          quantity: item.quantity,
          index: index,
        })),
      },
    },
  }, '*');
});
```

:::message
カスタムピクセルのサンドボックスからは`window.dataLayer`に直接アクセスできません。`postMessage`を使って親フレーム（ストアのページ）にデータを渡し、そちら側でdataLayerに追加する構成を取ります。
:::

---

## GTM側の受信タグとトリガーの設定

Shopifyのカスタムピクセルから送られた`postMessage`を受け取るには、GTM側でカスタムHTMLタグを使って`message`イベントをリッスンする必要があります。

まず、GTMのワークスペースで以下のカスタムHTMLタグを作成します。トリガーは「All Pages（全ページ）」に設定してください。このタグは、カスタムピクセルからのメッセージを受け取り、dataLayerに変換します。

```html
<!-- GTM カスタムHTMLタグ: Shopifyピクセルイベントレシーバー -->
<script>
  window.addEventListener('message', function(event) {
    // 信頼できるオリジンのみ受け付ける（本番環境では自社ドメインを指定）
    if (!event.data || event.data.type !== 'gtm_event') return;

    var payload = event.data.payload;
    if (!payload || !payload.event) return;

    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({ ecommerce: null }); // 前回のecommerceデータをクリア
    window.dataLayer.push(payload);
  }, false);
</script>
```

次に、GTMでカスタムイベントトリガーを作成します。

- **トリガーの種類**: カスタムイベント
- **イベント名**: `purchase`（dataLayerにプッシュしたevent名と一致させる）

このトリガーに対してGA4イベントタグを紐付けます。GA4タグの設定では「イベント名」を`purchase`とし、ecommerceデータの送信を有効化するオプションをONにします。dataLayer変数として`ecommerce`オブジェクトを渡すことで、GA4の拡張eコマースとして計測されます。

:::message
GTMでecommerceデータを送信する際は、タグの「その他の設定 → eコマースデータを送信する」を有効にし、データソースを「Data Layer」に設定してください。これにより`items`配列も自動的に送信されます。
:::

---

## GA4でのデータ確認とBigQueryでの分析クエリ

GTMとカスタムピクセルの設定が完了したら、GA4のリアルタイムレポートやデバッグビューでデータが届いているか確認します。GA4の「設定 → DebugView」で`purchase`イベントおよびecommerceパラメータが正しく送信されているかをチェックしてください。

さらに詳細な分析を行う場合は、GA4とBigQueryを連携してSQL分析が利用できます。以下は、流入元チャネル別の購入金額を集計するクエリの例です。

```sql
-- BigQuery: 流入元チャネル別の購入金額集計（GA4エクスポートテーブル）
SELECT
  s.manual_medium AS medium,
  s.manual_source AS source,
  COUNT(DISTINCT ep_session.value.int_value) AS sessions,
  COUNT(DISTINCT CASE WHEN e.event_name = 'purchase' THEN e.user_pseudo_id END) AS purchasers,
  SUM(
    CASE WHEN e.event_name = 'purchase'
    THEN (
      SELECT ep.value.double_value
      FROM UNNEST(e.event_params) AS ep
      WHERE ep.key = 'value'
    )
    END
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXX.events_*` AS e,
  UNNEST(e.event_params) AS ep_session,
  UNNEST([e.collected_traffic_source]) AS s
WHERE
  ep_session.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC;
```

:::message
`ga_session_id`はevent_paramsのネストされたフィールドに格納されているため、`UNNEST(event_params)`で展開してから参照してください。また、流入元情報は`collected_traffic_source.manual_medium`および`collected_traffic_source.manual_source`を使用します（`traffic_source`フィールドはセッション初回のみ記録される点にご注意ください）。
:::

---

## よくあるトラブルと対処法

カスタムピクセルの実装でよく見られる問題と、その対処法を紹介します。

**1. `checkout_completed`イベントが発火しない**

ShopifyのPlus以外のプランでは、チェックアウトカスタマイズに制限があります。カスタムピクセル自体はBasic以上のプランでも利用可能ですが、管理画面の「設定 → カスタムピクセル」が表示されているか先に確認してください。また、カスタムピクセルの「接続ステータス」が「接続済み」になっているかも確認が必要です。

**2. GA4にecommerceデータが届かない**

最も多い原因は、GTMタグの「eコマースデータを送信する」オプションが無効になっているケースです。もう1つの原因として、dataLayerへのプッシュ前に`{ ecommerce: null }`でリセットしていないことが挙げられます。前の購入データが混入してしまうため、リセット処理は欠かさず実施してください。

**3. postMessageが受け取れない**

GTMのカスタムHTMLタグが実際にページ上で実行されているか確認します。GTMプレビューモードを使い、「message」リスナーが正常にセットアップされているか確認してください。また、Shopifyのコンテンツセキュリティポリシー（CSP）の影響でpostMessageがブロックされている場合は、カスタムピクセルの設定側でShopify公式の`init`イベント経由でデータを送る方法に切り替えることも検討してください。

---

## まとめ

本記事では、ShopifyのカスタムピクセルをGTMと連携させてGA4に高精度なeコマースデータを送信する方法を解説しました。

- Shopifyのチェックアウトページへの直接スクリプト埋め込みには制限があるため、カスタムピクセルを活用する
- カスタムピクセルはサンドボックス環境で動作し、`postMessage`でGTMのdataLayerにデータを渡す
- GTM側ではカスタムHTMLタグで`message`イベントをリッスンし、GA4イベントタグと連携する
- BigQueryでの分析では`ga_session_id`を`UNNEST(event_params)`経由で取得し、流入元は`collected_traffic_source`を参照する

初期設定にはやや複雑な手順が伴いますが、一度構築してしまえばShopifyのアップデートに左右されにくい安定した計測基盤になります。まずはGTMのプレビューモードとGA4のDebugViewを併用しながら、1つずつ動作を確認していくことをお勧めします。

次のステップとしては、`product_viewed`や`cart_updated`など他のShopifyイベントも購読し、ファネル全体の可視化に取り組んでみてください。Looker Studioと組み合わせることで、チャネル別・商品別のコンバージョン分析ダッシュボードの構築も可能です。

## 関連記事

- [GA4×GTMでサイト内検索キーワードを正しく計測する設定](https://zenn.dev/web_benriya/articles/ga4-gtm-site-search-tracking)
- [GTMのデータレイヤーを使ったGA4カスタムイベント設計のベストプラクティス](https://zenn.dev/web_benriya/articles/gtm-data-layer-ga4-custom-event-design)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
