---
title: "ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する"
emoji: "📊"
type: "tech"
topics: ["bigquery","googleanalytics","ec","sql","datanalysis"]
published: false
---

## はじめに

「先月、送料を値上げしたら購入率が下がった気がする。でも、本当に価格のせいなのか、季節性のせいなのか、判断しきれない」——そんな経験はありませんか。

ECサイトを運営していると、価格や送料の変更が避けられない場面が出てきます。しかしその変更が売上やCVR（コンバージョン率）にどの程度影響したかを正確に把握するのは難しく、「感覚」で判断してしまっているケースが多いのではないでしょうか。

単純に「変更前後の数字を比べる」だけでは、同時期に起きた外部要因（広告配信の変化、競合の動向、季節波動など）の影響が混入してしまいます。そこで役立つのが**因果推論**という考え方です。本記事では、GA4のBigQueryエクスポートデータを活用して、価格変更の純粋な効果を推定する方法を、SQLを交えて解説します。

---

## 因果推論の基本：「差分の差分法（DiD）」とは

因果推論にはさまざまな手法がありますが、ECの価格変更のような「施策前後の比較」に適した手法が**差分の差分法（Difference-in-Differences、DiD）**です。

考え方はシンプルです。価格変更の影響を受けた「処置群」と、変更を受けていない「対照群」を用意し、それぞれの変化量の差を取ります。

- 処置群の変化：価格変更後のCVR − 価格変更前のCVR
- 対照群の変化：同期間の対照商品CVR（変更後）− 対照商品CVR（変更前）
- **推定効果 = 処置群の変化 − 対照群の変化**

対照群として使えるのは「価格を変更しなかった類似商品」や「同カテゴリの他商品」です。これにより、季節変動や広告効果などの共通要因を差し引いて、価格変更そのものの影響を見積もることができます。

:::message
DiDが成立する前提条件として「平行トレンド仮定」があります。これは「もし処置がなければ、処置群と対照群は同じように動いていたはず」という仮定です。変更前の期間で両者のトレンドが似ていることをグラフで確認しておくと、分析の信頼性が高まります。
:::

---

## GA4×BigQueryでデータを準備する

GA4のBigQueryエクスポートを使うと、セッション単位・ユーザー単位の行動ログが取得できます。まず、分析に必要な「商品ページへの到達数」と「購入数」をセッション単位で集計します。

以下のクエリは、GA4のイベントログから商品別・日別のセッション数と購入数を取得するものです。`event_params`はネストされた形式になっているため、`UNNEST`で展開して`ga_session_id`を取り出します。

```sql
-- GA4イベントログからセッション×商品別のCVR集計
WITH base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTで取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    -- 商品IDはevent_paramsのitem_idから取得（purchase/view_itemイベント向け）
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
),

session_level AS (
  SELECT
    event_date,
    item_id,
    CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)) AS session_key,
    MAX(IF(event_name = 'view_item',  1, 0)) AS viewed,
    MAX(IF(event_name = 'purchase',   1, 0)) AS purchased
  FROM base
  WHERE item_id IS NOT NULL
  GROUP BY 1, 2, 3
)

SELECT
  event_date,
  item_id,
  COUNT(*)                    AS sessions,
  SUM(purchased)              AS conversions,
  SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
FROM session_level
WHERE viewed = 1
GROUP BY 1, 2
ORDER BY 1, 2
```

:::message
`collected_traffic_source.manual_medium` / `manual_source` はGA4が標準で持つ流入元フィールドです。`event_params`内の `medium` / `source` とは異なる場合がありますので、ご利用のGA4設定に合わせてご確認ください。
:::

---

## SQLで差分の差分を計算する

上記で集計したデータをもとに、DiDの計算をSQLで実装します。ここでは「商品A（価格変更あり）」と「商品B（価格変更なし）」を対比する例を示します。価格変更日を2025年7月1日と仮定しています。

