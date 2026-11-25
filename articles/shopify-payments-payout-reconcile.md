---
title: "Shopify Payments の入金を注文取引にひもづける — GraphQLで照合"
emoji: "🧮"
type: "tech"
topics: ["shopify", "graphql", "ec"]
published: true
---

## はじめに

Shopify の注文データを集計して「今月の売上」を出し、Shopify Payments の入金額と並べると、ほぼ確実に数字がずれます。注文の合計から手数料を引いても合わない、というのはよくある状況です。

注文単位の売上と、入金（payout）単位の現金の動きは、そもそも別の台帳です。ずれの原因を人間が目で追うと時間がかかるので、「入金ごとに、その入金に含まれた残高取引を取り、注文の決済取引と突き合わせる」という機械的な照合に落とすと整理しやすくなります。この記事はその手順を、公式ドキュメントの範囲で組み立てたものです（自分が実ストアで動かして確認したものではありません）。

この記事では、Admin GraphQL API の `ShopifyPaymentsBalanceTransaction` を使って、入金単位に残高取引を取得し、注文取引へひもづけ、手数料（fee）と純額（net）を分けて集計する流れを書きます。実装ログ寄りの内容です。

なお、この記事の対象は **Shopify Payments の入金のみ**です。PayPal や他社決済、コンビニ払い、代金引換などの入金は、この残高取引には現れないので別の仕組みで照合する必要があります。

### 注記

本文中のフィールド名は、執筆時点で公式ドキュメント（`ShopifyPaymentsBalanceTransaction` のオブジェクトリファレンス）で確認したものです。クエリのルートや引数、型の細部は API バージョンにより異なる可能性があります。実際に書く前に、必ず公式リファレンスで確認してください。オブジェクトのリファレンスには、操作するユーザーに `view_payouts` 権限が必要だと書かれています（これはスタッフの権限で、アプリのアクセススコープ名とは別です）。アプリから取得する場合に必要なアクセススコープは、公式のアクセススコープ一覧で確認してください。

## 何と何を突き合わせるのか

まず整理しておくべきなのは、照合レポートに出てくるのは **Shopify Payments の残高の動き**であって、売上ではないという点です。Shopify のヘルプでも、payout reconciliation report は残高の動きを示すものとして説明されています。入金は注文の発生とは別のスケジュールで行われるため、「3日に発生した注文」と「3日に入金された金額」は一致しません。

したがって照合の単位は次の3層になります。

1. 注文（Order）の中にある決済取引（Order Transaction）
2. Shopify Payments の残高取引（Balance Transaction）
3. 入金（Payout）

残高取引が両者をつなぐ橋になります。公式のオブジェクト定義を見ると、`ShopifyPaymentsBalanceTransaction` には、少なくとも次のフィールドがあります。

| フィールド | 使いどころ |
|---|---|
| `associatedPayout` | どの入金に含まれたか |
| `sourceOrderTransactionId` | どの注文取引から生じたか |
| `amount` | 取引の金額 |
| `fee` | 手数料 |
| `net` | 手数料などを差し引いた純額 |
| `transactionDate` | 取引日 |
| `type` | 取引の種別 |

この表のうち、照合のキーになるのは `associatedPayout` と `sourceOrderTransactionId` の2つです。残りは、集計するときの数値と分類に使います。

## 入金単位に残高取引を取る

取得の考え方はこうです。

1. 対象期間の入金（payout）を一覧で取る
2. 入金ごと、またはまとめて残高取引を取り、`associatedPayout` で入金に振り分ける
3. 残高取引の `sourceOrderTransactionId` を使って注文取引と結ぶ

クエリのイメージを示します。**これは構造を示すための擬似的な例で、そのまま動く保証はありません。** ルートのフィールド名や引数は、APIバージョンの公式リファレンスで確認してください。

```graphql
# イメージ。ルートや引数は公式リファレンスで確認すること
query {
  shopifyPaymentsAccount {
    balanceTransactions(first: 100) {
      nodes {
        transactionDate
        type
        amount { amount currencyCode }
        fee    { amount currencyCode }
        net    { amount currencyCode }
        sourceOrderTransactionId
        associatedPayout { id }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}
```

金額は `Money` 型として `amount` と `currencyCode` のペアで返ります。通貨が混在する店舗では、通貨ごとに分けて集計してください。別の通貨を無理に合算すると、あとで「為替の差」と「本当のずれ」の区別がつかなくなります。

ページングは `pageInfo` で最後まで取り切ります。途中で止めると、入金の一部の取引だけが欠けた状態で照合することになり、原因の特定が難しくなります。

## 注文取引と突き合わせる

注文側は、期間内の注文から決済取引（transactions）を取り、取引ごとにIDと金額、種別（売上・返金など）を持たせます。ここで気をつけたいのはIDの形式です。`sourceOrderTransactionId` と注文取引のIDで、`gid://shopify/...` 形式なのか数値だけなのかが揃っていないと、突き合わせても全件が不一致になります。照合の前に、実際に返ってきた値を見て形式を揃えてください。

以下は、取得済みのデータを突き合わせる処理の例です。**数値はすべて架空のサンプルで、実在の店舗や案件の結果ではありません。**

