---
title: "GTMのデータレイヤーを使ったGA4カスタムイベント設計のベストプラクティス"
emoji: "📊"
type: "tech"
topics: ["gtm", "googleanalytics", "javascript"]
published: false
---

## GA4の標準イベントだけでは足りない現実

GA4を導入したものの、標準イベントだけではビジネス固有のユーザー行動を計測できない。
そんな課題を抱えているEC運営者やマーケターは多いのではないでしょうか。

「お気に入り登録」「クーポン適用」「チャット開始」など、サイト独自のアクションを正しく計測するには、GTM（Google Tag Manager）のデータレイヤーを活用したカスタムイベント設計が不可欠です。

この記事では、`dataLayer.push()`の基本構造からGA4カスタムイベントとの連携設定まで、実務で使えるベストプラクティスを解説します。

## dataLayer.push()の基本構造

データレイヤーは、Webサイトとタグマネージャーの間でデータを受け渡すためのJavaScriptオブジェクトです。

```javascript
// 基本構造
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: "イベント名",
  パラメータ名: "値"
});
```

ポイントは3つあります。

1. **`event`キーは必須** — GTMのカスタムイベントトリガーがこの値を検知します
2. **パラメータはフラットに記述** — ネストが深いとGTM変数で取得しにくくなります
3. **`window.dataLayer`の初期化** — GTMスニペットより前にpushする場合は初期化が必要です

### 実践例：お気に入り登録イベント

```javascript
window.dataLayer.push({
  event: "add_to_wishlist",
  item_id: "SKU-12345",
  item_name: "オーガニックコットンTシャツ",
  item_category: "apparel",
  value: 3980
});
```

GA4の推奨イベント名に合わせて`add_to_wishlist`を使うことで、GA4側での認識がスムーズになります。

## イベント命名規則のルール

GA4カスタムイベントの命名には明確なルールがあります。
守らないとデータが正しく記録されません。

### GA4イベント名の制約

| ルール | 内容 |
|--------|------|
| 文字数 | 最大40文字 |
| 使用可能文字 | 英数字とアンダースコアのみ |
| 先頭文字 | 英字で始める（数字不可） |
| 予約語 | `firebase_`、`google_`、`ga_`で始まる名前は使用不可 |

### 推奨する命名パターン

```
[動詞]_[対象]
```

具体例を示します。

```
click_cta_button     → CTAボタンのクリック
submit_contact_form  → お問い合わせフォーム送信
apply_coupon         → クーポン適用
start_live_chat      → チャット開始
view_size_guide      → サイズガイド表示
```

GA4の推奨イベント（`add_to_cart`、`begin_checkout`など）と重複しない名前を選びましょう。

## GTMでのカスタムイベントトリガー設定

データレイヤーにpushされたイベントをGTMで検知する設定手順です。

### 手順1：カスタムイベントトリガーを作成

1. GTMの「トリガー」→「新規」をクリック
2. トリガータイプで「カスタムイベント」を選択
3. イベント名に`add_to_wishlist`を入力
4. 「すべてのカスタムイベント」を選択して保存

### 手順2：データレイヤー変数を作成

パラメータを取得するために、データレイヤー変数を定義します。

1. GTMの「変数」→「ユーザー定義変数」→「新規」
2. 変数タイプ「データレイヤーの変数」を選択
3. データレイヤーの変数名に`item_id`を入力
4. 同様に`item_name`、`item_category`、`value`も作成

### 手順3：GA4イベントタグを作成

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "設定タグ": "GA4設定タグを選択",
  "イベント名": "add_to_wishlist",
  "イベントパラメータ": {
    "item_id": "{{DLV - item_id}}",
    "item_name": "{{DLV - item_name}}",
    "item_category": "{{DLV - item_category}}",
    "value": "{{DLV - value}}"
  },
  "トリガー": "CE - add_to_wishlist"
}
```

タグ名の接頭辞に`GA4 Event -`、トリガーに`CE -`、変数に`DLV -`を付けると管理しやすくなります。

## eコマースイベントのデータレイヤー設計

EC向けのeコマースイベントでは、`items`配列を含む構造が推奨されています。

```javascript
window.dataLayer.push({ ecommerce: null }); // 前回のecommerceデータをクリア
window.dataLayer.push({
  event: "view_item",
  ecommerce: {
    currency: "JPY",
    value: 3980,
    items: [
      {
        item_id: "SKU-12345",
        item_name: "オーガニックコットンTシャツ",
        item_category: "apparel",
        item_category2: "tops",
        price: 3980,
        quantity: 1
      }
    ]
  }
});
```

:::message
eコマースイベントでは、`push`前に`{ ecommerce: null }`でクリアすることが重要です。
前回のデータが残っていると、意図しないパラメータが混入する原因になります。
:::

## デバッグの手順

設定後のデバッグは以下の3ステップで行います。

### 1. GTMプレビューモードで確認

GTMの「プレビュー」ボタンからTag Assistantを起動します。
イベントが発火したタイミングでトリガーの発火状況とパラメータの値を確認できます。

### 2. GA4のDebugViewで確認

GA4管理画面の「管理」→「DebugView」を開きます。
リアルタイムでイベントとパラメータが正しく送信されているか確認できます。

DebugViewを有効にするには、GTMタグの設定フィールドで`debug_mode`を`true`にしてください。

```javascript
// もしくはURLパラメータで有効化
// ?gtm_debug=x を付けてアクセス
```

### 3. ブラウザのコンソールでdataLayerを確認

```javascript
// ブラウザのコンソールで実行
console.log(window.dataLayer);
```

pushされたオブジェクトの中身を直接確認できます。
パラメータ名のタイポや値の型ミスを発見しやすい方法です。

## 設計時に避けるべきアンチパターン

### パラメータ名に日本語を使う

```javascript
// NG
window.dataLayer.push({
  event: "add_to_wishlist",
  商品名: "Tシャツ"
});

// OK
window.dataLayer.push({
  event: "add_to_wishlist",
  item_name: "Tシャツ"
});
```

### イベント数を増やしすぎる

GA4にはカスタムイベント数の上限（500種類）があります。
類似イベントはパラメータで区別する設計が望ましいです。

```javascript
// NG：イベントを分けすぎ
// click_header_cta, click_footer_cta, click_sidebar_cta

// OK：パラメータで区別
window.dataLayer.push({
  event: "click_cta",
  cta_location: "header" // header / footer / sidebar
});
```

### GA4カスタムディメンションの登録を忘れる

`dataLayer.push()`→GTM変数→GA4イベントタグまで設定しても、GA4管理画面でカスタムディメンションを登録しないとレポートに表示されません。

GA4の「管理」→「カスタム定義」→「カスタムディメンションを作成」から登録してください。

## まとめ

データレイヤーを活用したGA4カスタムイベント設計のポイントを整理します。

- `dataLayer.push()`のeventキーでGTMトリガーと連携する
- イベント名は英小文字とアンダースコアで統一する
- パラメータはフラットに記述し、GTMのデータレイヤー変数で取得する
- eコマースイベントではpush前にecommerceオブジェクトをクリアする
- GA4のカスタムディメンション登録を忘れずに行う

正しく設計すれば、GA4のレポートやBigQueryエクスポートで自由に分析できるデータ基盤が完成します。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
