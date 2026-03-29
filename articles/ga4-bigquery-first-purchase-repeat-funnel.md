---
title: "GA4×BigQueryで初回購入→リピートまでのファネルを可視化する"
emoji: "🔄"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「新規顧客の獲得には広告費をかけているのに、リピート率がどのくらいなのか把握していない」「GA4のレポートで購入数は見ているが、同じユーザーが2回目・3回目を買っているかわからない」――EC運営でこんな状況に心当たりはないでしょうか。

多くのEC事業者は新規獲得に意識が向きがちですが、実は**リピート購入率こそが収益性を左右する最重要指標**です。本記事では、GA4のBigQueryエクスポートデータを使って、初回購入からリピートまでのファネルをSQLで可視化する方法を解説します。

## なぜリピート購入率が重要なのか

ECにおけるリピート購入率の重要性は、以下の3点に集約されます。

| 観点 | 内容 |
|---|---|
| **LTV（顧客生涯価値）** | リピート率が10%改善するだけでLTVは大幅に向上する |
| **広告費の回収** | 新規獲得コスト（CPA）を1回の購入で回収できないビジネスモデルでは、リピートなしに黒字化しない |
| **利益率** | 既存顧客への販売は新規獲得の5〜7分の1のコストで済むとされる |

:::message
リピート率を把握していないECは、バケツの穴を塞がずに水を注ぎ続けているようなものです。まずは現状を数字で把握することが改善の第一歩です。
:::

## 前提：テーブル構成

GA4のBigQueryエクスポートテーブル（`analytics_XXXXXX.events_*`）を使用します。購入イベントは`purchase`で、ユーザー識別には`user_pseudo_id`を使います。

## Step 1：ユーザーごとの初回購入日を特定する

まず、各ユーザーの初回購入日と購入回数を整理します。

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id,
    ecommerce.purchase_revenue
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

user_purchases AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    transaction_id,
    purchase_revenue,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number,
    MIN(purchase_date) OVER (
      PARTITION BY user_pseudo_id
    ) AS first_purchase_date
  FROM purchases
)

SELECT * FROM user_purchases
ORDER BY user_pseudo_id, purchase_number;
```

このクエリで、各ユーザーの購入が何回目なのか、初回購入日はいつだったのかが一目でわかるようになります。

## Step 2：2回目・3回目の購入と購入間隔を算出する

次に、購入回数ごとの日数間隔を計算します。

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

numbered AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

with_intervals AS (
  SELECT
    user_pseudo_id,
    purchase_number,
    purchase_date,
    LAG(purchase_date) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_number
    ) AS prev_purchase_date,
    DATE_DIFF(
      purchase_date,
      LAG(purchase_date) OVER (
        PARTITION BY user_pseudo_id
        ORDER BY purchase_number
      ),
      DAY
    ) AS days_since_prev_purchase
  FROM numbered
)

SELECT
  purchase_number,
  COUNT(*) AS user_count,
  ROUND(AVG(days_since_prev_purchase), 1) AS avg_days_between,
  APPROX_QUANTILES(days_since_prev_purchase, 2)[OFFSET(1)] AS median_days_between
FROM with_intervals
GROUP BY purchase_number
ORDER BY purchase_number;
```

:::message alert
`days_since_prev_purchase`が極端に長い（180日以上など）場合は、実質的に離脱→再獲得であり、純粋なリピートとは区別して分析するのが望ましいです。
:::

## Step 3：月次コホート別リピート率を算出する

初回購入月ごとに、30日・60日・90日以内にリピート購入したユーザーの割合を出します。

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase_date
  FROM purchases
  GROUP BY user_pseudo_id
),

cohort_repeat AS (
  SELECT
    fp.user_pseudo_id,
    FORMAT_DATE('%Y-%m', fp.first_purchase_date) AS cohort_month,
    fp.first_purchase_date,
    MIN(
      CASE WHEN p.purchase_date > fp.first_purchase_date
      THEN p.purchase_date END
    ) AS second_purchase_date
  FROM first_purchase fp
  LEFT JOIN purchases p
    ON fp.user_pseudo_id = p.user_pseudo_id
  GROUP BY fp.user_pseudo_id, fp.first_purchase_date
)

SELECT
  cohort_month,
  COUNT(*) AS first_time_buyers,
  COUNTIF(second_purchase_date IS NOT NULL) AS repeat_buyers,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) AS repeat_within_30d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) AS repeat_within_60d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) AS repeat_within_90d,
  ROUND(COUNTIF(second_purchase_date IS NOT NULL) / COUNT(*) * 100, 1) AS repeat_rate_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) / COUNT(*) * 100, 1) AS repeat_30d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) / COUNT(*) * 100, 1) AS repeat_60d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) / COUNT(*) * 100, 1) AS repeat_90d_pct
