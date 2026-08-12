---
title: "BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順"
emoji: "📊"
type: "tech"
topics: ["bigquery","lookerstudio","googleads","advertising","ec"]
published: true
---

## はじめに

「Google広告とMeta広告でそれぞれROASを確認しているが、どちらに予算を寄せればよいかわからない」——このような状況に置かれているEC担当者は少なくありません。広告媒体ごとにレポートが分散していると、全体の投資対効果を把握するだけでも相当な時間がかかります。

また、媒体ダッシュボードのROASはクリックベースでコンバージョンを計測するため、アトリビューションのルールが媒体ごとに異なります。そのため、単純に数値を並べても「どの媒体が本当に貢献しているか」を判断しにくいのが現実です。

本記事では、GA4のイベントデータをBigQueryへエクスポートし、広告費データと結合したうえでLooker Studioのダッシュボードに可視化するまでの流れを解説します。SQLの基本的な読み方がわかれば対応できる内容を中心に構成していますので、エンジニア以外の方にも参考にしていただけます。

---

## 1. 全体アーキテクチャの把握

ダッシュボードを構築するにあたり、まずデータの流れを整理しておきます。

```text
GA4 → BigQuery（イベントデータ）
                          ↓
広告媒体API（Google Ads / Meta Ads）→ BigQuery（広告費テーブル）
                          ↓
                   BigQuery（統合ビュー）
                          ↓
                    Looker Studio
```

GA4のBigQueryエクスポートを有効にすると、`events_YYYYMMDD` 形式のテーブルにイベントデータが日次で蓄積されます。一方、広告費データは各媒体のAPIや公式コネクタ（例：Google AdsのBigQueryエクスポート、Fivetran、Stitch等）を使ってBigQueryに取り込みます。

この2種類のデータをBigQuery上でJOINし、Looker Studioから参照するのが本構成の基本的な考え方です。BigQueryで統合ビューを作成しておくことで、Looker Studio側の設定がシンプルになり、レポートのメンテナンスコストも下がります。

---

## 2. GA4 BigQueryエクスポートからROAS計算に必要なデータを取得する

GA4のBigQueryエクスポートテーブルには、セッションや購入に関するイベントが格納されています。ROASの計算に必要な要素は「購入金額（revenue）」と「流入元（medium / source）」の2つです。

以下のSQLは、`purchase` イベントから日次・流入元別の売上を集計するクエリです。

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  1, 2, 3
ORDER BY
  date DESC
```

:::message
`ga_session_id` は `event_params` 配列の中に格納されているため、`UNNEST(event_params)` を経由して取得します。テーブルのトップレベルカラムとして直接参照することはできません。
:::

`collected_traffic_source.manual_medium` および `manual_source` は、URLパラメータ（`utm_medium` / `utm_source`）の値がGA4側で自動的にセッションに紐付けられたフィールドです。広告媒体を判別するためのキーとして活用します。

---

## 3. 広告費データをBigQueryに取り込む

広告費データをBigQueryに集約する方法はいくつかありますが、中小規模のEC事業者に向いているアプローチとして以下の2つを紹介します。

**方法A: Google AdsのBigQuery直接エクスポート（無料）**

Google Ads管理画面の「ツールと設定 → データマネージャー → BigQueryへのエクスポート」から設定できます。キャンペーン別の費用データが自動連携されます。

**方法B: スプレッドシートで手動管理してBigQueryへアップロード**

Meta AdsやYahoo広告など、BigQuery直接連携に対応していない媒体は、スプレッドシートで費用をまとめてBigQueryにアップロードする方法が現実的です。以下のような形式でCSVを準備してください。

```csv
date,medium,source,cost
2025-07-01,cpc,google,15000
2025-07-01,cpc,facebook,8000
2025-07-01,cpc,yahoo,5000
```

BigQueryへのアップロードはGUIから行えます。BigQueryコンソールでデータセットを選択し「テーブルを作成 → アップロード」を選ぶだけです。スキーマは自動検出でも問題ありませんが、`date` 型は `DATE` に変換されているか確認してください。

---

## 4. BigQueryで統合ビューを作成する

GA4の売上データと広告費データを結合し、ROASを算出するビューを作成します。

```sql
CREATE OR REPLACE VIEW `your_project.your_dataset.v_roas_summary` AS

