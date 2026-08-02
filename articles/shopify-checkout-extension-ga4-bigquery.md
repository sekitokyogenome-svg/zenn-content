---
title: "Shopifyのチェックアウト拡張機能のイベントをGA4×BigQueryで分析する"
emoji: "🛒"
type: "tech"
topics: ["shopify","googleanalytics","bigquery","ec","javascript"]
published: false
---

## はじめに

Shopifyでストアを運営していると、「カートに入れたのに購入されない」「チェックアウトのどのステップで離脱しているのか」といった疑問を抱えることはないでしょうか。標準のShopifyレポートやGA4のデフォルト計測では、チェックアウトフロー内部の詳細な動線を把握するのが難しいケースがあります。

そこで注目されるのが、**Shopifyのチェックアウト拡張機能（Checkout Extensions）** です。これはShopify Plusをはじめとするプランで利用できる機能で、チェックアウト画面のUI拡張だけでなく、ユーザーの行動イベントをカスタムで送信することが可能です。このイベントデータをGA4に連携し、さらにBigQueryへエクスポートすることで、高精度な購買行動の分析基盤を構築できます。

本記事では、Shopifyのチェックアウト拡張機能で発生するカスタムイベントをGA4に送信し、BigQueryで分析するまでの流れを解説します。ECサイトの改善施策を検討されているご担当者様や、計測環境の整備を進めたいWebコンサルタントの方を想定した内容です。コードサンプルも掲載しますが、技術的な背景知識がなくても全体の流れを把握いただけるよう、概念の説明も丁寧に盛り込んでいます。

---

## チェックアウト拡張機能でカスタムイベントを送信する

Shopify Checkout Extensionsは、`@shopify/ui-extensions`パッケージが提供するAPIを通じて、チェックアウト画面の各ステップで任意のイベントを発火させることができます。GA4へのデータ送信には、`gtag`関数を呼び出す方法が一般的です。

以下は、チェックアウトの「配送情報入力」ステップでイベントを送信するサンプルコードです。

```javascript
import { useEffect } from "@shopify/ui-extensions-react/checkout";
import { extension } from "@shopify/ui-extensions/checkout";

extension("Checkout::DeliveryAddress::RenderBefore", (root, api) => {
  // チェックアウト画面に到達したタイミングでGA4イベントを送信
  if (typeof window !== "undefined" && typeof window.gtag === "function") {
    window.gtag("event", "checkout_step_reached", {
      checkout_step: "delivery_address",
      currency: "JPY",
    });
  }
});
```

ここで注意が必要なのは、Shopifyのチェックアウトページはサードパーティスクリプトの実行に制限があるという点です。`gtag`の呼び出しが可能かどうかは、ストアの設定やShopifyのバージョン（Hydrogen / 通常Storefront）によって異なります。まずは開発者ツールのコンソールで`window.gtag`が参照できるか確認してから実装を進めることをお勧めします。

:::message
Shopify Plusプラン未満の場合、チェックアウト拡張機能の一部機能が制限されることがあります。利用可能なAPIは公式ドキュメントで最新情報をご確認ください。
:::

---

## GA4でカスタムイベントを受け取る設定

`gtag`経由で送信したカスタムイベントは、GA4のリアルタイムレポートで確認できます。ただし、BigQueryへのエクスポートを活用するためには、いくつかの設定が必要です。

**1. GA4プロパティでBigQueryリンクを有効にする**

GA4の管理画面から「プロダクトリンク」→「BigQueryリンク」を選択し、GCPプロジェクトと連携します。エクスポート頻度は「毎日」または「ストリーミング」から選択できます。リアルタイム性が重要な場合はストリーミングエクスポートが便利ですが、コストが発生する点に留意が必要です。

**2. カスタムイベントパラメータを登録する**

`checkout_step`のような独自のパラメータは、GA4の「カスタム定義」から「カスタムディメンション」として登録しておく必要があります。登録しておかないとBigQueryのエクスポートデータにパラメータ値が含まれない場合があるため、忘れずに設定しましょう。

**3. BigQueryのテーブル構成を把握する**

GA4からBigQueryにエクスポートされるデータは、`events_YYYYMMDD`という形式のテーブルに格納されます。各行が1イベントに対応しており、イベントパラメータは`event_params`という繰り返しフィールド（RECORD型）に格納されています。

---

## BigQueryでチェックアウトイベントを集計するSQL

BigQueryでGA4のデータを分析する際、最も重要なポイントは「event_paramsの扱い方」です。`ga_session_id`などのパラメータは、直接カラムとして参照することができないため、`UNNEST`関数を使って展開する必要があります。

