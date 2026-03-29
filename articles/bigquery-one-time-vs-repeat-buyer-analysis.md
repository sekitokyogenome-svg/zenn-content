---
title: "BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した"
emoji: "🔄"
type: "idea"
topics: ["bigquery", "ec", "dataanalytics"]
published: false
---

## はじめに

ECサイトの収益を伸ばすうえで、リピーターの存在は欠かせません。しかし、「なぜリピートするユーザーとしないユーザーがいるのか」を感覚ではなくデータで理解できている事業者は少ないのではないでしょうか。

1回だけ購入して離脱するユーザーと、2回以上購入するユーザーの間には、初回訪問時の行動に明確な差があるケースが多いです。この差を分析できれば、リピート率を向上させるための施策を立案する根拠になります。

この記事では、BigQueryでGA4の生データを使い、購入回数別にユーザーの行動パターンを比較する方法を解説します。

---

## 分析の全体設計

分析は以下の3ステップで進めます。

1. ユーザーごとの購入回数を集計し、1回購入者とリピーターに分類する
2. 各グループの初回セッションにおける行動指標を比較する
3. 流入元の違いを確認する

---

## ユーザーを購入回数で分類するSQL

まず、ユーザーごとの購入回数を集計します。

```sql
WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  CASE
    WHEN purchase_count = 1 THEN 'one_time'
    ELSE 'repeat'
  END AS buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(purchase_count), 1) AS avg_purchases
FROM purchase_counts
GROUP BY buyer_type
```

:::message
購入回数のカウントは `purchase` イベントの回数で行っています。同一セッション内で複数回 `purchase` が発火するケースがある場合は、セッション単位でDEDUPする処理を追加してください。
:::

---

## 初回セッションの行動指標を比較する

リピーターと1回購入者で、初回セッション時の行動にどのような差があるかを調べます。

```sql
WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
    ROW_NUMBER() OVER(
      PARTITION BY e.user_pseudo_id
      ORDER BY e.event_timestamp
    ) AS event_seq
  FROM `beeracle.analytics_263425816.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

first_session_ids AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM first_sessions
  WHERE event_seq = 1
),

first_session_metrics AS (
  SELECT
    fs.user_pseudo_id,
    fsi.session_id,
    COUNTIF(fs.event_name = 'page_view') AS page_views,
    SUM(fs.engagement_time_msec) / 1000 AS engagement_sec,
    MAX(IF(fs.event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
    MAX(IF(fs.event_name = 'view_item', 1, 0)) AS has_view_item
  FROM first_sessions fs
  INNER JOIN first_session_ids fsi
    ON fs.user_pseudo_id = fsi.user_pseudo_id
    AND fs.session_id = fsi.session_id
  GROUP BY fs.user_pseudo_id, fsi.session_id
)

SELECT
  bt.buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(fsm.page_views), 1) AS avg_page_views,
  ROUND(AVG(fsm.engagement_sec), 1) AS avg_engagement_sec,
  ROUND(COUNTIF(fsm.has_view_item = 1) / COUNT(*) * 100, 1) AS view_item_rate,
  ROUND(COUNTIF(fsm.has_add_to_cart = 1) / COUNT(*) * 100, 1) AS add_to_cart_rate
FROM first_session_metrics fsm
INNER JOIN buyer_type bt ON fsm.user_pseudo_id = bt.user_pseudo_id
GROUP BY bt.buyer_type
```

結果のイメージは以下の通りです。

| buyer_type | users | avg_page_views | avg_engagement_sec | view_item_rate | add_to_cart_rate |
|-----------|-------|----------------|-------------------|----------------|-----------------|
| one_time | 230 | 4.2 | 120.5 | 78.3 | 52.1 |
| repeat | 68 | 7.8 | 245.3 | 95.6 | 82.4 |

---

## 結果から読み取れること

### リピーターは初回から行動量が多い

リピーターは初回セッションの時点で、ページ閲覧数やエンゲージメント時間が1回購入者を大きく上回る傾向があります。これは「じっくり商品を見て、ブランドに好感を持った上で購入している」可能性を示唆しています。

### 商品詳細ページの閲覧率に差がある

`view_item` の発生率に差がある場合、リピーターは購入前に複数の商品を比較検討していると考えられます。商品詳細ページの回遊性を高める施策（関連商品のレコメンドなど）が、リピート率向上に寄与する可能性があります。

---

## 流入元の違いを確認する

購入者タイプ別に流入元を比較すると、リピーターを生みやすいチャネルが見えてきます。

```sql
WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_touch AS (
  SELECT
    e.user_pseudo_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    ROW_NUMBER() OVER(PARTITION BY e.user_pseudo_id ORDER BY e.event_timestamp) AS rn
  FROM `beeracle.analytics_263425816.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'session_start'
)

SELECT
  bt.buyer_type,
  ft.source,
  ft.medium,
  COUNT(*) AS users
FROM first_touch ft
INNER JOIN buyer_type bt ON ft.user_pseudo_id = bt.user_pseudo_id
WHERE ft.rn = 1
GROUP BY bt.buyer_type, ft.source, ft.medium
ORDER BY bt.buyer_type, users DESC
```

たとえば、オーガニック検索経由のユーザーはリピート率が高く、SNS広告経由のユーザーは1回購入で離脱しやすいといった傾向が見えることがあります。

---

## 施策への活用

分析結果を踏まえて、以下のような施策を検討できます。

| 発見 | 施策案 |
|------|--------|
| リピーターは初回の閲覧ページ数が多い | 商品レコメンド・関連商品表示を強化する |
| リピーターは商品詳細を必ず見ている | 商品ページのコンテンツを充実させる |
| 特定チャネルからのリピート率が高い | そのチャネルへの投資を優先する |
| 1回購入者のエンゲージメント時間が短い | 購入後のフォローメールでブランド理解を促進する |

---

## まとめ

- 購入回数でユーザーを分類し、初回セッションの行動指標を比較することで、リピーターの特徴が見える
- リピーターは初回訪問時からページ閲覧数やエンゲージメント時間が長い傾向がある
- 流入元の違いも合わせて分析すれば、リピーターを生みやすいチャネルが特定できる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
