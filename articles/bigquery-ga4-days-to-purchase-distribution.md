---
title: "ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する"
emoji: "📅"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

ECサイトを運営していると、「ユーザーが初めてサイトを訪れてから購入するまで何日かかるのか」が気になることがあります。

即日購入するユーザーもいれば、何週間も検討してから購入するユーザーもいます。この日数分布を正確に把握できれば、リマーケティング広告の配信期間やメルマガのタイミングを最適化するための根拠が得られます。

この記事では、GA4のBigQueryエクスポートデータを使って、初回訪問から購入までの日数分布を算出するSQLを解説します。

---

## 分析の考え方

分析のステップは以下の3つです。

1. ユーザーごとの初回訪問日を特定する
2. ユーザーごとの初回購入日を特定する
3. 両者の差分（日数）を算出し、分布を集計する

GA4の `first_visit` イベントと `purchase` イベントを使います。

---

## 初回訪問日と初回購入日を取得するSQL

```sql
WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  fv.user_pseudo_id,
  fv.first_visit_date,
  fp.first_purchase_date,
  DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
FROM first_visits fv
INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
```

:::message
`first_visit` イベントが記録されていないユーザーもいます。GA4の計測開始前から存在していたユーザーや、Cookieがリセットされたケースなどが該当します。分析対象期間の設定には注意してください。
:::

---

## 日数分布をヒストグラム用に集計する

上記の結果を日数ごとに集計し、ヒストグラム用のデータを生成します。

```sql
WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

days_calc AS (
  SELECT
    DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
  FROM first_visits fv
  INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
)

SELECT
  CASE
    WHEN days_to_purchase = 0 THEN '当日'
    WHEN days_to_purchase = 1 THEN '1日後'
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN '2-3日後'
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN '4-7日後'
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN '8-14日後'
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN '15-30日後'
    ELSE '31日以上'
  END AS purchase_timing,
  COUNT(*) AS users,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 1) AS pct
FROM days_calc
GROUP BY
  CASE
    WHEN days_to_purchase = 0 THEN 0
    WHEN days_to_purchase = 1 THEN 1
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN 2
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN 3
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN 4
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN 5
    ELSE 6
  END,
  purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '当日' THEN 0
    WHEN '1日後' THEN 1
    WHEN '2-3日後' THEN 2
    WHEN '4-7日後' THEN 3
    WHEN '8-14日後' THEN 4
    WHEN '15-30日後' THEN 5
    ELSE 6
  END
```

結果のイメージは以下のようになります。

| purchase_timing | users | pct |
|-----------------|-------|-----|
| 当日 | 145 | 48.2 |
| 1日後 | 38 | 12.6 |
| 2-3日後 | 29 | 9.6 |
| 4-7日後 | 35 | 11.6 |
| 8-14日後 | 22 | 7.3 |
| 15-30日後 | 18 | 6.0 |
| 31日以上 | 14 | 4.7 |

---

## 結果の読み方と施策への活用

### 当日購入が多い場合

即日購入の割合が高いサイトでは、初回訪問時のCVR最大化が重要です。ランディングページの購入導線を強化したり、初回限定クーポンを表示する施策が有効です。

### 検討期間が長い場合

7日以上かかるユーザーの割合が大きい場合は、リマーケティング広告やカート放棄メールの配信期間を延長することを検討してください。

### リマーケティング期間の設定根拠

多くのEC事業者が広告プラットフォームのデフォルト設定（7日や30日）をそのまま使っていますが、自社データに基づいて設定するほうが合理的です。

たとえば、購入者の90%が14日以内に購入しているのであれば、リマーケティングのオーディエンス期間を14日に設定することで、広告費を無駄なく配分できます。

```sql
-- 累積分布で「X日以内に何%が購入するか」を算出
WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

days_calc AS (
  SELECT
    DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
  FROM first_visits fv
  INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
)

SELECT
  days_to_purchase,
  COUNT(*) AS users,
  SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) AS cumulative_users,
  ROUND(SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) / SUM(COUNT(*)) OVER() * 100, 1) AS cumulative_pct
FROM days_calc
WHERE days_to_purchase <= 30
GROUP BY days_to_purchase
ORDER BY days_to_purchase
```

この累積分布を見れば、「購入者の80%は何日以内に購入しているか」が一目でわかります。

---

## Looker Studioでの可視化

BigQueryの集計結果をLooker Studioに接続すれば、ヒストグラムとして可視化できます。棒グラフのディメンションに `purchase_timing` を、指標に `users` を設定するだけで、購入までの日数分布が視覚的に把握できるようになります。

日次や月次でフィルターを追加すれば、季節やキャンペーンによる変動も観察できます。

---

## まとめ

- GA4の `first_visit` と `purchase` イベントの日付差分で、購入までの検討日数を算出できる
- 日数分布をヒストグラム化することで、ユーザーの購買行動パターンが見える
- リマーケティング広告の配信期間やメルマガのタイミングを、データに基づいて設定できる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
