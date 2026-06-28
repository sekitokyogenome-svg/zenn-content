---
title: "EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例"
emoji: "📉"
type: "idea"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「商品ページのPVはそこそこあるのに、カートに入れてもらえない」――EC運営者であれば、一度はこの壁にぶつかったことがあるはずです。

GA4の標準レポートでも離脱率は確認できますが、「どの商品ページが特に離脱されやすいのか」「改善施策の前後で数値がどう変わったか」を正確に追いたい場合、BigQueryでの直接分析が有効です。

自分が担当していた某EC案件でも、商品ページの離脱率をBigQueryで深掘りしたことで、改善の優先度が見えるようになりました。本記事では、そのときに使ったSQLと分析アプローチ、改善施策の効果検証方法を紹介します。

---

## 商品ページの離脱率とは

ここでいう「商品ページの離脱率」は、商品詳細ページを閲覧したセッションのうち、次のアクション（カート追加や別ページへの遷移）を取らずにサイトを離れたセッションの割合です。

```text
商品ページ離脱率 = 商品ページで離脱したセッション数 / 商品ページを閲覧したセッション数 × 100
```

GA4の標準UIだとページ単位の離脱率は出せますが、「商品カテゴリ別」「流入元別」などの切り口を掛け合わせるのが難しい。ここがBigQueryの出番です。

---

## 基本SQL：商品ページ別の離脱率を算出する

まずは商品ページごとの離脱率を出すクエリです。`page_view` イベントのうち、そのセッション内で最後に閲覧されたページを「離脱ページ」として判定します。

```sql
WITH session_pages AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_timestamp
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'page_view'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
last_page_per_session AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    ARRAY_AGG(page_location ORDER BY event_timestamp DESC LIMIT 1)[OFFSET(0)] AS exit_page
  FROM session_pages
  GROUP BY user_pseudo_id, ga_session_id
),
product_page_views AS (
  SELECT
    sp.user_pseudo_id,
    sp.ga_session_id,
    sp.page_location,
    CASE WHEN lp.exit_page = sp.page_location THEN 1 ELSE 0 END AS is_exit
  FROM session_pages sp
  JOIN last_page_per_session lp
    ON sp.user_pseudo_id = lp.user_pseudo_id
    AND sp.ga_session_id = lp.ga_session_id
  WHERE sp.page_location LIKE '%/products/%'
)
SELECT
  page_location,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS total_sessions,
  SUM(is_exit) AS exit_sessions,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_page_views
GROUP BY page_location
HAVING total_sessions >= 10
ORDER BY exit_rate DESC;
```

`HAVING total_sessions >= 10` で、サンプル数が少なすぎるページを除外しています。閾値は扱うデータ量に応じて調整してください。

---

## 流入元別に商品ページ離脱率を比較する

離脱率が高い原因を探るとき、流入元別の切り口が役立ちます。広告経由とオーガニック検索経由では、ユーザーの期待値が異なるためです。

```sql
WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_exits AS (
  -- 前述のクエリで算出した商品ページ別の離脱フラグを使う
  SELECT
    user_pseudo_id,
    ga_session_id,
    is_exit
  FROM product_page_views
)
SELECT
  IFNULL(ss.source, '(direct)') AS source,
  IFNULL(ss.medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  SUM(pe.is_exit) AS exit_sessions,
  ROUND(SUM(pe.is_exit) / COUNT(*) * 100, 1) AS exit_rate
FROM product_exits pe
JOIN session_source ss
  ON pe.user_pseudo_id = ss.user_pseudo_id
  AND pe.ga_session_id = ss.ga_session_id
GROUP BY source, medium
ORDER BY sessions DESC;
```

自分の案件では、SNS広告経由の離脱率がオーガニック検索の約1.5倍高いことが判明しました。広告クリエイティブと商品ページの内容にギャップがあったことが原因だった、という事例です。

---

## 改善施策の前後比較SQL

施策を打った後に「本当に効果があったのか」を検証するためのSQLです。施策実施日を境にして、前後の期間で離脱率を比較します。

```sql
WITH product_exit_data AS (
  -- 前述のproduct_page_viewsと同様のロジック
  -- _TABLE_SUFFIXを広めに取る（施策前後をカバーする期間）
  SELECT
    page_location,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    is_exit,
    user_pseudo_id,
    ga_session_id
  FROM product_page_views_with_date
)
SELECT
  page_location,
  CASE
    WHEN event_date < '2026-03-15' THEN 'before'
    ELSE 'after'
  END AS period,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  SUM(is_exit) AS exits,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_exit_data
WHERE page_location = '/products/target-product'
GROUP BY page_location, period
ORDER BY period;
```

:::message
施策前後の期間は、季節性やキャンペーンの影響を受けにくい期間を選ぶことが大切です。前後それぞれ2週間程度を比較対象にすると、短期的な変動に惑わされにくくなります。
:::

---

## 某EC案件での改善事例

自分が担当した某美容系ECでの事例を紹介します（数値は実際のデータに基づいていますが、クライアント情報は匿名化しています）。

### 分析で見えた課題

| 指標 | 改善前 |
|------|--------|
| 商品ページ離脱率（全体） | 68.3% |
| SNS広告経由の離脱率 | 78.1% |
| オーガニック検索経由の離脱率 | 52.4% |

SNS広告経由の離脱率が特に高い。広告では「期間限定セール」を訴求していたが、遷移先の商品ページにはセール情報の表示がなく、ユーザーが混乱していたことが原因でした。

### 実施した施策

1. 広告経由の遷移先にセール価格・割引率を目立つ位置に表示
2. 商品画像の上にレビュー評価を追加（社会的証明）
3. 「カートに追加」ボタンをファーストビュー内に移動

### 改善後の結果

| 指標 | 改善前 | 改善後 | 変化 |
|------|--------|--------|------|
| 商品ページ離脱率（全体） | 68.3% | 59.7% | -8.6pt |
| SNS広告経由の離脱率 | 78.1% | 63.2% | -14.9pt |

特にSNS広告経由での改善幅が大きかった。「広告で見せたものが商品ページにもある」という一貫性が離脱率に直結していたわけです。

---

## LookerStudioでモニタリングする

一度きりの分析で終わらせず、継続的にモニタリングする仕組みを作ることをおすすめします。BigQueryをデータソースにしてLookerStudioに接続すれば、日次・週次で離脱率の推移を確認できるダッシュボードが作れます。

チェックすべきポイントは以下の3つです。

- **離脱率の週次推移**：急上昇したタイミングがあれば、サイト変更やキャンペーン開始と照合する
- **離脱率ワーストの商品TOP10**：改善優先度の判断材料にする
- **流入元×離脱率のクロス集計**：広告費の配分見直しに活用する

---

## まとめ

商品ページの離脱率は、EC運営者にとって改善インパクトが大きい指標です。GA4の標準レポートではざっくりとした数値しか見えませんが、BigQueryで分析すると「どの商品が」「どの流入元で」「どれだけ離脱しているか」が明確になります。

自分としては、離脱率の改善は「ページのどこに問題があるか」よりも「ユーザーの期待と実際のページ内容のギャップをどう埋めるか」が本質だと感じています。

皆さんのECサイトでは、商品ページの離脱率をどのように把握・改善していますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
