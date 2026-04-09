---
title: "EC売上が下がったとき最初に確認すべきBigQueryクエリ5選"
emoji: "📉"
type: "tech"
topics: ["bigquery", "googleanalytics", "ec"]
published: false
---

## はじめに

「先月と比べて売上が下がっている気がする」「GA4の管理画面を見ても、何が原因かわからない」――EC運営でこうした状況に直面したとき、どこから手をつければいいか迷う方は多いのではないでしょうか。

GA4の標準レポートだけでは、売上低下の原因を特定するには情報が足りません。BigQueryにエクスポートしたGA4生データを使えば、チャネル別・デバイス別・ページ別・ファネル段階別に分解して、ボトルネックを素早く見つけることができます。

本記事では、EC売上が下がったときに**最初に実行すべきBigQueryクエリ5つ**を紹介します。すべてGA4のBigQueryエクスポートテーブル（`analytics_XXXXXX.events_*`）を対象としたSQLです。

:::message
前提として、GA4のBigQueryエクスポートが設定済みであることが必要です。まだの方は先にエクスポート設定を完了してください。
:::

---

## クエリ1：日別売上推移（いつから下がったかを特定する）

まず最初にやるべきは、日別の売上推移を可視化して「いつから下がり始めたか」を特定することです。

```sql
SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ecommerce.transaction_id END) AS transactions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
GROUP BY
  event_date
ORDER BY
  event_date
```

このクエリで日別のセッション数・トランザクション数・売上を一覧できます。売上が落ち始めた日付がわかれば、その前後で何が変わったかを調べる起点になります。

:::message alert
`_TABLE_SUFFIX`の日付範囲は、比較したい期間に合わせて調整してください。直近30日 vs 前月同期間で比較するのが基本です。
:::

---

## クエリ2：チャネル別売上比較（どのチャネルが落ちたか）

日別推移で下落時期がわかったら、次はチャネル別に分解します。Organic Search・Paid Search・Direct・Referralなど、どの流入チャネルで売上が落ちたのかを確認します。

```sql
WITH period_data AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    user_pseudo_id,
    event_name,
    ecommerce.purchase_revenue,
    ecommerce.transaction_id
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
)
SELECT
  period,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS transactions,
  SUM(CASE WHEN event_name = 'purchase' THEN purchase_revenue END) AS revenue
FROM
  period_data
WHERE
  period IS NOT NULL
GROUP BY
  period, medium
ORDER BY
  period, revenue DESC
```

`collected_traffic_source.manual_medium`を使うことで、utm_mediumベースのチャネル分類が可能です。特定のチャネルだけが大きく落ちていれば、そのチャネルに絞った調査に進めます。

---

## クエリ3：デバイス別CVR比較（モバイル vs デスクトップ）

チャネル全体ではなくデバイス種別でCVR（コンバージョン率）が変化していることもあります。特にモバイルのCVR低下はサイト表示速度やUI変更の影響を示唆します。

```sql
WITH sessions AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    device.category AS device,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
  GROUP BY
    period, device, session_id
)
SELECT
  period,
  device,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS converting_sessions,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_percent
FROM
  sessions
WHERE
  period IS NOT NULL
GROUP BY
  period, device
ORDER BY
  period, device
```

前月と当月でデバイス別のCVRを比較し、モバイルだけCVRが下がっていれば、モバイル固有の問題（ページ速度の悪化、UIの崩れ、決済フローの不具合など）を疑います。

---

## クエリ4：主要ランディングページの流入比較（どのページでトラフィックが減ったか）

売上低下の原因がトラフィック減少にある場合、どのランディングページへの流入が減ったかを特定します。

```sql
WITH landing_pages AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name = 'session_start'
)
SELECT
  period,
  REGEXP_EXTRACT(page_location, r'https?://[^/]+(/.*)') AS landing_path,
  COUNT(DISTINCT session_id) AS sessions
FROM
  landing_pages
WHERE
  period IS NOT NULL
GROUP BY
  period, landing_path
HAVING
  sessions >= 10
ORDER BY
  period, sessions DESC
LIMIT 50
```

