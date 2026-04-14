---
title: "GTMでGA4のeコマース計測を完全設定する手順【Shopify対応】"
emoji: "🏷️"
type: "tech"
topics: ["gtm", "googleanalytics", "shopify"]
published: true
---

## はじめに

「ShopifyでGA4のeコマース計測を設定したいけど、dataLayerの構造がよくわからない」。「GTMでタグを作ったのに、GA4のレポートに売上データが反映されない」。こんな悩みを抱えているEC担当者やマーケターは多いのではないでしょうか。

GA4のeコマース計測は、従来のユニバーサルアナリティクスとはデータ構造が大きく異なります。さらにShopifyは独自のチェックアウトフローを持つため、一般的なGTM設定ガイドがそのまま使えないケースも少なくありません。

本記事では、GTMを使ってGA4のeコマースイベントをShopifyサイトに設定する手順を、dataLayerの構造からGTMのタグ・トリガー・変数の設定まで一通り解説します。

## GA4 eコマースイベントの全体像

GA4のeコマース計測では、購買ファネルに沿った以下の4つのイベントが重要です。

| イベント名 | 発火タイミング | 計測できること |
|---|---|---|
| `view_item` | 商品詳細ページの表示 | 商品閲覧数・人気商品の把握 |
| `add_to_cart` | カートに追加 | カート追加率・カゴ落ち分析 |
| `begin_checkout` | チェックアウト開始 | チェックアウト離脱率 |
| `purchase` | 購入完了 | 売上・コンバージョン |

これらのイベントにはすべて**items配列**（商品データ）を含める必要があります。items配列が欠落していると、GA4のeコマースレポートにデータが表示されません。

## dataLayerの構造（イベント別）

各イベントでdataLayerにpushするデータ構造を確認しましょう。

### view_item

```javascript
dataLayer.push({
  event: "view_item",
  ecommerce: {
    currency: "JPY",
    value: 3980,
    items: [
      {
        item_id: "SKU-001",
        item_name: "オーガニックハンドクリーム",
        item_category: "スキンケア",
        price: 3980,
        quantity: 1
      }
    ]
  }
});
```

### add_to_cart

```javascript
dataLayer.push({
  event: "add_to_cart",
  ecommerce: {
    currency: "JPY",
    value: 3980,
    items: [
      {
        item_id: "SKU-001",
        item_name: "オーガニックハンドクリーム",
        item_category: "スキンケア",
        price: 3980,
        quantity: 1
      }
    ]
  }
});
```

### begin_checkout

```javascript
dataLayer.push({
  event: "begin_checkout",
  ecommerce: {
    currency: "JPY",
    value: 7960,
    items: [
      {
        item_id: "SKU-001",
        item_name: "オーガニックハンドクリーム",
        price: 3980,
        quantity: 2
      }
    ]
  }
});
```

### purchase

```javascript
dataLayer.push({
  event: "purchase",
  ecommerce: {
    transaction_id: "T-20260329-001",
    currency: "JPY",
    value: 7960,
    tax: 723,
    shipping: 500,
    items: [
      {
        item_id: "SKU-001",
        item_name: "オーガニックハンドクリーム",
        price: 3980,
        quantity: 2
      }
    ]
  }
});
```

:::message
purchaseイベントには`transaction_id`が必須です。これがないとGA4側で重複カウントされる原因になります。
:::

## ShopifyでのdataLayer実装

Shopifyでは、テーマのLiquidテンプレートを編集してdataLayerへのpushを実装します。

### 方法1: Shopifyのカスタムピクセル（推奨）

Shopify の **Customer Events（カスタムピクセル）** を使う方法が現在の推奨です。Shopify管理画面の「設定 > カスタムピクセル」から設定できます。

