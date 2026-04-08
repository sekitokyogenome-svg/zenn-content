

```markdown
---
title: "GA4×BigQueryで初回購入→リピートまでのファネルを可視化する"
emoji: "🔄"
type: "tech"
topics: ["GA4", "BigQuery", "EC", "SQL", "リピート分析"]
published: false
---

## 「初回購入はあるのに、なぜかリピートが伸びない…」

ECサイトを運営していて、新規顧客の獲得コストは把握しているけれど、**初回購入からリピートまでに何が起きているのか分からない**——そんな悩みを抱えていませんか？

GA4の標準レポートでは「リピーター」というセグメントは見られても、**初回購入からリピート購入に至るまでの日数分布や離脱ポイント**までは把握できません。BigQueryにエクスポートしたデータを使えば、この「見えないファネル」を可視化できます。

## 分析のゴール

今回作るのは以下の3つです。

1. **ユーザーごとの初回購入日・2回目購入日の特定**
2. **初回→リピートまでの日数分布**
3. **日数帯ごとのリピート転換率ファネル**

これにより、「初回購入後◯日以内にアプローチすべき」という具体的な施策タイミングが見えてきます。

## Step 1: ユーザーごとの購入回数と購入日を整理する

まず、GA4のBigQueryエクスポートテーブルから、ユーザーごとに購入イベントを時系列で並べます。

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.transaction_id,
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND ecommerce.transaction_id IS NOT NULL
),

ranked_purchases AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    revenue,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date ASC
    ) AS purchase_order
  FROM purchase_events
  GROUP BY user_pseudo_id, purchase_date, revenue, transaction_id
)

SELECT * FROM ranked_purchases
WHERE purchase_order <= 3
ORDER BY user_pseudo_id, purchase_order;
```

:::message
`transaction_id` が重複するケースがあるため、同一トランザクションの二重計上に注意してください。必要に応じて `DISTINCT` を加えましょう。
:::

## Step 2: 初回→リピートまでの日数を算出する

Step 1のCTEを活用して、初回購入日と2回目購入日の差分を計算します。

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND ecommerce.transaction_id IS NOT NULL
  GROUP BY user_pseudo_id, event_date, ecommerce.transaction_id
),

ranked AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id ORDER BY purchase_date
    ) AS purchase_order
  FROM purchase_events
),

first_and_second AS (
  SELECT
    f.user_pseudo_id,
    f.purchase_date AS first_purchase_date,
    s.purchase_date AS second_purchase_date,
    DATE_DIFF(s.purchase_date, f.purchase_date, DAY) AS days_to_repeat
  FROM ranked f
  LEFT JOIN ranked s
    ON f.user_pseudo_id = s.user_pseudo_id
    AND s.purchase_order = 2
  WHERE f.purchase_order = 1
)

SELECT
  CASE
    WHEN days_to_repeat IS NULL THEN '未リピート'
    WHEN days_to_repeat <= 7 THEN '0-7日'
    WHEN days_to_repeat <= 14 THEN '8-14日'
    WHEN days_to_repeat <= 30 THEN '15-30日'
    WHEN days_to_repeat <= 60 THEN '31-60日'
    WHEN days_to_repeat <= 90 THEN '61-90日'
    ELSE '91日以上'
  END AS repeat_bucket,
  COUNT(*) AS user_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM first_and_second
GROUP BY repeat_bucket
ORDER BY
  CASE repeat_bucket
    WHEN '0-7日' THEN 1
    WHEN '8-14日' THEN 2
    WHEN '15-30日' THEN 3
    WHEN '31-60日' THEN 4
    WHEN '61-90日' THEN 5
    WHEN '91日以上' THEN 6
    WHEN '未リピート' THEN 7
  END;
```

## 出力イメージと読み取り方

| repeat_bucket | user_count | percentage |
|:---:|---:|---:|
| 0-7日 | 320 | 3.2% |
| 8-14日 | 480 | 4.8% |
| 15-30日 | 750 | 7.5% |
| 31-60日 | 620 | 6.2% |
| 61-90日 | 280 | 2.8% |
| 91日以上 | 350 | 3.5% |
| 未リピート | 7,200 | 72.0% |

:::message alert
この例では**72%が未リピート**です。これは多くのECサイトで見られる典型的なパターンですが、逆に言えば初回購入後30日以内に**全リピーターの約半数**が2回目購入していることも読み取れます。
:::

## Step 3: 施策への落とし込み

このファネルデータから導ける施策例を整理します。

| 日数帯 | 推奨施策 |
|:---|:---|
| 0〜7日 | 購入直後のサンクスメールでクロスセル提案 |
| 8〜14日 | 商品到着後レビュー依頼＋次回クーポン配布 |
| 15〜30日 | 消耗品なら「そろそろ無くなりませんか？」リマインド |
| 31〜60日 | ステップメールで関連商品・新商品紹介 |
| 61日以上 | 休眠防止の限定オファー |

重要なのは、**自社ECの日数分布に合わせてメール配信やリターゲティングのタイミングを最適化すること**です。分析結果が「15-30日にリピートが集中」なら、20日前後に集中的にアプローチする設計が効果的です。

## Looker Studioでの可視化Tips

BigQueryの結果をLooker Studioに接続し、**積み上げ棒グラフ**で月別×日数帯のリピート分布を見ると、季節変動やキャンペーン効果の検証にも使えます。`first_purchase_date` を月でGROUP BYすれば、コホートごとの比較も可能です。

## まとめ

- GA4の標準レポートでは見えない**初回→リピートの日数分布**をBigQueryで可視化
- リピーターの過半数が集中する日数帯を特定し、**CRMの配信タイミングを最適化**
- 「未リピート」のボリュームを把握することで、投資対効果の高い施策を判断できる

---

:::message
**「SQLを書く時間がない」「分析はできても施策に落とし込めない」**という方へ——GA4×BigQueryの初期設定からリピート分析レポートの構築まで、まるごとサポートしています。
👉 [ココナラのサービスページはこちら](https://coconala.com/services/1791205)
:::
```