以下は、チェックアウトの各ステップへの到達数と、セッションの流入元を合わせて集計するSQLの例です。

```sql
WITH base AS (
  SELECT
    event_date,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- チェックアウトステップ（カスタムパラメータ）を取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
)

SELECT
  event_date,
  checkout_step,
  medium,
  source,
  COUNT(DISTINCT ga_session_id) AS sessions,
  COUNT(*) AS event_count
FROM base
GROUP BY
  event_date,
  checkout_step,
  medium,
  source
ORDER BY
  event_date,
  checkout_step;
```

:::message
`your_project.analytics_XXXXXXXXX`の部分は、実際のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。プロパティIDはGA4の管理画面で確認できます。
:::

このSQLを実行することで、「日別・チェックアウトステップ別・流入元別のセッション数」が一覧で取得できます。たとえば、organic検索からの流入セッションが配送情報入力で多く離脱しているといった傾向が見えてくれば、そのステップのUI改善や送料表示の見直しといったアクションにつなげることができます。

---

## ファネル分析でボトルネックを特定する

チェックアウトの各ステップ間の遷移率（ファネル通過率）を見ることで、どのステップで離脱が多いかを特定できます。以下のSQLは、セッションごとに到達したステップを横展開し、ステップ間の遷移を集計する例です。

```sql
WITH step_sessions AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
),

funnel AS (
  SELECT
    COUNTIF(checkout_step = 'delivery_address') AS step1_delivery,
    COUNTIF(checkout_step = 'shipping_method')  AS step2_shipping,
    COUNTIF(checkout_step = 'payment')          AS step3_payment,
    COUNTIF(checkout_step = 'review')           AS step4_review
  FROM (
    SELECT ga_session_id, checkout_step
    FROM step_sessions
    GROUP BY ga_session_id, checkout_step
  )
)

SELECT
  step1_delivery,
  step2_shipping,
  ROUND(step2_shipping / NULLIF(step1_delivery, 0) * 100, 1) AS step1_to_step2_pct,
  step3_payment,
  ROUND(step3_payment / NULLIF(step2_shipping, 0) * 100, 1) AS step2_to_step3_pct,
  step4_review,
  ROUND(step4_review / NULLIF(step3_payment, 0) * 100, 1) AS step3_to_step4_pct
FROM funnel;
```

このような分析を行うことで、「配送方法選択から決済情報入力への遷移率が低い」といった具体的なボトルネックを数値で把握することができます。対策を講じた後に同じSQLで計測し直すことで、改善効果の検証も行えます。

---

## Looker Studioとの連携でレポートを可視化する

BigQueryで集計したデータは、Looker Studio（旧データポータル）と連携することで、グラフや表として視覚的に表示できます。Looker StudioはGoogleのBIツールで、BigQueryをデータソースとして直接接続できるため、SQLの知識がない担当者でも最新のレポートを閲覧できる環境が作れます。

手順は以下の通りです。

1. Looker Studioにログインし、「データソースを作成」からBigQueryを選択する
2. GCPプロジェクト・データセット・テーブル（またはカスタムクエリ）を指定して接続する
3. ディメンションと指標を設定し、棒グラフや折れ線グラフでファネルを表示する

特に「チェックアウトステップ別のセッション数」を棒グラフで並べると、どのステップで人数が大きく減っているかが一目で分かります。週次・月次の定期レポートとして関係者に共有する場合も、Looker Studioのリンクを渡すだけで最新データを参照できるため便利です。

:::message
Looker StudioからBigQueryへのクエリは実行のたびにコストが発生します。頻繁に参照するデータはBigQueryの「スケジュールされたクエリ」で事前に集計テーブルを作成しておくとコストを抑えられます。
:::

---

## まとめ

本記事では、Shopifyのチェックアウト拡張機能を使ってカスタムイベントをGA4に送信し、BigQueryで分析するまでの流れを解説しました。要点を整理します。

- **チェックアウト拡張機能**を使うと、チェックアウトの各ステップで任意のイベントを発火できる
- GA4に送信したイベントは**BigQueryエクスポート**を通じて詳細分析が可能になる
- BigQueryでは`UNNEST(event_params)`でセッションIDやカスタムパラメータを取得し、`collected_traffic_source`で流入元を把握する
- ファネル分析でボトルネックを特定し、改善施策の効果測定まで一貫して行える
- **Looker Studio**との連携で、非エンジニアの担当者もレポートを閲覧できる環境が作れる

チェックアウトフローの離脱率改善は、広告費を増やさずに売上を伸ばすための重要な取り組みです。まずはBigQueryへのエクスポート設定から着手し、データを蓄積しながら分析の精度を高めていくことをお勧めします。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
