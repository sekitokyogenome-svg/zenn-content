---
title: "GA4×BigQueryでモバイルとPCの購買行動の違いを分析した"
emoji: "📱"
type: "idea"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「うちのECサイト、モバイルのアクセスは8割なのに、購入はPCが多い」――こういう話は、EC運営者同士の会話でよく出てきます。

自分が担当していた某美容系ECでも、セッションの75%がモバイルなのに、売上の55%はPCから発生していました。モバイルとPCでは、ユーザーの行動パターンがまったく違うんです。

GA4の標準レポートでもデバイス別の数値は確認できますが、ファネルの各ステップごとの離脱率や、デバイスをまたいだ行動の把握はBigQueryでの分析が有効です。本記事では、デバイス別の購買行動の違いを可視化するSQLと、分析から得られたインサイトを紹介します。

---

## デバイス別の基本指標を比較する

まずは、デバイス別のセッション数・CV数・CVRを出します。

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchases AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  s.device_category,
  COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.user_pseudo_id = p.user_pseudo_id
  AND s.ga_session_id = p.ga_session_id
GROUP BY s.device_category
ORDER BY sessions DESC;
```

某美容系ECでの結果がこちらです。

| デバイス | セッション数 | 購入セッション | CVR |
|---------|------------|-------------|-----|
| mobile | 18,400 | 245 | 1.33% |
| desktop | 5,200 | 198 | 3.81% |
| tablet | 1,100 | 22 | 2.00% |

モバイルのCVRはPCの約3分の1。アクセスの母数は多いのに、購入に至る率が低いことがはっきり見えます。

---

## デバイス別ファネル分析

どのステップで離脱が起きているかを把握するため、ファネル（商品閲覧→カート追加→購入開始→購入完了）をデバイス別に比較します。

```sql
WITH funnel_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  device_category,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS view_item,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS add_to_cart,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS begin_checkout,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS purchase
FROM funnel_events
GROUP BY device_category
ORDER BY view_item DESC;
```

結果をファネルの転換率で整理すると、モバイルとPCの差が鮮明になります。

### モバイル

| ステップ | セッション数 | 転換率 |
|---------|------------|--------|
| view_item | 12,800 | ― |
| add_to_cart | 1,920 | 15.0% |
| begin_checkout | 640 | 33.3% |
| purchase | 245 | 38.3% |

### PC

| ステップ | セッション数 | 転換率 |
|---------|------------|--------|
| view_item | 4,200 | ― |
| add_to_cart | 840 | 20.0% |
| begin_checkout | 420 | 50.0% |
| purchase | 198 | 47.1% |

モバイルとPCの差が出るのは、`add_to_cart → begin_checkout`（カート追加→購入開始）の転換率です。モバイルは33.3%に対してPCは50.0%。モバイルではカートに入れた後に「あとで買おう」となりやすいことが数値で裏付けられます。

---

## モバイルの離脱ポイントを深掘りする

カート追加後に離脱するモバイルユーザーが「どのタイミングで戻ってくるか」を分析します。

```sql
WITH cart_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS cart_time
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'add_to_cart'
    AND device.category = 'mobile'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
),
purchase_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS purchase_time
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN p.user_pseudo_id IS NULL THEN '未購入'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 1 THEN '1時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 24 THEN '24時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 168 THEN '1週間以内'
    ELSE '1週間以上'
  END AS purchase_timing,
  COUNT(*) AS user_count
FROM cart_users c
LEFT JOIN purchase_users p
  ON c.user_pseudo_id = p.user_pseudo_id
GROUP BY purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '1時間以内' THEN 1
    WHEN '24時間以内' THEN 2
    WHEN '1週間以内' THEN 3
    WHEN '1週間以上' THEN 4
    WHEN '未購入' THEN 5
  END;
```

某ECでの結果は以下の通りでした。

| 購入タイミング | ユーザー数 | 割合 |
|--------------|-----------|------|
| 1時間以内 | 180 | 12.5% |
| 24時間以内 | 95 | 6.6% |
| 1週間以内 | 60 | 4.2% |
| 1週間以上 | 25 | 1.7% |
| 未購入 | 1,080 | 75.0% |

モバイルでカート追加した人の75%が購入に至っていません。一方で、24時間以内に購入する層が約19%いることから、カート追加直後のリマインド施策が有効であることが示唆されます。

---

## クロスデバイスの考慮

GA4は `user_pseudo_id` がデバイスごとに異なるため、同じユーザーがモバイルでカートに追加し、PCで購入した場合、正確に追跡するのは難しいという制約があります。

ただし、Googleシグナルを有効にしている場合や、ログイン機能のあるECサイトであれば `user_id` を使ったクロスデバイス分析が可能です。

```sql
-- user_idが設定されている場合のクロスデバイス分析
WITH cross_device AS (
  SELECT
    user_id,
    device.category AS device_category,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name IN ('add_to_cart', 'purchase')
    AND user_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  cart.user_id,
  cart.device_category AS cart_device,
  purchase.device_category AS purchase_device
FROM (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'add_to_cart'
) cart
JOIN (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'purchase'
) purchase
  ON cart.user_id = purchase.user_id
WHERE cart.device_category != purchase.device_category;
```

:::message
`user_id` が設定されていないサイトでは、クロスデバイスの正確な計測は難しくなります。会員登録・ログイン機能がある場合は、GA4の `user_id` 設定を優先的に実装することをおすすめします。
:::

---

## 分析から得られた改善施策

デバイス別の分析結果をもとに、某ECで実施した施策は以下の3つです。

1. **モバイルのカート追加後リマインドメール**: カート追加から1時間後・24時間後にリマインドメールを自動配信
2. **モバイルの決済フロー簡略化**: 入力フォームのステップ数を5→3に削減、Apple Pay/Google Payの導入
3. **PCへの誘導メッセージ**: モバイルでカート追加した際に「PCからの購入もスムーズです」のメッセージを表示

---

## まとめ

モバイルとPCの購買行動は、同じECサイトでもかなり異なります。「モバイルのアクセスが多い」だけでは語れない、ファネルの各ステップでの転換率やカート追加後の行動パターンを、BigQueryで可視化することで改善の打ち手が見えてきます。

自分としては、モバイルのCVRが低いことを「モバイルは買いにくいから仕方ない」と片付けるのはもったいないと感じています。ファネルのどこで詰まっているかがわかれば、改善の優先度が明確になるので。

皆さんのECサイトでは、デバイス別のファネル分析はどこまで見えていますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
