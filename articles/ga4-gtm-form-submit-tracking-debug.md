---
title: "GA4×GTMでフォーム送信の計測が取れないときのデバッグ手順"
emoji: "🔍"
type: "tech"
topics: ["gtm", "googleanalytics", "debugging"]
published: false
---

## はじめに

「GTMでフォーム送信トリガーを設定したのに、GA4のレポートにイベントが一件も上がってこない」

こうした状況に遭遇したことはないでしょうか。問い合わせフォームやリード獲得フォームの送信計測は、コンバージョン分析の要です。にもかかわらず、設定したはずのイベントが計測されないと、原因の切り分けに時間を取られてしまいます。

本記事では、GA4×GTMのフォーム送信計測が動かないときに、どこから調べればよいかを体系的に整理します。

## Step 1: GTMプレビューモードでトリガーの発火を確認する

まずはGTMのプレビューモード（Tag Assistant）で、トリガーが発火しているかを確認します。

1. GTMの管理画面で「プレビュー」をクリック
2. 対象のWebサイトでフォームを送信する
3. Tag Assistantの左パネルに `Form Submit` や `Click` イベントが表示されるか確認

:::message
プレビューモードで対象のタグが「Tags Fired」に表示されていない場合、トリガーの条件が合っていません。「Tags Not Fired」セクションでトリガー条件のどれが不一致かを確認しましょう。
:::

## Step 2: トリガー設定のよくある問題を確認する

トリガーが発火しない場合、以下のポイントを見直してください。

### フォーム送信トリガー vs クリックトリガー

GTMには「フォーム送信（Form Submission）」トリガーと「クリック」トリガーがあります。混同しやすいので注意が必要です。

| トリガー種別 | 検知対象 | 適用場面 |
|---|---|---|
| フォーム送信 | HTMLの `<form>` タグの `submit` イベント | 標準的なHTMLフォーム |
| クリック（すべての要素） | 任意の要素のクリック | 送信ボタンのクリック検知 |

### SPAでの注意点

React、Vue、Next.jsなどのSPAフレームワークでは、ページ遷移なしでフォームが処理されます。GTMの標準フォーム送信トリガーは、ブラウザネイティブの `submit` イベントに依存しているため、SPAのフォームでは発火しないケースがあります。

:::message alert
フォーム送信トリガーの「タグの配信を待つ」オプションを有効にしていても、JavaScriptで `event.preventDefault()` されている場合はページ遷移が発生しないため、意図どおりに動かないことがあります。
:::

## Step 3: フォームの送信方式を確認する

フォームが標準的なHTML送信を使っているか、JavaScript/AJAXで送信しているかで対処法が変わります。

ブラウザのDevTools（F12）でNetworkタブを開き、フォーム送信時のリクエストを観察してください。

- **ページ遷移が発生する** → 標準HTML送信（GTMのフォーム送信トリガーで対応可能）
- **ページ遷移なしでリクエストが飛ぶ** → AJAX送信（カスタム対応が必要）

```javascript
// DevToolsのConsoleで確認する方法
// フォーム要素にsubmitイベントリスナーがあるか確認
const form = document.querySelector('form');
console.log(getEventListeners(form));
```

## Step 4: AJAXフォームにはdataLayerプッシュで対応する

AJAXでフォームを送信しているサイトでは、送信完了のタイミングでdataLayerにイベントをプッシュするのが確実です。

### 方法A: サイト側のコードにdataLayerプッシュを追加する

フォーム送信の成功コールバック内で以下を実行します。

```javascript
// フォーム送信成功時にdataLayerへプッシュ
function onFormSubmitSuccess() {
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({
    event: 'form_submit',
    form_id: 'contact_form',
    form_name: 'お問い合わせフォーム'
  });
}
```

GTM側では、カスタムイベントトリガーで `event` 名 `form_submit` を指定すれば発火します。

### 方法B: GTMカスタムHTMLタグでAJAXフォームを検知する

サイト側のコードを変更できない場合は、GTMのカスタムHTMLタグで対応できます。

