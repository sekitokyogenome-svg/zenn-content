---
title: "GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する"
emoji: "💰"
type: "tech"
topics: ["bigquery", "googleanalytics", "advertising"]
published: false
---

## はじめに

EC事業の成長には新規顧客の獲得が不可欠ですが、「新規顧客1人を獲得するのにいくらかかっているか」をチャネル別に把握できているでしょうか。

CAC（Customer Acquisition Cost：顧客獲得コスト）は、広告費÷新規顧客数という単純な式で計算できます。しかし、GA4の標準レポートだけでは「新規顧客」の定義が曖昧になりがちで、チャネル別のCACを正確に算出するのは困難です。

この記事では、GA4のBigQueryエクスポートデータを使って新規購入者をチャネル別に特定し、広告費データと突き合わせてCACを算出する方法を解説します。

---

## 新規顧客の定義

CACを計算するにあたって、「新規顧客」の定義を明確にする必要があります。

| 定義方法 | 判定基準 | 精度 |
|---------|---------|------|
| GA4の `first_visit` イベント | 初めてサイトを訪問したユーザー | Cookieベースのため低め |
| `purchase` イベントの初回発生 | 分析期間内で初めて購入したユーザー | 中程度 |
| CRMデータとの突合 | 会員登録日ベース | 高い |

この記事では、分析期間内で初めて `purchase` イベントが発生したユーザーを新規顧客として扱います。

:::message
Cookieベースの判定では、ブラウザ変更やCookie削除により同一ユーザーが複数の `user_pseudo_id` を持つケースがあります。より高精度な分析が必要な場合は、`user_id`（ログインID）を使った判定を検討してください。
:::

---

## チャネル別の新規購入者数を算出するSQL

新規購入者の初回購入時のチャネルを特定します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_detail AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN e.collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN e.collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN e.collected_traffic_source.manual_medium IS NULL
        OR e.collected_traffic_source.manual_medium = '(none)' THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source,
    e.ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
)

SELECT
  channel,
  source,
  COUNT(DISTINCT user_pseudo_id) AS new_customers,
  ROUND(SUM(revenue), 0) AS first_purchase_revenue,
  ROUND(AVG(revenue), 0) AS avg_first_purchase_value
FROM first_purchase_detail
GROUP BY channel, source
ORDER BY new_customers DESC
```

---

## 広告費データとの結合

CACを算出するには、チャネル別の広告費データが必要です。広告費はGA4には含まれないため、別途用意する必要があります。

### 方法1: 手動でCTEに記述する

```sql
WITH ad_costs AS (
  SELECT 'Paid Search' AS channel, 'google' AS source, 350000 AS monthly_cost UNION ALL
  SELECT 'Paid Search', 'yahoo', 150000 UNION ALL
  SELECT 'Social', 'instagram', 80000 UNION ALL
  SELECT 'Social', 'tiktok', 120000
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_channel AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source
  FROM `beeracle.analytics_263425816.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
    AND e.collected_traffic_source.manual_medium IN ('cpc', 'social')
),

new_customers_by_source AS (
  SELECT
    channel,
    source,
    COUNT(DISTINCT user_pseudo_id) AS new_customers
  FROM first_purchase_channel
  GROUP BY channel, source
)

SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.monthly_cost,
  ROUND(ac.monthly_cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN ad_costs ac ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
```

### 方法2: Google Sheetsを外部テーブルとして使う

広告費データをGoogle Sheetsで管理し、BigQueryの外部テーブルとして読み込む方法が運用に適しています。

```sql
-- Google Sheetsの外部テーブルを事前に作成しておく
-- CREATE EXTERNAL TABLE `beeracle.ad_costs.monthly_costs`
-- OPTIONS (
--   format = 'GOOGLE_SHEETS',
--   uris = ['https://docs.google.com/spreadsheets/d/XXXXX']
-- )

SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.cost AS monthly_cost,
  ROUND(ac.cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN `beeracle.ad_costs.monthly_costs` ac
  ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
```

---

## CACの評価基準

CACの数値だけ見ても、それが高いのか低いのかは判断できません。LTV（顧客生涯価値）との比率で評価します。

```sql
WITH customer_ltv AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  ROUND(AVG(total_revenue), 0) AS avg_ltv,
  ROUND(PERCENTILE_CONT(total_revenue, 0.5) OVER(), 0) AS median_ltv,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_count
FROM customer_ltv
LIMIT 1
```

一般的に、LTV:CACの比率が3:1以上であれば健全とされています。

| LTV:CAC比率 | 評価 |
|-------------|------|
| 1:1未満 | 赤字。広告費の見直しが必要 |
| 1:1〜3:1 | 損益分岐付近。改善の余地あり |
| 3:1以上 | 健全。投資対効果が出ている |
| 5:1以上 | 投資余力あり。広告費を増やす検討の余地あり |

---

## チャネル別CACの施策活用

CACの分析結果をもとに、以下のような意思決定が可能になります。

| 分析結果 | 施策 |
|---------|------|
| Google広告のCACが3,000円、Instagram広告が8,000円 | Google広告に予算を寄せる |
| TikTok広告のCACは高いがLTVも高い | リピート率を加味して投資判断する |
| オーガニック検索のCACが実質0円 | SEO施策を強化する |
| メルマガ経由のCACが低い | メルマガ登録導線を強化する |

CACは単月の数値だけでなく、トレンドの変化を追うことが重要です。月次でCACを算出し、Looker Studioでトレンドグラフとして可視化しておくと、広告効率の変化にすぐ気づけます。

---

## まとめ

- GA4の `purchase` イベントと `collected_traffic_source` を使えば、チャネル別の新規購入者を特定できる
- 広告費データ（手動CTE、Google Sheets外部テーブルなど）と結合してCACを算出する
- CACはLTVとの比率で評価し、チャネルごとの投資判断に活用する

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
