

```markdown
---
title: "GTMでGA4のeコマース計測を完全設定する手順【Shopify対応】"
emoji: "🛒"
type: "tech"
topics: ["GA4", "GTM", "Shopify", "ecommerce", "BigQuery"]
published: false
---

## 「購入数は分かるけど、どこで離脱してるか分からない…」

ECサイトを運営していて、GA4の管理画面に「purchase」イベントだけがポツンと記録されている状態になっていませんか？

商品一覧の閲覧 → 商品詳細 → カート追加 → チェックアウト → 購入。このファネル全体を計測できてはじめて「どこで売上を取りこぼしているか」が見えてきます。

本記事では、Shopify＋GTM＋GA4の構成で、eコマースイベントをステップごとに設定する手順を解説します。

## 前提：GA4のeコマースイベント体系

GA4で推奨されているeコマースイベントは以下の通りです。

| ファネル段階 | イベント名 | 発火タイミング |
|---|---|---|
| 商品一覧表示 | `view_item_list` | カテゴリページ表示 |
| 商品詳細表示 | `view_item` | 商品ページ表示 |
| カート追加 | `add_to_cart` | カートボタンクリック |
| チェックアウト開始 | `begin_checkout` | チェックアウトページ表示 |
| 購入完了 | `purchase` | サンクスページ表示 |

これらすべてに `ecommerce` オブジェクト（items配列）を渡す必要があります。

## Step 1：ShopifyからdataLayerにeコマースデータを送る

Shopifyのテーマファイル（`theme.liquid`）に、各ページで適切な `dataLayer.push` を記述します。

### 商品詳細ページ（product.liquid / メインテーマのproductセクション）

```html
<script>
  window.dataLayer = window.dataLayer || [];
  dataLayer.push({ ecommerce: null }); // 前のecommerceオブジェクトをクリア
  dataLayer.push({
    event: "view_item",
    ecommerce: {
      currency: "JPY",
      value: {{ product.price | divided_by: 100.0 }},
      items: [{
        item_id: "{{ product.variants.first.sku }}",
        item_name: "{{ product.title | escape }}",
        price: {{ product.price | divided_by: 100.0 }},
        item_category: "{{ product.type | escape }}",
        quantity: 1
      }]
    }
  });
</script>
```

:::message
**重要**: Shopifyの価格はセント単位（日本円でも100倍された値）で格納されています。`divided_by: 100.0` で正しい金額に変換してください。環境によっては不要な場合もあるので、実際の出力値を確認しましょう。
:::

### カート追加（カートボタンのクリック時）

```html
<script>
document.querySelector('form[action="/cart/add"] button[type="submit"]')
  .addEventListener('click', function() {
    dataLayer.push({ ecommerce: null });
    dataLayer.push({
      event: "add_to_cart",
      ecommerce: {
        currency: "JPY",
        value: {{ product.price | divided_by: 100.0 }},
        items: [{
          item_id: "{{ product.variants.first.sku }}",
          item_name: "{{ product.title | escape }}",
          price: {{ product.price | divided_by: 100.0 }},
          quantity: 1
        }]
      }
    });
  });
</script>
```

### 購入完了ページ（checkout の追加スクリプト or order status page）

Shopifyの**設定 > チェックアウト > 追加スクリプト**（または「注文状況ページ」のカスタムピクセル）に記述します。

```html
{% if first_time_accessed %}
<script>
  window.dataLayer = window.dataLayer || [];
  dataLayer.push({ ecommerce: null });
  dataLayer.push({
    event: "purchase",
    ecommerce: {
      transaction_id: "{{ order.name }}",
      value: {{ total_price | divided_by: 100.0 }},
      tax: {{ tax_price | divided_by: 100.0 }},
      shipping: {{ shipping_price | divided_by: 100.0 }},
      currency: "JPY",
      items: [
        {% for item in line_items %}
        {
          item_id: "{{ item.sku }}",
          item_name: "{{ item.title | escape }}",
          price: {{ item.final_price | divided_by: 100.0 }},
          quantity: {{ item.quantity }}
        }{% unless forloop.last %},{% endunless %}
        {% endfor %}
      ]
    }
  });
</script>
{% endif %}
```

:::message alert
`first_time_accessed` の条件分岐を入れないと、ページリロードのたびにpurchaseが重複送信されます。
:::

## Step 2：GTMでトリガーとタグを設定する

### 2-1. トリガーの作成

**トリガータイプ**：カスタムイベント

| トリガー名 | イベント名 |
|---|---|
| CE - view_item | `view_item` |
| CE - add_to_cart | `add_to_cart` |
| CE - purchase | `purchase` |

各イベントに対して1つずつトリガーを作成します。

### 2-2. タグの作成（GA4イベントタグ）

**タグタイプ**：Google アナリティクス: GA4 イベント

| 設定項目 | 値 |
|---|---|
| 測定ID | `G-XXXXXXXXXX` |
| イベント名 | `{{Event}}` ※組み込み変数 |
| eコマースデータを送信 | ✅ チェックを入れる（**Data Layer**を選択） |

:::message
「eコマースデータを送信」にチェックを入れ、ソースに「Data Layer」を選択するだけで、`dataLayer` の `ecommerce` オブジェクトが自動的にGA4に送られます。items配列のパラメータを個別にマッピングする必要はありません。
:::

この設定を、`view_item` / `add_to_cart` / `purchase` の各トリガーに紐づけたタグとして作成します（共通タグ1つにトリガー3つを紐づけてもOKです）。

## Step 3：GTMプレビューで検証する

1. GTMの「プレビュー」モードを起動
2. Shopifyの商品ページにアクセス → `view_item` が発火することを確認
3. カートに追加 → `add_to_cart` が発火することを確認
4. テスト注文で購入完了 → `purchase` の `ecommerce` オブジェクトに `transaction_id` と `items` が含まれていることを確認

**GA4のリアルタイムレポート**でもイベントが届いているか、同時にチェックしましょう。

## Step 4：BigQueryでファネル分析する

GA4のBigQueryエクスポートを有効にしていれば、以下のSQLでファネルの各段階のセッション数を集計できます。

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)
SELECT
  event_name,
  COUNT(DISTINCT session_id) AS sessions
FROM
  sessions
GROUP BY
  event_name
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
  END
```

このSQLの結果で「add_to_cartからbegin_checkoutへの遷移率が低い」と分かれば、カートページのUI改善が優先施策になります。数字でボトルネックを特定できるのがeコマース計測の最大のメリットです。

## まとめ

| ステップ | やること |
|---|---|
| 1 | Shopifyテーマに `dataLayer.push` を設置 |
| 2 | GTMでカスタムイベントトリガー＋GA4タグを作成 |
| 3 | プレビュー＋リアルタイムレポートで検証 |
| 4 | BigQueryでファネル分析し、改善箇所を特定 |

eコマース計測は「設定して終わり」ではなく、ファネルデータを見て改善アクションにつなげてこそ価値が出ます。

---

:::message
「設定が合っているか不安」「BigQueryでもっと深掘り分析したい」という方へ──
GA4・GTM・BigQueryの設定代行から分析レポート作成まで、ココナラで承っています。
👉 [GA4・BigQuery分析のご相談はこちら](https://coconala.com/services/1791205)
:::
```