```sql
-- 差分の差分（DiD）推定クエリ
WITH daily_cvr AS (
  -- 上記クエリの結果をCTEとして再利用するイメージ
  SELECT
    event_date,
    item_id,
    SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
  FROM session_level
  WHERE viewed = 1
  GROUP BY 1, 2
),

grouped AS (
  SELECT
    item_id,
    CASE
      WHEN item_id = 'ITEM_A' THEN 'treated'   -- 価格変更あり
      WHEN item_id = 'ITEM_B' THEN 'control'   -- 価格変更なし
    END AS group_type,
    CASE
      WHEN event_date < '2025-07-01' THEN 'pre'
      ELSE 'post'
    END AS period,
    AVG(cvr) AS avg_cvr
  FROM daily_cvr
  WHERE item_id IN ('ITEM_A', 'ITEM_B')
  GROUP BY 1, 2, 3
),

pivoted AS (
  SELECT
    item_id,
    group_type,
    MAX(IF(period = 'pre',  avg_cvr, NULL)) AS cvr_pre,
    MAX(IF(period = 'post', avg_cvr, NULL)) AS cvr_post
  FROM grouped
  GROUP BY 1, 2
),

diff AS (
  SELECT
    item_id,
    group_type,
    cvr_pre,
    cvr_post,
    cvr_post - cvr_pre AS delta_cvr
  FROM pivoted
)

-- DiD = 処置群のdelta − 対照群のdelta
SELECT
  MAX(IF(group_type = 'treated', delta_cvr, NULL))
    - MAX(IF(group_type = 'control', delta_cvr, NULL)) AS did_estimate,
  MAX(IF(group_type = 'treated', cvr_pre,  NULL)) AS treated_cvr_pre,
  MAX(IF(group_type = 'treated', cvr_post, NULL)) AS treated_cvr_post,
  MAX(IF(group_type = 'control', cvr_pre,  NULL)) AS control_cvr_pre,
  MAX(IF(group_type = 'control', cvr_post, NULL)) AS control_cvr_post
FROM diff
```

`did_estimate` がマイナスであれば、価格変更によってCVRが下がったと推定されます。プラスであれば、価格変更にもかかわらず（あるいは価格変更を機に）CVRが改善したことを意味します。

---

## 売上への影響も合わせて確認する

CVRだけでなく、売上金額への影響も確認することが重要です。CVRが下がっても客単価が上がれば、売上総額はむしろ増える場合があります。以下のクエリで「セッション当たり売上（RPS：Revenue Per Session）」を計算すると、価格弾力性を踏まえた意思決定ができます。

```sql
-- セッション当たり売上（RPS）の集計
WITH revenue_base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    (SELECT value.int_value  FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id')   AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
)

SELECT
  event_date,
  item_id,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  SUM(IF(event_name = 'purchase', revenue, 0))                          AS total_revenue,
  SAFE_DIVIDE(
    SUM(IF(event_name = 'purchase', revenue, 0)),
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)))
  ) AS rps
FROM revenue_base
WHERE item_id IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2
```

このRPSを前述のDiDフレームワークに当てはめることで、「価格変更は売上にプラスだったかマイナスだったか」を数値で示すことができます。

---

## 結果を解釈する際の注意点

因果推論の結果を実務に活かす際には、以下の点に留意してください。

**サンプルサイズの確認**
期間が短い、または対象商品のトラフィックが少ない場合、CVRの変動が統計的なばらつきによるものである可能性があります。セッション数が各期間で数百件以上あるか確認し、少ない場合は期間を延ばして再集計することを検討してください。

**共変量の影響**
広告の配信量、流入経路の構成比（オーガニック vs 有料）、デバイス比率などが前後期間で大きく変わっていないかを確認することが大切です。`collected_traffic_source.manual_medium` を使ってセグメント別に分解し、特定流入元だけでCVRが変動していないかチェックするのも有効です。

**対照群の選定**
対照群に選んだ商品が、処置群と同じカテゴリ・価格帯・ターゲット層であることが理想です。全く異なる商品を対照群にすると、DiDの前提が崩れる可能性があります。

---

## まとめ

本記事では、ECサイトにおける価格変更の影響を因果推論（差分の差分法）でGA4×BigQueryを用いて推定する方法を解説しました。要点を整理します。

- **単純な前後比較では外部要因が混入する**ため、対照群との比較が重要
- **DiD（差分の差分法）**を使うと、価格変更そのものの効果をより正確に推定できる
- GA4のBigQueryエクスポートでは、`ga_session_id`は`UNNEST(event_params)`で取得し、流入元は`collected_traffic_source`を参照する
- CVRと合わせて**RPS（セッション当たり売上）**も見ることで、価格変更の総合的な評価が可能

次のアクションとして、まず自社の対象商品と対照商品を選定し、変更日前後それぞれ4週間分のデータを取得して上記クエリを試してみてください。数字が揃えば、次回の価格改定の判断材料として活用できます。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
