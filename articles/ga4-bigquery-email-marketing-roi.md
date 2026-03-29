---
title: "GA4×BigQueryでメルマガのROIを正確に測定する"
emoji: "📧"
type: "tech"
topics: ["bigquery", "googleanalytics", "email"]
published: false
---

## はじめに

メルマガを配信しているEC事業者は多いですが、「メルマガ経由の売上がいくらで、配信コストに対してどれだけリターンがあるのか」を正確に把握できているでしょうか。

メール配信ツールのレポートでは開封率やクリック率は見られますが、その先の購入金額までは追えません。一方、GA4の標準レポートではメルマガ経由のセッション数はわかりますが、購入との紐付けが不十分なケースがあります。

この記事では、GA4のBigQueryエクスポートデータを使って、メルマガ流入からの購入を正確にトラッキングし、ROIを算出する方法を解説します。

---

## UTMパラメータの設計が前提

メルマガのROIを正確に測定するには、メール内のリンクに適切なUTMパラメータを付与する必要があります。

| パラメータ | 設定例 | 説明 |
|-----------|--------|------|
| `utm_source` | newsletter | 流入元の識別 |
| `utm_medium` | email | メディアタイプ |
| `utm_campaign` | 2025_spring_sale | キャンペーン名 |

GA4のBigQueryエクスポートでは、これらの値が `collected_traffic_source` フィールドに格納されます。

:::message
UTMパラメータが設定されていない場合、GA4はリファラーからメール流入を推定しますが、精度が大幅に低下します。メルマガのリンクには必ずUTMパラメータを付与してください。
:::

---

## メルマガ流入セッションを特定するSQL

まず、メルマガ経由のセッションを抽出し、セッション内の行動と購入を紐付けます。

```sql
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign AS campaign,
    event_name,
    event_timestamp,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(SUM(IF(event_name = 'purchase', revenue, 0)), 0) AS total_revenue,
  ROUND(
    COUNTIF(event_name = 'purchase')
    / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) * 100,
    2
  ) AS cvr
FROM email_sessions
GROUP BY campaign
ORDER BY total_revenue DESC
```

このSQLにより、キャンペーンごとのセッション数、購入数、売上、CVRが一覧で確認できます。

---

## セッションをまたいだアトリビューション

メルマガをクリックした直後に購入するユーザーだけでなく、数日後に別の経路から戻ってきて購入するケースもあります。この「間接的な貢献」も含めてROIを評価するには、セッションをまたいだアトリビューションが必要です。

```sql
WITH email_clicks AS (
  -- メルマガ経由で訪問したユーザーとその日時
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_campaign AS campaign,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS email_click_time
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'session_start'
  GROUP BY user_pseudo_id, campaign
),

purchases AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS purchase_time,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ec.campaign,
  COUNT(DISTINCT ec.user_pseudo_id) AS email_visitors,
  -- 直接CV（同日購入）
  COUNT(DISTINCT IF(
    DATE(p.purchase_time) = DATE(ec.email_click_time),
    ec.user_pseudo_id, NULL
  )) AS same_day_purchasers,
  -- 間接CV（7日以内に購入）
  COUNT(DISTINCT IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    ec.user_pseudo_id, NULL
  )) AS purchasers_within_7d,
  -- 7日以内の売上合計
  ROUND(SUM(IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    p.revenue, 0
  )), 0) AS revenue_within_7d
FROM email_clicks ec
LEFT JOIN purchases p ON ec.user_pseudo_id = p.user_pseudo_id
  AND p.purchase_time >= ec.email_click_time
GROUP BY ec.campaign
ORDER BY revenue_within_7d DESC
```

アトリビューションウィンドウを7日に設定していますが、自社の購買サイクルに合わせて調整してください。

---

## ROIを算出する

メルマガの配信コスト（メール配信ツールの月額費用＋制作工数）と売上を比較してROIを算出します。

```sql
-- 配信コストをキャンペーンごとに手動で設定する例
WITH campaign_costs AS (
  SELECT 'spring_sale_2025' AS campaign, 15000 AS cost UNION ALL
  SELECT 'weekly_20250301', 5000 UNION ALL
  SELECT 'weekly_20250308', 5000 UNION ALL
  SELECT 'weekly_20250315', 5000
),

email_revenue AS (
  SELECT
    collected_traffic_source.manual_campaign AS campaign,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'purchase'
  GROUP BY campaign
)

SELECT
  er.campaign,
  cc.cost,
  ROUND(er.revenue, 0) AS revenue,
  ROUND((er.revenue - cc.cost) / cc.cost * 100, 1) AS roi_pct
FROM email_revenue er
INNER JOIN campaign_costs cc ON er.campaign = cc.campaign
ORDER BY roi_pct DESC
```

:::message
配信コストを手動設定する代わりに、Google Sheetsに配信コストを管理してBigQueryの外部テーブルとして参照する方法もあります。運用を自動化したい場合はこの方法を検討してください。
:::

---

## メルマガの品質をセグメント別に評価する

全体のROIだけでなく、メルマガの種類ごとに効果を比較することも重要です。

| メルマガ種類 | 目的 | 重視すべき指標 |
|-------------|------|--------------|
| セールス告知 | 直接売上 | CVR、売上金額 |
| 新商品案内 | 興味喚起 | ページ閲覧数、滞在時間 |
| 定期ニュースレター | 関係維持 | 開封率、サイト再訪率 |

UTMの `campaign` パラメータにメルマガの種類を含めておけば、BigQuery上で種類別の分析が可能になります。命名規則の例として、`newsletter_weekly`、`promo_spring_sale`、`newitem_202503` のような形式が実用的です。

---

## まとめ

- UTMパラメータを適切に設定すれば、GA4×BigQueryでメルマガ経由の売上を正確に追跡できる
- 直接CVだけでなく、セッションをまたいだアトリビューション分析で間接的な貢献も評価できる
- 配信コストと売上を突き合わせることで、キャンペーンごとのROIが算出できる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
