---
title: "GA4×BigQueryでカート放棄率を正確に計測・改善する方法"
emoji: "🛒"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「カゴ落ちが多いのはわかっているけど、実際の放棄率が何%なのか正確に把握できていない」――EC運営者にとって、カート放棄（カゴ落ち）は売上損失に直結する課題です。

GA4の標準UIでもファネルレポートは確認できますが、デバイス別・流入元別・商品別といった切り口での深掘りには限界があります。とくに「どの商品がカゴ落ちされやすいのか」「モバイルとPCでどれだけ差があるのか」を定量的に把握するには、BigQueryでの直接分析が必要です。

本記事では、GA4のBigQueryエクスポートデータを使って、カート放棄率を正確に計測し、改善につなげるためのSQLと分析手法を紹介します。

---

## カート放棄率とは

カート放棄率（Cart Abandonment Rate）は、以下の式で算出します。

```text
カート放棄率 = (カートに追加したが購入しなかったユーザー数) / (カートに追加したユーザー数) × 100
```

GA4のイベントに対応させると、`add_to_cart` イベントを発火したユーザーのうち、`purchase` イベントを発火しなかったユーザーの割合です。

:::message
業界平均のカート放棄率は約70%前後と言われています。自社の数値がこの水準と比べてどうかを把握することが、改善の第一歩です。
:::

---

## 基本SQL：カート放棄率を算出する

まずは全体のカート放棄率を算出するクエリです。

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id;
```

`LEFT JOIN` で `purchase` イベントが存在しないユーザーを「放棄したユーザー」として特定します。`_TABLE_SUFFIX` の範囲は分析対象の期間に合わせて変更してください。

---

## デバイス別のカート放棄率

モバイルはPCに比べて放棄率が高い傾向があります。デバイス別に集計して差分を確認しましょう。

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    device.category AS device_category
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  a.device_category,
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id
GROUP BY a.device_category
ORDER BY cart_abandonment_rate DESC;
```

:::message alert
`device.category` はイベント発火時点のデバイスが記録されます。同一ユーザーが複数デバイスで操作する場合、`user_pseudo_id` はデバイスごとに異なる点に注意してください。クロスデバイス分析が必要な場合は `user_id`（ログインID）の利用を検討しましょう。
:::

---

## 流入元別のカート放棄率

どの流入経路からのユーザーが放棄しやすいかを把握すると、広告やSEOの改善に直結します。

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  a.traffic_source,
  a.traffic_medium,
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id
GROUP BY a.traffic_source, a.traffic_medium
HAVING COUNT(*) >= 10
ORDER BY cart_abandonment_rate DESC;
```

`HAVING COUNT(*) >= 10` でサンプル数が少ない流入元を除外しています。閾値はサイト規模に応じて調整してください。

---

## 商品別のカゴ落ち分析

どの商品がカートに入れられたのに購入されていないかを特定することで、価格設定や商品ページの改善ポイントが見えてきます。

```sql
WITH cart_items AS (
  SELECT
    user_pseudo_id,
    item.item_id,
    item.item_name
  FROM `beeracle.analytics_263425816.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchased_items AS (
  SELECT
    user_pseudo_id,
    item.item_id
  FROM `beeracle.analytics_263425816.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  c.item_id,
  c.item_name,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id) AS abandoned_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS abandonment_rate
FROM cart_items c
LEFT JOIN purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.item_id = p.item_id
GROUP BY c.item_id, c.item_name
HAVING COUNT(DISTINCT c.user_pseudo_id) >= 5
ORDER BY abandoned_users DESC
LIMIT 20;
```

放棄ユーザー数が多い商品は、改善のインパクトが大きい優先ターゲットです。

---

## カゴ落ちの主な原因と改善施策

カート放棄率が高い場合、以下の原因と施策が考えられます。

| 原因 | 改善施策 |
|------|----------|
| 送料がカート画面で初めて表示される | 商品ページや一覧で送料を事前表示する |
| 決済手段が少ない | クレジットカード以外にPayPay・コンビニ払いなどを追加 |
| 会員登録が必須 | ゲスト購入を導入する |
| モバイルでの入力が面倒 | フォームの最適化・住所自動入力の導入 |
| 商品ページの情報不足 | レビュー・サイズ・使用感の情報を充実させる |
| 単純に「あとで買おう」と思っている | カゴ落ちリマインドメール・リターゲティング広告 |

:::message
すべてを一度に改善する必要はありません。上記のSQLで特定した「放棄率が高いデバイス・流入元・商品」から優先的に対処するのが効果的です。
:::

---

## 改善の効果を時系列で追跡する

施策を実施したら、カート放棄率の推移をモニタリングしましょう。以下のクエリで週次の推移を確認できます。

```sql
WITH weekly_cart AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
),
weekly_purchase AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
)
SELECT
  c.week_start,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS cart_abandonment_rate
FROM weekly_cart c
LEFT JOIN weekly_purchase p
  ON c.week_start = p.week_start
  AND c.user_pseudo_id = p.user_pseudo_id
GROUP BY c.week_start
ORDER BY c.week_start;
```

このクエリをLooker Studioに接続すれば、施策実施前後の変化を視覚的に確認できます。放棄率が継続的に下がっているかどうかが、改善施策の成否を判断する指標になります。

---

## まとめ

カート放棄率はEC運営において最も改善インパクトの大きい指標の一つです。GA4のUI上では把握しにくい「デバイス別」「流入元別」「商品別」の詳細な分析も、BigQueryを使えばSQLで正確に算出できます。

本記事で紹介したポイントをまとめます。

- カート放棄率 = `add_to_cart` したが `purchase` しなかったユーザーの割合
- デバイス別に見ると、モバイルの放棄率が高いケースが多い
- 流入元別の分析で、広告やSEOの改善優先度が見える
- 商品別のカゴ落ち分析で、改善インパクトの大きい商品を特定できる
- 施策実施後は週次で推移を追跡し、効果を検証する

「GA4×BigQueryの分析基盤を構築したい」「カゴ落ち改善のためのデータ環境を整えたい」という方は、お気軽にご相談ください。

https://coconala.com/services/1791205
