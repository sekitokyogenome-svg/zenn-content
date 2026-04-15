

```markdown
---
title: "GA4移行後にデータが取れていない問題を解決するGTMデバッグ手順"
emoji: "🔍"
type: "tech"
topics: ["GA4", "GTM", "BigQuery", "デバッグ", "EC"]
published: false
---

## 「GA4に移行したのに、コンバージョンが計測されていない…」

UA（ユニバーサルアナリティクス）からGA4に移行して数週間。ふとレポートを確認したら、**purchaseイベントが0件**。あるいは、セッション数が以前の半分以下。こんな状況に陥っているEC担当者の方、少なくないのではないでしょうか。

GA4移行後のデータ欠損は、原因の大半が**GTM（Googleタグマネージャー）の設定ミス**に起因しています。本記事では、実務で遭遇しやすい「データが取れていない」問題を、GTMのデバッグ機能を使って体系的に切り分ける手順を解説します。

## ステップ1：GTMプレビューモードで発火状況を確認

まずは基本中の基本、GTMのプレビューモードで**タグが正しく発火しているか**を確認します。

1. GTM管理画面右上の「プレビュー」をクリック
2. Tag Assistantが起動したら、対象サイトのURLを入力して接続
3. 対象ページでコンバージョン操作（購入完了など）を実行
4. 左カラムのイベント一覧で、該当タグが「Tags Fired」に入っているか確認

:::message
**よくある落とし穴：** GTMのワークスペースで変更を加えたのに「公開」していないケース。プレビューモードでは未公開の変更も反映されますが、本番環境には反映されません。変更後は必ずバージョンを公開してください。
:::

### チェックポイント

| 確認項目 | 正常 | 異常時の対処 |
|---|---|---|
| GA4設定タグの発火 | 全ページでFired | トリガー条件（All Pages）を確認 |
| イベントタグの発火 | 該当操作時にFired | トリガーの条件式・データレイヤー変数を確認 |
| 測定ID（G-XXXXX） | 正しいIDが入っている | GA4プロパティの管理画面で再取得 |

## ステップ2：データレイヤーの中身を検証する

ECサイトでpurchaseやadd_to_cartが取れない原因の多くは、**dataLayerにデータが正しくpushされていない**ことです。

Tag Assistantの「Data Layer」タブを開き、以下の構造でデータが入っているか確認します。

```javascript
// purchase イベントの正しいdataLayer構造（GA4形式）
dataLayer.push({
  event: "purchase",
  ecommerce: {
    transaction_id: "T-20240115-001",
    value: 12800,
    currency: "JPY",
    items: [
      {
        item_id: "SKU-001",
        item_name: "オーガニックコットンTシャツ",
        price: 6400,
        quantity: 2
      }
    ]
  }
});
```

:::message alert
**UA形式とGA4形式の混在に注意。** UA時代の `products` 配列や `id` / `name` フィールドは、GA4では `items` 配列の `item_id` / `item_name` に変わっています。移行時にこの書き換えが漏れているケースが非常に多いです。
:::

## ステップ3：GA4のDebugViewでリアルタイム検証

GTM側でタグが発火していても、GA4側で正しく受信できていないことがあります。GA4管理画面の**DebugView**を使って確認しましょう。

1. GTMのGA4設定タグで「デバッグモードを有効にする」にチェック（`debug_mode: true`）
2. GA4管理画面 → 「管理」→「DebugView」を開く
3. 対象ページで操作を実行し、イベントがリアルタイムで流れてくるか確認

DebugViewにイベントが表示されない場合、以下を疑います。

- **測定IDの不一致**（開発環境用と本番用が混在）
- **コンセント管理ツール（CMP）による送信ブロック**
- **広告ブロッカー拡張機能の影響**（検証時は無効化推奨）

## ステップ4：BigQueryエクスポートでデータ到達を最終確認

GA4のUIレポートには反映ラグやしきい値によるデータ非表示があるため、**BigQueryで直接確認する**のが最も正確です。

```sql
-- 直近7日間のpurchaseイベントとeコマースパラメータの確認
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  ecommerce.transaction_id,
  ecommerce.purchase_revenue,
  (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'currency') AS currency
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'purchase'
ORDER BY
  event_date DESC
LIMIT 100;
```

このクエリで**0件が返ってくる場合**、GTM→GA4→BigQueryのパイプラインのどこかが断絶しています。ステップ1〜3を順に遡って原因を特定してください。

逆に、BigQueryにはデータがあるのにGA4のUIレポートに表示されない場合は、**GA4側のフィルタ設定やカスタムディメンションの未登録**が原因の可能性があります。

## デバッグ手順まとめ：切り分けフロー

```
GTMプレビューでタグ発火確認
  ├─ 発火していない → トリガー条件・dataLayer pushを修正
  └─ 発火している
      → GA4 DebugViewで受信確認
          ├─ 表示されない → 測定ID・CMP・ブロッカーを確認
          └─ 表示されている
              → BigQueryで最終確認
                  ├─ データなし → BQエクスポート設定を確認
                  └─ データあり → GA4 UIのフィルタ・ディメンション設定を確認
```

:::message
GA4移行後のトラブルは、**「データが無い」のではなく「設定の接続が切れている」だけ**というケースがほとんどです。焦ってタグを追加する前に、まずこのフローで原因箇所を特定することをお勧めします。
:::

## まとめ

GA4移行後のデータ欠損は、GTMプレビュー → GA4 DebugView → BigQueryの3段階で切り分けることで、原因を高い精度で特定できます。特にECサイトでは、dataLayerのUA形式→GA4形式への書き換え漏れが最も多い原因です。

---

「GTMの設定を見直したいけど、どこが間違っているかわからない」「BigQueryのデータとGA4レポートの数字が合わない」——そんなお悩みがあれば、GA4×BigQuery×GTMの実務経験をもとにお手伝いします。

👉 **[ココナラでGA4・BigQuery活用の相談を受付中](https://coconala.com/services/1791205)**
```