WITH ga4_revenue AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    1, 2, 3
),

ad_cost AS (
  SELECT
    date,
    medium,
    source,
    SUM(cost) AS cost
  FROM
    `your_project.your_dataset.ad_cost`
  GROUP BY
    1, 2, 3
)

SELECT
  COALESCE(r.date, c.date) AS date,
  COALESCE(r.medium, c.medium) AS medium,
  COALESCE(r.source, c.source) AS source,
  COALESCE(r.revenue, 0) AS revenue,
  COALESCE(c.cost, 0) AS cost,
  SAFE_DIVIDE(COALESCE(r.revenue, 0), COALESCE(c.cost, 0)) AS roas
FROM
  ga4_revenue r
FULL OUTER JOIN
  ad_cost c
  ON r.date = c.date
  AND r.medium = c.medium
  AND r.source = c.source
```

:::message
`SAFE_DIVIDE` を使うことで、広告費が0の場合でもエラーにならず `NULL` が返ります。Looker Studioでは `NULL` はグラフ上で空白として扱われるため、表示上の問題が発生しにくくなります。
:::

FULL OUTER JOINを使用している理由は、広告費だけがあって購入がない日・流入元の組み合わせや、逆にオーガニック経由の売上（広告費なし）も欠落なく拾うためです。

---

## 5. Looker Studioでダッシュボードを構築する

BigQueryのビューが完成したら、Looker Studioからデータを参照してダッシュボードを仕上げます。

**データソースの接続手順**

1. Looker Studioを開き「データを追加」からBigQueryを選択します
2. プロジェクト → データセット → 作成したビュー（`v_roas_summary`）を選択します
3. フィールドの型を確認し、`date` が「日付」、`revenue` / `cost` / `roas` が「数値」になっていることを確認します

**推奨ウィジェット構成**

| ウィジェット | 使用フィールド | 用途 |
|---|---|---|
| スコアカード | ROAS（全期間平均） | 全媒体の概況把握 |
| 折れ線グラフ | 日付 × ROAS（medium別） | 媒体別ROASの推移確認 |
| 棒グラフ | source × revenue / cost | 流入元別の収益・費用比較 |
| 表 | date / medium / source / revenue / cost / ROAS | 詳細データの確認 |

Looker Studioの「フィルタコントロール」を追加し、`medium` や `source` でインタラクティブに絞り込めるようにしておくと、担当者が媒体ごとに確認する際の操作性が向上します。

---

## まとめ

本記事では、以下の流れで広告媒体横断ROASダッシュボードの構築手順を解説しました。

1. **全体設計**: GA4 → BigQuery → Looker Studioのデータフローを整理
2. **売上データの取得**: GA4エクスポートテーブルからSQLでrevenue・流入元を集計
3. **広告費データの取り込み**: Google Adsは直接エクスポート、その他媒体はCSVアップロード
4. **統合ビューの作成**: FULL OUTER JOINでROASを算出するビューをBigQueryに構築
5. **ダッシュボードの作成**: Looker Studioでスコアカード・グラフ・フィルタを配置

初期構築に時間はかかりますが、一度整備しておけば毎月のレポート作業を大幅に削減できます。まずはGoogle広告1媒体で試作し、慣れてきたら他媒体のデータを追加していく進め方が取り組みやすいです。

次のアクションとして、GA4のBigQueryエクスポートがまだ有効になっていない場合は、GA4管理画面の「管理 → BigQueryのリンク」から設定をはじめてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
