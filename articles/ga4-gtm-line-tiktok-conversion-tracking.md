---
title: "GA4×GTMでLINE広告・TikTok広告のコンバージョン計測を設定する"
emoji: "📱"
type: "tech"
topics: ["gtm", "googleanalytics", "advertising"]
published: false
---

## 広告効果がわからないまま予算を使い続けていませんか

LINE広告やTikTok広告を出稿しているものの、「どの広告がコンバージョンにつながったか」を正しく計測できていないケースは少なくありません。

各広告プラットフォームにはそれぞれ専用のタグ（LINE Tag、TikTok Pixel）があり、これらをサイトに設置する必要があります。
しかし、タグの直貼りはサイト管理の負担になり、GA4との連携も手動になりがちです。

GTMを使えば、LINE Tag・TikTok Pixelの設置をコード変更なしで行え、GA4のコンバージョンイベントと連動させた一元管理が可能です。

この記事では、GTMを使ったLINE広告・TikTok広告のコンバージョン計測設定を順番に解説します。

## LINE Tagの設置（GTMカスタムHTML）

LINE広告のコンバージョン計測には「LINE Tag」を使います。
LINE Tagは3種類ありますが、GTMではカスタムHTMLタグとして設置します。

### LINE Tagの種類

| タグ名 | 役割 | 設置場所 |
|--------|------|----------|
| ベースコード | 全ページ共通のトラッキングコード | 全ページ |
| コンバージョンコード | CV発生時に実行 | サンクスページ等 |
| カスタムイベントコード | 特定のアクションを計測 | 任意のページ |

### 手順1：ベースコードの設置

LINE広告マネージャーの「トラッキング」→「LINE Tag」からベースコードを取得します。

GTMで新しいタグを作成します。

**タグの設定：**

| 項目 | 値 |
|------|-----|
| タグタイプ | カスタムHTML |
| タグ名 | LINE Tag - Base Code |
| トリガー | All Pages |

```html
<script>
(function(g,d,o){
  g._ltq=g._ltq||[];g._lt=g._lt||function(){g._ltq.push(arguments)};
  var h=d.getElementsByTagName("script")[0];
  var s=d.createElement("script");s.async=1;
  s.src=o+'?id='+g._lt_sid;h.parentNode.insertBefore(s,h);
})(window,document,"https://sp.line-scdn.net/tag/sdk/v1/js/line-tag.js");
_lt('init',{
  customerType:'account',
  tagId:'YOUR_TAG_ID'
});
_lt('send','pv',['YOUR_TAG_ID']);
</script>
```

`YOUR_TAG_ID`はLINE広告マネージャーで確認できるタグIDに置き換えてください。

### 手順2：コンバージョンコードの設置

購入完了や申し込み完了ページで発火するタグを作成します。

**タグの設定：**

| 項目 | 値 |
|------|-----|
| タグタイプ | カスタムHTML |
| タグ名 | LINE Tag - Conversion |
| トリガー | 購入完了ページ |

```html
<script>
_lt('send','cv',{
  type: 'Conversion'
},['YOUR_TAG_ID']);
</script>
```

**トリガーの設定：**

```
トリガータイプ: ページビュー
発生場所: 一部のページビュー
条件: Page Path — 含む — /thanks または /complete
```

:::message
LINE Tagのベースコードが先に読み込まれている前提です。
GTMの「タグの順序付け」機能で、コンバージョンタグがベースコードの後に発火するよう設定してください。
:::

### タグの順序付け設定

1. コンバージョンタグの「詳細設定」→「タグの順序付け」
2. 「〇〇が発行される前にタグを配信」にチェック
3. セットアップタグとして「LINE Tag - Base Code」を選択

## TikTok Pixelの設置（GTMカスタムHTML）

TikTok広告のコンバージョン計測には「TikTok Pixel」を使います。

### 手順1：ベースコードの設置

TikTok広告マネージャーの「アセット」→「イベント」→「ウェブイベント」からPixelコードを取得します。

**タグの設定：**

| 項目 | 値 |
|------|-----|
| タグタイプ | カスタムHTML |
| タグ名 | TikTok Pixel - Base Code |
| トリガー | All Pages |

```html
<script>
!function (w, d, t) {
  w.TiktokAnalyticsObject=t;var ttq=w[t]=w[t]||[];
  ttq.methods=["page","track","identify","instances","debug","on","off","once","ready","alias","group","enableCookie","disableCookie"];
  ttq.setAndDefer=function(t,e){t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}};
  for(var i=0;i<ttq.methods.length;i++)ttq.setAndDefer(ttq,ttq.methods[i]);
  ttq.instance=function(t){for(var e=ttq._i[t]||[],n=0;n<ttq.methods.length;n++)ttq.setAndDefer(e,ttq.methods[n]);return e};
  ttq.load=function(e,n){var i="https://analytics.tiktok.com/i18n/pixel/events.js";
  ttq._i=ttq._i||{};ttq._i[e]=[];ttq._i[e]._u=i;ttq._t=ttq._t||{};ttq._t[e+""]=+new Date;
  ttq._o=ttq._o||{};ttq._o[e+""]=n||{};
  var o=document.createElement("script");o.type="text/javascript";o.async=!0;o.src=i+"?sdkid="+e+"&lib="+t;
  var a=document.getElementsByTagName("script")[0];a.parentNode.insertBefore(o,a)};
  ttq.load('YOUR_PIXEL_ID');
  ttq.page();
}(window, document, 'ttq');
</script>
```