```html
<script>
(function() {
  // フォーム要素を監視してsubmitイベントを捕捉する
  var targetForm = document.querySelector('#contact-form');
  if (!targetForm) return;

  targetForm.addEventListener('submit', function(e) {
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({
      event: 'ajax_form_submit',
      form_id: targetForm.id || 'unknown',
      form_action: targetForm.action || ''
    });
  });
})();
</script>
```

:::message
カスタムHTMLタグは「All Pages」トリガーで配信し、DOMの読み込み完了後に実行されるようにしてください。タイミングが早すぎるとフォーム要素がまだ存在せず、`querySelector` が `null` を返します。
:::

### 方法C: MutationObserverで動的フォームに対応する

SPAなどでフォーム要素が後からDOMに追加される場合は、MutationObserverで検知できます。

```html
<script>
(function() {
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeType === 1 && node.matches && node.matches('.thank-you-message')) {
          window.dataLayer = window.dataLayer || [];
          window.dataLayer.push({
            event: 'form_submit_complete',
            form_type: 'contact'
          });
          observer.disconnect();
        }
      });
    });
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true
  });
})();
</script>
```

この例では、サンクスメッセージ（`.thank-you-message`）がDOMに追加されたタイミングで送信完了と判定しています。

## Step 5: GA4 DebugViewでイベントの到達を確認する

GTM側でタグが発火しても、GA4にデータが届いていない可能性があります。GA4のDebugViewで確認しましょう。

1. GA4管理画面の **「管理」>「DebugView」** を開く
2. GTMプレビューモードを有効にした状態でフォームを送信する
3. DebugViewのタイムラインにイベントが表示されるか確認する

:::message alert
DebugViewにイベントが表示されない場合、GA4設定タグ（Google Tag）自体が正しく配信されていない可能性があります。測定IDが正しいか、GTMのGA4設定タグがすべてのページで発火しているかを確認してください。
:::

## Step 6: GA4のイベント設定を確認する

イベントがGA4に届いていても、レポートに表示されるまでには注意点があります。

### カスタムイベント vs 推奨イベント

GA4には「推奨イベント」（`generate_lead` など）と「カスタムイベント」があります。フォーム送信の計測には、推奨イベント名 `generate_lead` を使うとGA4のレポートで自動的に認識されます。

```javascript
// 推奨イベント名を使う例
window.dataLayer.push({
  event: 'generate_lead',
  currency: 'JPY',
  value: 0
});
```

### キーイベント（コンバージョン）への登録

イベントが計測されていても、キーイベントとしてマークしないとコンバージョンレポートには反映されません。

1. GA4管理画面の **「データの表示」>「キーイベント」** を開く
2. 「新しいキーイベント」をクリックし、イベント名を登録する

## デバッグチェックリスト

フォーム送信の計測が取れないときは、以下の順にチェックしてください。

- [ ] GTMプレビューモードでタグが「Tags Fired」に表示されるか
- [ ] トリガー種別（フォーム送信 / クリック / カスタムイベント）は正しいか
- [ ] フォームの送信方式（HTML標準 / AJAX）を確認したか
- [ ] AJAX送信の場合、dataLayerプッシュまたはカスタムHTMLで対応したか
- [ ] GA4 DebugViewにイベントが表示されるか
- [ ] GA4の測定ID（G-XXXXXXXXXX）は正しいか
- [ ] イベント名のスペルミスがないか（GA4は大文字・小文字を区別する）
- [ ] キーイベントとして登録済みか

:::message
GA4のリアルタイムレポートにデータが反映されるまで数分かかることがあります。DebugViewのほうがリアルタイム性が高いので、デバッグ中はDebugViewを使いましょう。
:::

## まとめ

フォーム送信の計測が取れない原因は、大きく分けて以下の3層に分かれます。

1. **GTM層**: トリガーが発火していない（設定ミス・フォーム方式の不一致）
2. **通信層**: タグは発火しているがGA4にデータが届いていない（測定IDミスなど）
3. **GA4層**: データは届いているがレポートに表示されていない（イベント設定・キーイベント未登録）

この3層を順番に切り分ければ、原因の特定にかかる時間を大幅に短縮できます。

---

GA4やGTMの設定でお困りの方は、お気軽にご相談ください。計測設計からデバッグ、BigQuery連携まで対応しています。

https://coconala.com/services/3332133
