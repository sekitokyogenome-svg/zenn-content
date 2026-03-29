---
title: "BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googleanalytics", "demographics"]
published: false
---

## 「うちの顧客層は30代女性が多いはず」は本当か

EC運営者に「メインの顧客層は？」と聞くと、多くの方が「たぶん30代女性」「40代男性が中心だと思う」と答えます。しかし、その根拠はGA4のレポート画面に表示されるデモグラフィックデータであることが大半です。

GA4のデモグラフィックデータには、実は大きな制約があります。この記事では、BigQueryに蓄積されたGA4のデモグラフィックデータの精度を検証し、その限界と対策について解説します。

## GA4のデモグラフィックデータの仕組み

GA4が提供する年齢・性別データは、Googleシグナル（Google アカウントに紐づく広告パーソナライズ設定）から推定されたデータです。ユーザーが直接申告した情報ではありません。

重要な制約は以下の通りです。

- Googleアカウントにログインしているユーザーのみが対象
- 広告パーソナライズを有効にしているユーザーのみ
- しきい値が適用され、少数のユーザーグループはデータが非表示になる
- 推定精度はGoogleが公開していない

## Step 1: デモグラフィックデータのカバレッジを確認する

まず、GA4のBigQueryエクスポートデータで、デモグラフィック情報がどの程度取得できているかを確認します。

```sql
WITH user_demographics AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
)
SELECT
  COUNT(*) AS total_users,
  COUNTIF(age_bracket IS NOT NULL) AS users_with_age,
  COUNTIF(gender IS NOT NULL) AS users_with_gender,
  ROUND(COUNTIF(age_bracket IS NOT NULL) / COUNT(*) * 100, 1) AS age_coverage_pct,
  ROUND(COUNTIF(gender IS NOT NULL) / COUNT(*) * 100, 1) AS gender_coverage_pct
FROM user_demographics
```

多くのサイトでは、このカバレッジが30〜50%程度にとどまります。つまり、半数以上のユーザーについてはデモグラフィック情報が取得できていないということです。

## Step 2: デモグラフィック別のセグメント分析

取得できているデータの範囲内で、年齢・性別の分布を確認します。

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
)
SELECT
  age_bracket,
  gender,
  COUNT(*) AS user_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct
FROM user_demo
WHERE age_bracket IS NOT NULL
  AND gender IS NOT NULL
GROUP BY age_bracket, gender
ORDER BY user_count DESC
```

## Step 3: デモグラフィック別の購買行動比較

デモグラフィックデータが取れているユーザーと取れていないユーザーで、購買行動に違いがあるかを検証します。

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
user_purchases AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN ud.age_bracket IS NOT NULL THEN 'デモグラ取得済み'
    ELSE 'デモグラ未取得'
  END AS demo_status,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.purchase_count), 2) AS avg_purchases,
  ROUND(AVG(up.total_revenue), 0) AS avg_revenue
FROM user_purchases up
LEFT JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
GROUP BY demo_status
```

この結果に大きな差がある場合、デモグラフィックデータの取得有無自体がバイアスを持っている可能性があります。Googleアカウントにログインしている層は、一般的にデジタルリテラシーが高く、行動パターンが異なることが多いためです。

## Step 4: 年齢層別の購入単価・頻度分析

デモグラフィック情報が取れているユーザーに限定して、年齢層ごとの購買傾向を分析します。

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
user_purchases AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  ud.age_bracket,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(up.purchase_count), 2) AS avg_frequency,
  ROUND(AVG(up.total_revenue / up.purchase_count), 0) AS avg_order_value
FROM user_purchases up
INNER JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
WHERE ud.age_bracket IS NOT NULL
GROUP BY ud.age_bracket
ORDER BY avg_ltv DESC
```

## GA4デモグラフィックデータの限界

検証を通じて明らかになるGA4のデモグラフィックデータの限界をまとめます。

**カバレッジの問題**
全ユーザーの30〜50%程度しかデータが取得できない場合が多く、残りのユーザーについては推測に頼ることになります。

**バイアスの問題**
デモグラフィックが取得できるユーザー層（Googleアカウントログイン＋広告パーソナライズON）と取得できない層で、行動パターンが異なる可能性が高いです。

**精度の問題**
Googleが推定したデータであり、ユーザーが直接申告した情報ではありません。年齢は「18-24」「25-34」のようなブラケット単位であり、詳細な年齢は取得できません。

## 対策: より精度の高いデモグラフィック取得方法

GA4の推定データだけに頼らず、以下の方法を組み合わせることで精度を向上させられます。

**1. 会員登録時のプロフィール情報**

ECサイトの会員登録フォームで年齢・性別を取得し、CRMデータとしてBigQueryに取り込みます。GA4の`user_id`と突合することで、GA4の行動データと会員属性を統合できます。

**2. 購入商品からの推定**

商品カテゴリの傾向から顧客層を推定する方法です。例えば、レディースアパレルの購入者は女性である可能性が高いといった推定が可能です。

**3. アンケート施策との連携**

購入後アンケートや定期的なNPSサーベイで属性情報を収集し、BigQueryに蓄積する方法です。回答率は低いですが、得られるデータの精度は高いです。

## BigQueryでCRMデータと統合するSQL例

会員データをBigQueryに取り込んでいる場合の統合クエリ例です。

```sql
SELECT
  ga.user_pseudo_id,
  crm.age,
  crm.gender,
  crm.prefecture,
  COUNT(DISTINCT CASE WHEN ga.event_name = 'purchase' THEN ga.event_bundle_sequence_id END) AS purchases,
  SUM(CASE WHEN ga.event_name = 'purchase' THEN ga.ecommerce.purchase_revenue END) AS total_revenue
FROM
  `beeracle.analytics_263425816.events_*` ga
INNER JOIN
  `beeracle.crm.members` crm
  ON ga.user_id = crm.user_id
WHERE
  ga._TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  ga.user_pseudo_id, crm.age, crm.gender, crm.prefecture
```

## まとめ

GA4のデモグラフィックデータは手軽に確認できる反面、カバレッジ・バイアス・精度の3つの課題を抱えています。「うちの顧客は30代女性が多い」という認識が、実際にはGoogleアカウントにログインしている層の偏った断面を見ているだけかもしれません。

正確な顧客理解には、GA4だけに依存せず、CRMデータやアンケートデータとの統合が有効です。まずはBigQueryで自社データのデモグラフィックカバレッジを確認するところから始めてみてください。

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