`YOUR_PIXEL_ID`はTikTok広告マネージャーのPixel IDに置き換えてください。

### 手順2：コンバージョンイベントの設置

TikTok Pixelは標準イベントとして以下をサポートしています。

| イベント名 | 用途 |
|-----------|------|
| ViewContent | 商品ページ閲覧 |
| AddToCart | カートに追加 |
| InitiateCheckout | 決済開始 |
| CompletePayment | 購入完了 |
| SubmitForm | フォーム送信 |
| Contact | お問い合わせ |

購入完了のコンバージョンタグを作成します。

```html
<script>
ttq.track('CompletePayment', {
  content_type: 'product',
  value: {{DLV - purchase_value}},
  currency: 'JPY'
});
</script>
```

**トリガーの設定：**

GA4の`purchase`イベントと同じタイミングで発火させる場合、データレイヤーのカスタムイベントトリガーを使います。

```
トリガータイプ: カスタムイベント
イベント名: purchase
```

:::message
金額パラメータ（value）をデータレイヤー変数から取得する場合、GTMのデータレイヤー変数を事前に作成してください。
eコマースデータレイヤーの`ecommerce.value`から取得するのが一般的です。
:::

## GA4コンバージョンとの連動設計

LINE Tag・TikTok Pixelを設置したら、GA4のコンバージョンイベントと同じトリガーで発火させることで、計測のタイミングを統一できます。

### 推奨するトリガー設計

```
[ユーザーが購入完了]
  ↓
[dataLayer.push({ event: "purchase", ... })]
  ↓
[GTMトリガー: CE - purchase]
  ↓ 同じトリガーを3つのタグに紐づけ
[GA4 Event - purchase]
[LINE Tag - Conversion]
[TikTok Pixel - CompletePayment]
```

この設計にすると、以下のメリットがあります。

- コンバージョンの定義が統一される
- トリガーの管理が一箇所で済む
- 新しい広告プラットフォームを追加する際もトリガーを使い回せる

### データレイヤーの共通設計

```javascript
window.dataLayer.push({ ecommerce: null });
window.dataLayer.push({
  event: "purchase",
  ecommerce: {
    transaction_id: "T-20260330-001",
    value: 12800,
    currency: "JPY",
    items: [
      {
        item_id: "SKU-001",
        item_name: "商品A",
        price: 6400,
        quantity: 2
      }
    ]
  }
});
```

GA4、LINE Tag、TikTok Pixelのすべてがこのデータレイヤーから値を取得できます。

## 各プラットフォームの管理画面で計測を確認

### LINE広告マネージャー

1. 「トラッキング」→「LINE Tag」→「テストイベント」
2. サイトでコンバージョンを実行
3. テストイベント画面にCVイベントが表示されるか確認

### TikTok広告マネージャー

1. 「アセット」→「イベント」→ 該当Pixelを選択
2. 「テストイベント」タブを開く
3. サイトURLを入力してテストを実行

### GA4

GA4のリアルタイムレポートまたはDebugViewで`purchase`イベントの受信を確認します。

## よくあるトラブルと対処法

### LINE Tagのコンバージョンがカウントされない

**原因1：** ベースコードが先に読み込まれていない
→ GTMの「タグの順序付け」を確認

**原因2：** タグIDが間違っている
→ LINE広告マネージャーで正しいIDを再確認

### TikTok Pixelのイベントが検知されない

**原因1：** `ttq`オブジェクトが未初期化
→ ベースコードが正しく設置されているか確認

**原因2：** イベント名の大文字小文字が違う
→ `CompletePayment`は先頭大文字。`completepayment`では動作しません

### 3つのプラットフォームでCV数が一致しない

これは仕様上の差異です。各プラットフォームのアトリビューションモデルやCookie処理が異なるため、CV数は完全には一致しません。
GA4のデータを基準にしつつ、各広告プラットフォームのデータを参考値として扱うのが現実的な運用方法です。

## まとめ

GTMを使ったLINE広告・TikTok広告のコンバージョン計測のポイントを整理します。

- LINE Tag・TikTok PixelともにGTMのカスタムHTMLタグで設置する
- ベースコードは全ページ、コンバージョンコードはCV発生ページで発火させる
- GA4のpurchaseイベントと同じトリガーを使い、計測タイミングを統一する
- データレイヤーを共通設計にすると、新しい広告プラットフォームの追加が容易になる
- 各プラットフォーム間のCV数差異はアトリビューションモデルの違いとして許容する

広告ROASを正しく把握するには、計測基盤の整備が前提です。
GTMでの一元管理は、その第一歩として有効な手段です。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