```javascript
// カスタムピクセルでのpurchaseイベント例
analytics.subscribe("checkout_completed", (event) => {
  const checkout = event.data.checkout;
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({ ecommerce: null }); // 前のecommerceデータをクリア
  window.dataLayer.push({
    event: "purchase",
    ecommerce: {
      transaction_id: checkout.order.id,
      value: checkout.totalPrice.amount,
      currency: checkout.totalPrice.currencyCode,
      tax: checkout.totalTax.amount,
      shipping: checkout.shippingLine?.price.amount || 0,
      items: checkout.lineItems.map((item, index) => ({
        item_id: item.variant.sku || item.variant.id,
        item_name: item.title,
        price: item.variant.price.amount,
        quantity: item.quantity,
        index: index
      }))
    }
  });
});
```

### 方法2: theme.liquidでの実装

商品ページの`view_item`や`add_to_cart`は、テーマファイルで実装するケースもあります。

```javascript
// product.liquidまたはmain-product.liquidに追加
<script>
  window.dataLayer = window.dataLayer || [];
  dataLayer.push({ ecommerce: null });
  dataLayer.push({
    event: "view_item",
    ecommerce: {
      currency: "{{ shop.currency }}",
      value: {{ product.price | money_without_currency | remove: ',' }},
      items: [{
        item_id: "{{ product.selected_or_first_available_variant.sku }}",
        item_name: "{{ product.title | escape }}",
        item_category: "{{ product.type | escape }}",
        price: {{ product.price | money_without_currency | remove: ',' }},
        quantity: 1
      }]
    }
  });
</script>
```

:::message alert
dataLayerにpushする前に `dataLayer.push({ ecommerce: null })` で前のecommerceオブジェクトをクリアしてください。これを省略すると、前のイベントのitems配列が残り、データが混在する原因になります。
:::

## GTM設定: GA4イベントタグの作成

GTMで各eコマースイベント用のタグを作成します。

### 手順

1. GTMで「タグ > 新規」を選択
2. タグタイプ: **Googleアナリティクス: GA4イベント**
3. 測定ID: GA4の測定ID（G-XXXXXXXXX）を入力
4. イベント名: `view_item`（各イベントに対応する名前）
5. 「eコマースデータを送信」にチェックを入れる
6. データソース: **Data Layer** を選択

この「eコマースデータを送信」の設定が重要です。これを有効にすると、dataLayerのecommerceオブジェクトが自動的にGA4に送信されます。

:::message
「eコマースデータを送信」を有効にすれば、items配列やcurrency、valueなどを個別にイベントパラメータとして設定する必要はありません。dataLayerのecommerceオブジェクトがそのまま送信されます。
:::

同様の手順で`add_to_cart`、`begin_checkout`、`purchase`の計4つのタグを作成します。

## GTM設定: dataLayer変数の作成

eコマースデータの送信にはdataLayer変数を個別に作成する必要はありませんが、トリガー条件やカスタムレポートで使いたい場合は、以下のような変数を作成しておくと便利です。

| 変数名 | 変数タイプ | データレイヤーの変数名 |
|---|---|---|
| dlv - ecommerce.currency | データレイヤーの変数 | `ecommerce.currency` |
| dlv - ecommerce.value | データレイヤーの変数 | `ecommerce.value` |
| dlv - ecommerce.transaction_id | データレイヤーの変数 | `ecommerce.transaction_id` |

作成手順:

1. GTMで「変数 > ユーザー定義変数 > 新規」
2. 変数タイプ: **データレイヤーの変数**
3. データレイヤーの変数名に上記の値を入力
4. データレイヤーのバージョン: **バージョン2**

## GTM設定: トリガーの作成

各eコマースイベント用のトリガーを作成します。

| トリガー名 | トリガータイプ | 条件 |
|---|---|---|
| CE - view_item | カスタムイベント | イベント名 = `view_item` |
| CE - add_to_cart | カスタムイベント | イベント名 = `add_to_cart` |
| CE - begin_checkout | カスタムイベント | イベント名 = `begin_checkout` |
| CE - purchase | カスタムイベント | イベント名 = `purchase` |

作成手順:

1. GTMで「トリガー > 新規」
2. トリガータイプ: **カスタムイベント**
3. イベント名: `view_item`（正規表現は使用しない）
4. 発生場所: **すべてのカスタムイベント**

作成したトリガーを、対応するGA4イベントタグにそれぞれ紐づけます。

## テスト: GTMプレビューモードとGA4 DebugView

設定が完了したら、公開前にテストを行います。

### GTMプレビューモードでの確認

1. GTMで「プレビュー」ボタンをクリック
2. サイトのURLを入力してTag Assistantを起動
3. 商品ページを表示 → `view_item`イベントが発火するか確認
4. カート追加 → `add_to_cart`が発火するか確認
5. 各タグの「Tags Fired」セクションで、ecommerceデータが正しく含まれているか確認

### GA4 DebugViewでの確認

1. GA4の管理画面で「管理 > DebugView」を開く
2. GTMプレビューモードでサイトを操作
3. DebugViewにイベントがリアルタイムで表示される
4. 各イベントをクリックし、`items`パラメータに商品データが含まれているか確認

:::message
DebugViewにイベントが表示されるまで数秒〜数十秒のタイムラグがあります。表示されない場合は少し待ってからページをリロードしてみてください。
:::

## よくあるトラブルと対処法

### 1. purchaseイベントが二重カウントされる

**原因**: 注文完了ページのリロードや、ブラウザの「戻る」操作で再度dataLayer.pushが実行されている。

**対処法**: `transaction_id`を含める。GA4は同一の`transaction_id`を自動的に重複排除します。加えて、Cookieやセッションストレージで送信済みフラグを管理する実装も有効です。

```javascript
if (!sessionStorage.getItem('purchase_tracked_' + orderId)) {
  dataLayer.push({ event: "purchase", ecommerce: { /* ... */ } });
  sessionStorage.setItem('purchase_tracked_' + orderId, 'true');
}
```

### 2. GA4レポートにitems（商品）データが表示されない

**原因**: dataLayerのecommerceオブジェクトの構造が正しくない、またはGA4タグで「eコマースデータを送信」が無効になっている。

**対処法**: GTMプレビューモードのData Layerタブで、ecommerceオブジェクトの構造がGA4の仕様通りになっているか確認してください。特に`items`が配列であること、各アイテムに`item_id`または`item_name`が含まれていることが必須です。

### 3. Shopifyのチェックアウトページでイベントが取れない

**原因**: Shopifyのチェックアウトページは外部スクリプトの実行が制限されています。通常のGTMコンテナスニペットはチェックアウトページで動作しません。

**対処法**: Shopifyのカスタムピクセル（Customer Events）を使用してください。カスタムピクセルはチェックアウトページでも動作するため、`begin_checkout`や`purchase`イベントを取得できます。

### 4. currencyが設定されておらず売上が0になる

**原因**: ecommerceオブジェクトに`currency`フィールドが含まれていない。

**対処法**: すべてのeコマースイベントに`currency`（例: `"JPY"`）を含めてください。currencyがないとGA4が金額データを正しく処理できません。

## まとめ

GTMでGA4のeコマース計測をShopifyサイトに設定する手順を解説しました。ポイントを整理します。

- dataLayerのecommerceオブジェクトは**GA4の仕様に準拠した構造**で実装する
- pushの前に `{ ecommerce: null }` で**前のデータをクリア**する
- GA4タグで「**eコマースデータを送信**」を有効にする
- Shopifyのチェックアウトページは**カスタムピクセル**で対応する
- `transaction_id`を含めて**重複カウントを防止**する
- 公開前にGTMプレビューモードとGA4 DebugViewで**テスト**する

eコマース計測は設定項目が多いため、一つの設定ミスがデータ全体の信頼性に影響します。正確な計測基盤があってこそ、売上改善やマーケティング施策の効果検証が可能になります。

---

GA4のeコマース計測設定やデータ分析基盤の構築でお困りの方は、以下のサービスで対応しています。

https://coconala.com/services/3332133