特定のページへの流入が大きく減っていれば、SEO順位の低下・広告出稿の停止・外部リンクの変化などが考えられます。逆に新しいページが流入を奪っていないかも確認しましょう。

---

## クエリ5：ファネルステップ比較（どの段階で離脱が増えたか）

トラフィックもチャネルも大きく変わっていないのに売上が下がっている場合、購買ファネルのどこかで離脱が増えている可能性があります。`view_item` → `add_to_cart` → `purchase` の各ステップの通過数を比較します。

```sql
WITH funnel AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)
SELECT
  period,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END) AS view_item_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END) AS add_to_cart_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout' THEN session_id END) AS begin_checkout_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END) AS purchase_sessions,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END)
  ) * 100, 2) AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END)
  ) * 100, 2) AS cart_to_purchase_rate
FROM
  funnel
WHERE
  period IS NOT NULL
GROUP BY
  period
ORDER BY
  period
```

各ステップの転換率を前月と比較することで、ボトルネックの位置が明確になります。

- **view_item → add_to_cart が低下**: 商品ページの訴求力低下、価格変更、在庫切れなどの可能性
- **add_to_cart → purchase が低下**: カートページや決済フローの問題、送料・手数料の変更、決済エラーなどの可能性

:::message
`begin_checkout`イベントが計測されていない場合は、`add_to_cart` → `purchase`の2ステップで比較してください。
:::

---

## 結果の読み解き方と仮説の立て方

5つのクエリを実行したら、結果を組み合わせて仮説を立てます。

| 発見パターン | 仮説の例 |
|---|---|
| 特定チャネルだけ売上減少 | 広告の停止・SEO順位変動・外部メディア掲載の終了 |
| モバイルだけCVR低下 | サイト速度悪化・UI変更・決済フォームの不具合 |
| 特定ページの流入減少 | 検索順位低下・被リンク喪失・ページの404化 |
| ファネル途中の転換率低下 | UX変更・価格改定・在庫切れ・決済エラー |
| 全体的に均等な低下 | 季節要因・市場トレンド・競合の影響 |

重要なのは、クエリ結果はあくまで「事実」であり、それ自体が原因ではないということです。データから仮説を立て、サイトの変更履歴やGoogleサーチコンソールなどの他データソースと突き合わせて、真の原因を特定するプロセスが必要です。

---

## 定期チェックをルーティン化する

売上が下がってから慌てて調査するのではなく、これらのクエリを**定期的に実行する仕組み**にしておくと、異変を早期に検知できます。

具体的なアプローチとしては以下が挙げられます。

- **BigQueryのスケジュールクエリ**で日次・週次に自動実行し、結果をテーブルに保存する
- **Looker Studio**でダッシュボード化し、毎朝確認する習慣をつける
- 閾値を設定して、前週比で大きく下がった場合に**アラート通知**を飛ばす

「異常に気づくのが1日遅れるだけで、損失は数十万円に膨らむ」というECの世界では、こうしたモニタリング基盤の構築が売上を守る第一歩になります。

---

## まとめ

EC売上が下がったとき、闇雲にサイトをいじる前にまずデータで事実を確認することが重要です。本記事で紹介した5つのクエリを順に実行すれば、以下の観点から原因の切り分けが可能です。

1. **いつから**下がったか（日別推移）
2. **どのチャネル**が落ちたか（チャネル別比較）
3. **どのデバイス**で問題が起きているか（デバイス別CVR）
4. **どのページ**でトラフィックが減ったか（LP別比較）
5. **どのファネル段階**で離脱が増えたか（ファネル比較）

BigQueryとGA4のデータを活用すれば、感覚ではなくデータに基づいた意思決定ができるようになります。

「GA4のデータはあるけど、BigQueryでの分析環境が整っていない」「自社でクエリを書くリソースがない」という方は、GA4×BigQuery基盤構築のサポートも行っています。お気軽にご相談ください。

https://coconala.com/services/1791205
