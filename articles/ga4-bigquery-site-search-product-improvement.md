---
title: "ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した"
emoji: "🔍"
type: "idea"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

ECサイトの検索窓に入力されるキーワードは、ユーザーが「今ほしいもの」を直接教えてくれるデータです。しかし、このデータを体系的に分析できている事業者はどれくらいいるでしょうか。

サイト内検索のキーワードを分析すると、「ユーザーが求めているのに自社サイトにない商品」が見えてきます。検索されたのに購入に至らなかったキーワードは、品揃え改善のヒントになります。

この記事では、GA4の `view_search_results` イベントをBigQueryで分析し、検索キーワードから品揃え改善につなげる方法を解説します。

---

## GA4のサイト内検索データの仕組み

GA4では、サイト内検索が行われると `view_search_results` イベントが発火します。検索キーワードは `event_params` の `search_term` パラメータに格納されます。

| 項目 | 値 |
|------|-----|
| イベント名 | `view_search_results` |
| キーワード格納先 | `event_params.search_term` |
| 前提条件 | GA4の拡張計測機能でサイト内検索が有効化されていること |

:::message
拡張計測機能の「サイト内検索」が無効になっている場合、`view_search_results` イベントは記録されません。GA4の管理画面で有効化されているか確認してください。
:::

---

## 検索キーワードのランキングを取得する

まず、検索キーワードの出現頻度を集計します。

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'view_search_results'
GROUP BY search_term
HAVING search_term IS NOT NULL
ORDER BY search_count DESC
LIMIT 50
```

検索回数の多いキーワードは、ユーザーの需要が高いことを示しています。上位キーワードの商品が充実しているかどうかを確認することが、品揃え改善の第一歩です。

---

## 検索キーワードごとの購入転換率を算出する

検索されたキーワードのうち、どれが購入に結びついているかを分析します。

```sql
WITH search_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

purchase_sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ss.search_term,
  COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) AS search_sessions,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING))) AS purchase_sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING)))
    / COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) * 100,
    2
  ) AS search_to_purchase_rate
FROM search_sessions ss
LEFT JOIN purchase_sessions ps
  ON ss.user_pseudo_id = ps.user_pseudo_id
  AND ss.session_id = ps.session_id
WHERE ss.search_term IS NOT NULL
GROUP BY ss.search_term
HAVING search_sessions >= 5
ORDER BY search_sessions DESC
```

結果のイメージは以下の通りです。

| search_term | search_sessions | purchase_sessions | search_to_purchase_rate |
|-------------|----------------|-------------------|------------------------|
| ギフトセット | 89 | 12 | 13.48 |
| 限定 | 65 | 8 | 12.31 |
| セール | 124 | 5 | 4.03 |
| オーガニック 化粧水 | 42 | 0 | 0.00 |
| メンズ スキンケア | 38 | 0 | 0.00 |

---

## 結果の読み方

### 検索回数が多く購入率が高いキーワード

このカテゴリのキーワードは、需要と供給のマッチングがうまくいっている領域です。在庫切れを防ぎ、関連商品のバリエーションを増やす方向で強化します。

### 検索回数が多いが購入率が0%のキーワード

ここが品揃え改善の最大のチャンスです。ユーザーが求めているのに、該当する商品がないか、検索結果に表示されていない可能性があります。

対処方法は2つあります。

1. **該当商品を追加する** — 需要があるのに商品がないケース
2. **検索結果のマッチングを改善する** — 商品はあるが検索にヒットしないケース（同義語辞書の整備など）

### 検索回数が少ないが購入率が高いキーワード

ニッチだが購入意欲の高いセグメントです。このキーワードでのSEO対策やリスティング広告の出稿を検討する価値があります。

---

## 検索後の行動を詳細に追う

検索後にユーザーがどのような行動をとっているかを分析すると、検索体験の改善ポイントが見えてきます。

```sql
WITH search_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
    event_timestamp AS search_timestamp
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

post_search_actions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    e.event_timestamp
  FROM `beeracle.analytics_263425816.events_*` e
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)

SELECT
  se.search_term,
  COUNT(DISTINCT se.user_pseudo_id) AS searchers,
  -- 検索後に商品詳細を見た割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'view_item', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS view_item_rate,
  -- 検索後にカート追加した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'add_to_cart', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS add_to_cart_rate,
  -- 検索後に購入した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'purchase', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS purchase_rate
FROM search_events se
LEFT JOIN post_search_actions psa
  ON se.user_pseudo_id = psa.user_pseudo_id
  AND se.session_id = psa.session_id
  AND psa.event_timestamp > se.search_timestamp
WHERE se.search_term IS NOT NULL
GROUP BY se.search_term
HAVING searchers >= 10
ORDER BY searchers DESC
LIMIT 30
```

検索→商品詳細閲覧の転換率が低いキーワードは、検索結果の表示内容に問題がある可能性を示唆しています。

---

## 実際の品揃え改善事例

ある美容系ECサイトで、サイト内検索のデータを分析したところ以下の傾向が見つかりました。

| 発見 | 対応 | 結果 |
|------|------|------|
| 「メンズ」の検索が月40件あるが商品0 | メンズ向けカテゴリを新設 | 新カテゴリから月15件の購入が発生 |
| 「ギフト」検索後の購入率が高い | ギフトセット商品を3種追加 | ギフト関連の売上が前月比で増加 |
| 「敏感肌」検索後の商品閲覧率が20%と低い | 商品タグに「敏感肌対応」を追加 | 検索→閲覧率が55%に改善 |

サイト内検索データは「ユーザーの声」そのものです。定期的に分析し、品揃えと検索精度の改善に活用することで、売上向上につなげられます。

---

## まとめ

- GA4の `view_search_results` イベントから、ユーザーが求めている商品を把握できる
- 検索キーワードごとの購入転換率を分析すれば、品揃えの過不足が見える
- 検索回数が多く購入率が0%のキーワードは、品揃え改善の優先候補になる

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