FROM cohort_repeat
GROUP BY cohort_month
ORDER BY cohort_month;
```

この結果を見ることで、「初回購入から30日以内にリピートする割合が低い月」や「特定のキャンペーン月にリピート率が跳ねている」といった傾向が見えてきます。

## Step 4：ファネル形式で可視化用データを作成する

1回目→2回目→3回目の購入到達率をファネル形式で出力します。

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `your_project.analytics_XXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

numbered AS (
  SELECT
    user_pseudo_id,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

funnel AS (
  SELECT
    purchase_number,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM numbered
  WHERE purchase_number <= 5
  GROUP BY purchase_number
)

SELECT
  purchase_number,
  users,
  FIRST_VALUE(users) OVER (ORDER BY purchase_number) AS first_purchase_users,
  ROUND(users / FIRST_VALUE(users) OVER (ORDER BY purchase_number) * 100, 1) AS retention_pct,
  ROUND(users / LAG(users) OVER (ORDER BY purchase_number) * 100, 1) AS step_conversion_pct
FROM funnel
ORDER BY purchase_number;
```

出力イメージは以下の通りです。

| purchase_number | users | retention_pct | step_conversion_pct |
|---|---|---|---|
| 1 | 1,000 | 100.0% | - |
| 2 | 150 | 15.0% | 15.0% |
| 3 | 80 | 8.0% | 53.3% |
| 4 | 55 | 5.5% | 68.8% |
| 5 | 42 | 4.2% | 76.4% |

:::message
注目すべきは`step_conversion_pct`の推移です。1回目→2回目の転換率が最も低く、2回目以降は上昇していくのが一般的なパターンです。つまり「2回目の壁」を超えさせることがリピート戦略の最重要ポイントになります。
:::

## Looker Studioでの可視化

上記のクエリ結果をLooker Studioに接続して可視化します。

**おすすめのグラフ構成：**

1. **ファネルチャート（棒グラフ）**: Step 4のクエリ結果を使い、購入回数ごとのユーザー数を棒グラフで表示
2. **コホートヒートマップ（ピボットテーブル）**: Step 3のクエリ結果を使い、月次×リピート期間の割合をヒートマップ風に色分け
3. **スコアカード**: 全体のリピート率、平均リピート日数、3回以上購入者の割合をKPIとして表示

Looker StudioからBigQueryに直接接続し、カスタムクエリとして上記SQLを設定するのが最も手軽な方法です。日付パラメータを設定しておくと、期間を絞り込んだ分析も可能になります。

## データから導くリピート率改善の打ち手

ファネルとコホートのデータが揃ったら、以下の観点で改善施策を検討します。

| データの示唆 | 打ち手 |
|---|---|
| 1回目→2回目の転換率が低い | 初回購入後7日以内のフォローメール、次回使えるクーポン配布 |
| リピートまでの日数が長い | 消耗品なら使い切りタイミングでのリマインド配信 |
| 特定コホート月のリピート率が高い | その月のキャンペーン施策を分析し、再現可能な要素を抽出 |
| 3回目→4回目の転換率が高い | 3回購入した顧客はロイヤル化しやすい。2回目→3回目の壁を突破する施策に注力 |
| 特定商品の初回購入者がリピートしやすい | その商品を初回購入の導線（LP・広告）で優先的に訴求 |

:::message
リピート施策はデータに基づいて優先順位をつけることが重要です。「なんとなくメルマガを送る」のではなく、ファネルのどこにボトルネックがあるかを把握した上で施策を設計しましょう。
:::

## まとめ

GA4×BigQueryを使えば、購入ファネルの可視化からリピート率のコホート分析まで、SQLだけで実現できます。

- **初回購入日の特定**と購入回数の付与が分析の起点
- **月次コホート別のリピート率**で時系列のトレンドを把握
- **ファネル形式**で「2回目の壁」の大きさを数値化
- Looker Studioと接続して**経営判断に使えるダッシュボード**を構築

リピート率の改善は、新規獲得の広告費を増やすよりも確実にLTVを伸ばす手段です。まずは自社のデータで現状を可視化することから始めてみてください。

---

「GA4×BigQueryの環境構築やリピート分析のダッシュボード作成を依頼したい」という方は、以下のサービスページからお気軽にご相談ください。

https://coconala.com/services/1791205
