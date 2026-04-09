---
title: "中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】"
emoji: "📊"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「LTVが大事なのは分かっているけど、具体的にどう計算すればいいの？」

中小ECを運営していると、広告代理店やマーケティング記事で「LTVを見ましょう」と言われることが増えてきます。しかし、実際にLTVを計算しようとすると、Shopifyの管理画面やGA4の標準レポートだけでは限界があり、手が止まってしまう方が多いのではないでしょうか。

この記事では、**GA4のBigQueryエクスポート**を使って、SQLコピペだけでLTV分析の基盤を無料で構築する方法を解説します。BigQueryの無料枠（毎月1TBのクエリ、10GBのストレージ）の範囲で十分に運用可能です。

---

## ECにおけるLTVとは

LTV（Life Time Value / 顧客生涯価値）とは、**1人の顧客が取引期間全体を通じてもたらす売上の合計**です。

ECにおいてLTVが重要な理由はシンプルです。

- **広告費の上限が決まる**: LTVが10,000円なら、新規獲得コスト（CAC）がそれ以下であれば黒字になる
- **リピート施策の効果測定に使える**: メルマガやLINE施策の投資対効果をLTVの変化で評価できる
- **チャネルごとの品質が見える**: SNS経由とリスティング経由でLTVに差があるなら、予算配分を見直す根拠になる

:::message
LTVの計算方法には複数のアプローチがあります。この記事ではEC事業者が実務で使いやすい「平均購入単価 × 平均購入回数 × 平均継続期間」のシンプルな式と、コホート分析ベースの方法を紹介します。
:::

---

## 前提: GA4 → BigQueryエクスポートの設定

LTV分析を行うには、GA4のデータがBigQueryに入っている必要があります。まだ設定していない場合は、以下の手順で有効化してください。

1. GA4の管理画面 → **管理** → **BigQueryのリンク** を開く
2. Google Cloudプロジェクトを選択し、データセットのロケーションを設定
3. エクスポートタイプは**毎日**を選択（ストリーミングは無料枠を超えやすいため注意）

:::message alert
BigQueryエクスポートを有効にした時点からデータが蓄積されます。過去データの遡及はできないため、まだ設定していない場合は早めに有効化することをおすすめします。
:::

エクスポートが完了すると、BigQuery上に `analytics_<プロパティID>.events_*` というテーブルが日次で作成されます。

---

## SQL Template 1: ユーザーごとの平均購入単価

まずは `purchase` イベントから、ユーザーごとの購入金額を集計します。

```sql
-- ユーザーごとの平均購入単価
SELECT
  user_pseudo_id,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  AVG(ecommerce.purchase_revenue) AS avg_purchase_value
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260329'
GROUP BY
  user_pseudo_id
ORDER BY
  total_revenue DESC
```

:::message
`_TABLE_SUFFIX` の範囲は分析対象期間に合わせて変更してください。期間が長すぎるとクエリのスキャン量が増えるため、まずは直近6ヶ月〜1年で試すのがおすすめです。
:::

---

## SQL Template 2: コホート月別のリピート率（購入頻度）

ユーザーの初回購入月でグルーピングし、月別の購入回数を集計します。

```sql
-- コホート月別の購入頻度
WITH user_first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_month
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
monthly_purchases AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    COUNT(*) AS purchases_in_month
  FROM
    `your-project.analytics_XXXXXXXXX.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  fp.first_purchase_month AS cohort_month,
  COUNT(DISTINCT fp.user_pseudo_id) AS cohort_size,
  AVG(mp.purchases_in_month) AS avg_monthly_purchases,
  COUNT(DISTINCT CASE
    WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
  END) AS repeat_users,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
    END) / COUNT(DISTINCT fp.user_pseudo_id), 3
  ) AS repeat_rate
FROM
  user_first_purchase fp
LEFT JOIN
  monthly_purchases mp ON fp.user_pseudo_id = mp.user_pseudo_id
GROUP BY
  cohort_month
ORDER BY
  cohort_month
```

このクエリで、初回購入月ごとのコホートサイズとリピート率が分かります。リピート率が低い月があれば、その時期の施策や流入チャネルを掘り下げる手がかりになります。

---

## SQL Template 3: シンプルLTV計算

全体の平均値からLTVの概算を出します。

```sql
-- シンプルLTV = 平均購入単価 × 平均購入回数 × 平均継続期間（年）
WITH user_metrics AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    AVG(ecommerce.purchase_revenue) AS avg_purchase_value,
    DATE_DIFF(
      MAX(DATE(TIMESTAMP_MICROS(event_timestamp))),
      MIN(DATE(TIMESTAMP_MICROS(event_timestamp))),
      DAY
    ) / 365.0 AS lifespan_years
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
  HAVING
    COUNT(*) >= 2  -- リピーターのみ対象
)
SELECT
  COUNT(*) AS user_count,
  ROUND(AVG(avg_purchase_value), 0) AS avg_purchase_value,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_frequency,
  ROUND(AVG(lifespan_years), 2) AS avg_lifespan_years,
  ROUND(
    AVG(avg_purchase_value) * AVG(purchase_count) * AVG(lifespan_years), 0
  ) AS estimated_ltv
FROM
  user_metrics