```python
from collections import defaultdict
from decimal import Decimal

# 架空のサンプルデータ
balance_txs = [
    {"payout": "P1", "src": "T100", "amount": Decimal("5000"), "fee": Decimal("180"), "net": Decimal("4820")},
    {"payout": "P1", "src": "T101", "amount": Decimal("3000"), "fee": Decimal("108"), "net": Decimal("2892")},
    {"payout": "P1", "src": None,   "amount": Decimal("-2000"), "fee": Decimal("0"),  "net": Decimal("-2000")},
]
order_txs = {"T100": {"order": "#1001"}, "T101": {"order": "#1002"}}

by_payout = defaultdict(lambda: {"amount": Decimal(0), "fee": Decimal(0), "net": Decimal(0), "unmatched": []})

for b in balance_txs:
    p = by_payout[b["payout"]]
    p["amount"] += b["amount"]
    p["fee"] += b["fee"]
    p["net"] += b["net"]
    if b["src"] not in order_txs:
        p["unmatched"].append(b)   # 注文に結べない残高取引

for payout, v in by_payout.items():
    print(payout, v["amount"], v["fee"], v["net"], len(v["unmatched"]))
```

金額の計算には `float` ではなく `Decimal` を使います。入金額の照合は1円単位で合わせたいので、浮動小数点の誤差が混ざる実装は避けたほうが安全です。

ここでの出力は、入金ごとに次の3つです。

- `amount` の合計（売上寄りの総額）
- `fee` の合計（手数料）
- `net` の合計（入金額に近い値）

そして、**注文取引に結べなかった残高取引（unmatched）**の一覧が出ます。この「結べなかったもの」が、照合の本題です。

## 結べなかった取引は何者か

注文に結べない残高取引は、バグではなく、注文に紐づかない動きであることが多いです。Shopify のヘルプ（入金が少ない・入金されない理由）には、入金額が想定と違う原因として、次のようなものが挙げられています。

- 調整
- チャージバック（不正請求などによる取り消し）
- 返金による控除
- リザーブ（保留される資金）
- 手数料と、その手数料にかかる税
- 通貨換算
- マイナス残高
- 保留

これらは、`sourceOrderTransactionId` を持たないか、元の注文の月と入金の月がずれる性質のものです。そこで `type` ごとに分けて集計し、「注文に結べるもの」「注文に結べないが種別が分かるもの」「どちらでもないもの」の3つに仕分ける形にすると、最後の「どちらでもないもの」だけを人間が見れば済みます。

`type` の取りうる値は API バージョンのドキュメントで確認してください。ここでは値の一覧は書きません。記憶に頼って分岐を書くと、種別が追加されたときに黙って取りこぼします。未知の種別は例外にせず、「その他」として拾って件数を出すほうが、あとで気づけます。

## fee と net を分けて持つ理由

売上の管理画面と入金額を直接比べると、差の大半は手数料に見えます。ただ、手数料だけを引けば合うとは限らず、返金控除や調整が混ざると計算が崩れます。そこで、次のように分けて保存しておくと原因を追いやすくなります。

- 取引ごとに `amount` / `fee` / `net` を別の列として保存する
- 入金ごとに、`net` の合計が実際の入金額と一致するかを検算する
- 一致しないときは、取りこぼし（ページング漏れ、期間の境界）を先に疑う

検算の式は単純で、入金に含まれる残高取引の `net` を合計したものが、その入金の額と合うかどうかを見ます。ここが合えば「取得は漏れていない」と言えます。合わないまま注文側の分析に進むと、原因を取り違えます。

## 運用で気をつけること

- 照合の基準日を決めておく。`transactionDate`（取引日）で見るのか、入金日で見るのか。月をまたぐ取引は、基準が違うだけで差として現れます
- 実行するたびに全件を取り直すより、入金IDを主キーにして保存しておくと、あとから再計算できます
- 権限不足のアプリでは取得できません。権限を追加すると再承認が必要になる場合があるので、先に確認してください
- 結果を会計ソフトに合わせるなら、ここで出した数字は「照合の材料」であって会計の結論ではありません

## この実装をやらなくてよい場合

- 月の入金件数が少なく、管理画面のCSVエクスポートを目で見て合わせられる規模なら、APIで組むほうが手間がかかります
- Shopify Payments 以外の決済が中心の店舗では、この方法で見える範囲が限られます
- 差が出たときに誰も原因を追わない運用なら、仕組みを作っても使われません。先に「ずれたら誰が何を見るか」を決めるほうが先です

## まとめ

入金と注文を結ぶ鍵は、`ShopifyPaymentsBalanceTransaction` の `associatedPayout` と `sourceOrderTransactionId` です。入金単位に残高取引を取り、注文取引と突き合わせ、`fee` と `net` を分けて集計すると、「結べない取引」だけが残ります。その中身が調整・返金控除・リザーブなどのどれなのかを分類するところまでを機械化すると、手作業で追う範囲がかなり絞れます。

自分はココナラで154件の案件に関わってきましたが、データの突合は「どこまでを自動化し、どこからを人が見るか」の線引きが成否を分けると感じています。実装の前に、その線引きを決めておくことをおすすめします。

## 関連記事

経営者・事業責任者向けに、Shopifyの売上の数字がレポートごとに変わる理由を整理した記事を自サイトに書いています。

- [Shopifyの売上がレポートごとに違う。返金は処理した月に引かれます](https://logical-web.jp/blog/shopify-sales-refund-counted-on-processed-date/?utm_source=zenn&utm_medium=article&utm_campaign=related_article)

---

データ基盤や計測まわりの相談は、[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)で受け付けています。
