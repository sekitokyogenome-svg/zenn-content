---
title: "GA4×BigQueryでEC定期購入の継続率を分析する"
emoji: "🔄"
type: "tech"
topics: ["bigquery", "ec", "subscription"]
published: false
---

## 定期購入ECの最大の課題は「継続率」

サブスクリプション型のECサイトを運営していると、新規獲得数ばかりに目が行きがちです。しかし、LTV（顧客生涯価値）を左右するのは、獲得した顧客がどれだけ長く継続してくれるかという「継続率」です。

「先月の解約が多かった気がする」「継続率が下がっている感覚がある」

こうした曖昧な認識のまま施策を打っても、改善の手応えは得られません。この記事では、GA4のデータをBigQueryに蓄積している環境で、定期購入の継続率をコホート分析で可視化する方法を解説します。

## 前提: GA4で定期購入を計測する仕組み

定期購入の継続率分析を行うには、GA4のeコマースイベントで以下のデータが取得できている前提です。

- `purchase` イベントが定期購入の初回・2回目以降それぞれで発火している
- `user_pseudo_id` でユーザーを一意に識別できる
- 購入日時（`event_timestamp`）が正確に記録されている

定期購入のステータス管理はバックエンドのDBに依存するため、GA4だけでは正確な「解約日」は取得できません。ここでは「購入イベントの発火有無」をもって継続・離脱を判定する方法を取ります。

## Step 1: 初回購入月の特定

まず、各ユーザーの初回購入月を特定します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  cohort_month,
  COUNT(*) AS new_subscribers
FROM first_purchase
GROUP BY cohort_month
ORDER BY cohort_month
```

このSQLで、月別の新規定期購入者数が算出できます。これがコホート分析のベースラインになります。

## Step 2: 月別継続率の算出

初回購入月をコホートとして、その後の各月に購入イベントがあったかどうかで継続を判定します。

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
monthly_purchases AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
    ) AS purchase_month
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, purchase_month
),
cohort_activity AS (
  SELECT
    fp.cohort_month,
    DATE_DIFF(
      PARSE_DATE('%Y-%m', mp.purchase_month),
      PARSE_DATE('%Y-%m', fp.cohort_month),
      MONTH
    ) AS months_since_first,
    COUNT(DISTINCT fp.user_pseudo_id) AS active_users
  FROM first_purchase fp
  INNER JOIN monthly_purchases mp
    ON fp.user_pseudo_id = mp.user_pseudo_id
  GROUP BY fp.cohort_month, months_since_first
),
cohort_size AS (
  SELECT
    cohort_month,
    COUNT(*) AS total_users
  FROM first_purchase
  GROUP BY cohort_month
)
SELECT
  ca.cohort_month,
  ca.months_since_first,
  cs.total_users,
  ca.active_users,
  ROUND(ca.active_users / cs.total_users * 100, 1) AS retention_pct
FROM cohort_activity ca
INNER JOIN cohort_size cs
  ON ca.cohort_month = cs.cohort_month
WHERE ca.months_since_first BETWEEN 0 AND 12
ORDER BY ca.cohort_month, ca.months_since_first
```

このクエリの出力は、コホート月ごとに「0ヶ月目（初月）は100%」「1ヶ月目はXX%」「2ヶ月目はYY%」という形式のテーブルになります。

## Step 3: チャーン率（解約率）の算出

継続率の裏返しがチャーン率です。月次チャーン率は以下のように計算します。

```sql
WITH retention_data AS (
  -- 上記Step 2のクエリをサブクエリとして利用
  -- ここでは簡略化のためWITH句で結果を受ける想定
  SELECT
    cohort_month,
    months_since_first,
    retention_pct
  FROM (
    -- Step 2のクエリ結果
  )
),
churn_calc AS (
  SELECT
    cohort_month,
    months_since_first,
    retention_pct,
    LAG(retention_pct) OVER (
      PARTITION BY cohort_month
      ORDER BY months_since_first
    ) AS prev_retention_pct
  FROM retention_data
)
SELECT
  cohort_month,
  months_since_first,
  retention_pct,
  ROUND(prev_retention_pct - retention_pct, 1) AS monthly_churn_pct
FROM churn_calc
WHERE months_since_first > 0
ORDER BY cohort_month, months_since_first
```

`LAG()` ウィンドウ関数を使って前月の継続率との差分を取ることで、各月のチャーン率が算出できます。

## 分析結果の読み方

コホート分析の結果を見る際に注目すべきポイントは3つあります。

**1. 初月→2ヶ月目の離脱率**

定期購入ECにおいて、初回購入から2回目の購入に至るかどうかが最大の分岐点です。ここでの離脱率が40%を超えている場合、初回体験（商品品質・配送速度・パッケージング）に課題がある可能性が高いです。

**2. チャーン率の安定化タイミング**

一般的に、継続月数が増えるにつれてチャーン率は低下し、ある時点で安定します。この安定化ポイントが3ヶ月目なのか6ヶ月目なのかによって、施策の打ち方が変わります。

**3. コホート間の比較**

施策を打った月のコホートと、それ以前のコホートを比較することで、施策の効果を定量的に評価できます。例えば「初回同梱物を改善した月」以降のコホートで2ヶ月目の継続率が改善しているかを確認します。

## GA4だけでは見えない限界

GA4のpurchaseイベントベースの分析には、以下の限界があります。

- バックエンドで処理される定期課金は、GA4に反映されないケースがある
- 「スキップ」「一時休止」と「解約」の区別ができない
- カート経由の購入のみが計測対象のため、自動課金は対象外になりやすい

より精度の高い分析を行うには、ECプラットフォームのAPIから取得した注文データをBigQueryに取り込み、GA4データと突合する構成が望ましいです。

## Looker Studioでの可視化

コホート分析の結果は、ヒートマップ形式のテーブルでLooker Studioに表示するのが効果的です。行をコホート月、列を経過月数、セルの色を継続率に連動させることで、どのコホートのどの時点で離脱が多いかが一目でわかります。

## まとめ

定期購入ECの成長には、新規獲得と同等以上に継続率の改善が重要です。BigQueryとGA4を使ったコホート分析で、まずは自社の継続率カーブを可視化するところから始めてみてください。データが見えるようになると、「どこに手を打つべきか」が具体的になります。

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