```

:::message alert
このシンプルLTVはあくまで概算です。データの蓄積期間が短い場合、継続期間（lifespan）が過小評価されるため、実際のLTVはこの数値より高くなる可能性があります。
:::

---

## SQL Template 4: コホート別LTV（月次リテンション）

より精度の高い分析として、コホート別に月次のリテンションと累積売上を追跡します。

```sql
-- コホート別月次リテンション＆累積LTV
WITH user_cohort AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS cohort_month
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
purchase_data AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    SUM(e.ecommerce.purchase_revenue) AS revenue
  FROM
    `your-project.analytics_XXXXXXXXX.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  uc.cohort_month,
  DATE_DIFF(
    PARSE_DATE('%Y-%m', pd.purchase_month),
    PARSE_DATE('%Y-%m', uc.cohort_month),
    MONTH
  ) AS months_since_first_purchase,
  COUNT(DISTINCT uc.user_pseudo_id) AS active_users,
  (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month) AS cohort_size,
  ROUND(SUM(pd.revenue), 0) AS monthly_revenue,
  ROUND(SUM(pd.revenue) / (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month), 0) AS revenue_per_cohort_user
FROM
  user_cohort uc
INNER JOIN
  purchase_data pd ON uc.user_pseudo_id = pd.user_pseudo_id
GROUP BY
  uc.cohort_month, months_since_first_purchase, cohort_size
ORDER BY
  uc.cohort_month, months_since_first_purchase
```

この結果をスプレッドシートやLooker Studioで可視化すると、**コホートごとにLTVがどう推移しているか**を把握できます。特定の月に獲得した顧客のLTVが高い場合、その時期のキャンペーンや流入チャネルを再現する判断材料になります。

---

## LTVを意思決定に活用する: LTV:CAC比率

LTVの数値が出たら、次はチャネルごとの新規獲得コスト（CAC）と比較します。GA4のBigQueryデータから流入チャネル別のLTVを算出する例を示します。

```sql
-- 流入チャネル別LTV（初回セッションのチャネルで分類）
WITH user_first_session AS (
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_medium AS first_medium,
    collected_traffic_source.manual_source AS first_source,
    MIN(event_timestamp) AS first_event_timestamp
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    collected_traffic_source.manual_medium,
    collected_traffic_source.manual_source
),
user_revenue AS (
  SELECT
    user_pseudo_id,
    SUM(ecommerce.purchase_revenue) AS total_revenue,
    COUNT(*) AS purchase_count
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
)
SELECT
  fs.first_medium,
  fs.first_source,
  COUNT(DISTINCT ur.user_pseudo_id) AS paying_users,
  ROUND(AVG(ur.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(ur.purchase_count), 1) AS avg_purchase_count
FROM
  user_first_session fs
INNER JOIN
  user_revenue ur ON fs.user_pseudo_id = ur.user_pseudo_id
GROUP BY
  fs.first_medium, fs.first_source
HAVING
  COUNT(DISTINCT ur.user_pseudo_id) >= 10  -- サンプル数が少なすぎるチャネルを除外
ORDER BY
  avg_ltv DESC
```

**LTV:CAC比率の目安:**

| LTV:CAC | 判断 |
|---------|------|
| 3:1以上 | 健全。積極的に投資を拡大できる |
| 1:1〜3:1 | 利益率次第。改善余地あり |
| 1:1未満 | 赤字チャネル。見直しが必要 |

:::message
CACはGA4のデータだけでは取得できません。広告管理画面の費用データと突合する必要があります。Google広告であればBigQueryへのデータ転送が可能です。
:::

---

## 制限事項と次のステップ

この方法には以下の制限があります。

- **`user_pseudo_id` はデバイス単位の識別子**であり、同一ユーザーが複数デバイスを使う場合は別ユーザーとしてカウントされます。より正確な分析にはUser-IDの導入が必要です
- **BigQueryエクスポート開始前のデータは存在しない**ため、十分なデータが溜まるまで数ヶ月の待機期間が必要です
- **返品・キャンセルの処理**はGA4のpurchaseイベントには含まれないため、基幹システムのデータと組み合わせる方が正確です
- **予測LTV**（将来の購入を統計モデルで予測）は本記事の範囲外です。BG/NBDモデルなどを使う場合はPythonとの連携が必要になります

次のステップとして検討できること:

1. **Looker Studioでダッシュボード化** → 定期的にLTVの推移を確認する仕組みを作る
2. **セグメント別LTV分析** → 商品カテゴリ別、地域別などでLTVを比較する
3. **GA4のUser-ID機能を有効化** → クロスデバイスの精度を上げる

---

## まとめ

GA4×BigQueryの無料枠を活用すれば、中小ECでもLTV分析の基盤を構築できます。

- まずはシンプルLTV（Template 3）で全体像を把握する
- コホート分析（Template 4）でリピート傾向の変化を追う
- チャネル別LTVとCACを比較して、広告予算の配分を最適化する

LTVの数値が見えるようになると、「なんとなく広告を出している」状態から、**データに基づいた投資判断**ができるようになります。

GA4やBigQueryの初期設定、LTV分析の構築でお困りの方は、以下のサービスで個別にサポートしています。

https://coconala.com/services/1791205
