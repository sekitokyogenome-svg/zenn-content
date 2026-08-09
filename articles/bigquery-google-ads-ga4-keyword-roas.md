---
title: "BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する"
emoji: "💹"
type: "tech"
topics: ["bigquery","googleads","googleanalytics","sql","ec"]
published: false
---

## はじめに

Google広告でリスティング広告を運用していると、「どのキーワードが売上に貢献しているか」を正確に把握したいという場面が多いかと思います。Google広告の管理画面でもコンバージョン数やROASを確認できますが、GA4と突き合わせると数値がずれていることはよくあります。計測方法の違いや、ラストクリック帰属モデルへの依存など、原因はさまざまです。

また、中小ECの場合、Google広告の「コンバージョン値」に商品ごとの実際の粗利ではなく売上金額を設定していることが多く、「ROASが高いキーワード」が本当に利益に貢献しているかどうかわかりにくい状況があります。

そこで本記事では、Google広告のデータエクスポートとGA4のBigQueryエクスポートをBigQuery上で結合し、**キーワード単位で広告費・セッション・売上・ROASを一元管理するSQL**を解説します。ECサイトの担当者やWebコンサルタントの方が「手元でデータを自由に分析したい」というニーズに応える内容です。

SQLに慣れていない方も、各ステップを順に読んでいただければ全体の流れを把握できるよう構成しています。

---

## Google広告データをBigQueryにエクスポートする

まず、Google広告側のデータをBigQueryに取り込む必要があります。Google広告はBigQueryへの直接エクスポート機能を持っていないため、以下のいずれかの方法を利用します。

**方法1: Google広告の自動レポートをスプレッドシート経由でBigQueryに取り込む**

Google広告の「自動レポート」機能でキーワードレポートをGoogleスプレッドシートに定期出力し、BigQueryの外部テーブルとして参照するか、Scheduled Queryで定期的にインポートする方法です。小規模であれば最もシンプルです。

**方法2: Google Ads APIを使って直接取得する**

PythonのGoogle Ads APIクライアントを使い、GAQLクエリでキーワード単位の広告費・クリック数・インプレッション数を取得し、BigQueryに書き込みます。以下は取得例です。

```python
from google.ads.googleads.client import GoogleAdsClient

client = GoogleAdsClient.load_from_storage("google-ads.yaml")
ga_service = client.get_service("GoogleAdsService")

query = """
    SELECT
        campaign.name,
        ad_group.name,
        ad_group_criterion.keyword.text,
        metrics.cost_micros,
        metrics.clicks,
        metrics.impressions,
        segments.date
    FROM keyword_view
    WHERE segments.date DURING LAST_30_DAYS
"""

response = ga_service.search_stream(customer_id="YOUR_CUSTOMER_ID", query=query)
```

取得したデータをDataFrameに変換してBigQueryに `to_gbq()` などで書き込むと、キーワード別の広告費テーブルが完成します。

**方法3: Looker Studio ConnectorやデータパイプラインツールでBigQueryに転送する**

Fivetran・Airbyte・Google Ads Data Transferなどのデータ統合ツールを利用する方法もあります。Google広告のData Transfer（BigQuery Data Transfer Service）はキャンペーンレベルまでは対応しており、キーワードレベルは別途対応が必要です。

本記事では、以下のようなスキーマのテーブルがBigQueryに存在することを前提に話を進めます。

```text
テーブル: your_project.ads_data.keyword_stats

date            DATE
campaign_name   STRING
ad_group_name   STRING
keyword_text    STRING
cost            FLOAT64   -- 広告費（円）
clicks          INT64
impressions     INT64
```

---

## GA4のBigQueryエクスポートを理解する

GA4のBigQueryエクスポートを有効にすると、`events_YYYYMMDD` という日付シャーディングされたテーブルが生成されます。1行が1イベントに対応しており、セッションIDや流入元情報はイベントパラメータ（`event_params`）の中にネストされています。

:::message
`ga_session_id` は `event_params` の中にネストされているため、直接カラムとして参照することはできません。`UNNEST(event_params)` を使って展開する必要があります。
:::

また、流入元（UTMパラメータ由来のメディア・ソース）は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` で取得します。これはGA4の新しいスキーマで利用可能な方法です。

キーワード（`utm_term`）については `collected_traffic_source.manual_term` を使用します。

セッションとイベントを紐づけるための基本的なCTEを以下に示します。

```sql
-- GA4イベントからセッションIDと流入情報を抽出するCTE
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはUNNEST経由で取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
)
```

このCTEをベースにしてセッション単位・キーワード単位に集計していきます。

---

## GA4側でキーワード別売上を集計するSQL

GA4のイベントデータからキーワード（`utm_term`）別に売上とセッション数を集計します。`purchase` イベントの `purchase_revenue` を合計することで売上を計算できます。

セッション数はユーザーとセッションIDの組み合わせで重複排除します。

```sql
WITH ga4_raw AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

-- cpcかつgoogle流入のセッションに絞る
paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword)    AS keyword,
    MAX(event_date) AS event_date
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

-- purchaseイベントの売上をセッションに紐づける
session_revenue AS (
  SELECT
    r.user_pseudo_id,
    r.ga_session_id,
    SUM(r.revenue) AS session_revenue
  FROM ga4_raw r
  WHERE r.event_name = 'purchase'
  GROUP BY
    r.user_pseudo_id,
    r.ga_session_id
),

-- キーワード別に集計
keyword_ga4 AS (
  SELECT
    s.keyword,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    s.keyword
)

SELECT * FROM keyword_ga4
ORDER BY revenue DESC;
```

:::message
`ecommerce.purchase_revenue` はGA4のeコマース計測が正しく設定されている場合に値が入ります。設定されていない場合は `event_params` 内の `value` パラメータから取得する必要があります。
:::

---

## Google広告データと結合してキーワード別ROASを算出するSQL

最後に、Google広告の広告費データ（`keyword_stats`）とGA4のキーワード別売上データを結合してROASを計算します。

キーワードの表記揺れ（大文字小文字・前後スペースなど）に対応するため、`LOWER(TRIM(...))` で正規化してから結合するのがポイントです。

```sql
WITH ga4_raw AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword) AS keyword
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_revenue AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    SUM(revenue) AS session_revenue
  FROM ga4_raw
  WHERE event_name = 'purchase'
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

keyword_ga4 AS (
  SELECT
    LOWER(TRIM(s.keyword)) AS keyword_normalized,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    keyword_normalized
),

keyword_ads AS (
  SELECT
    LOWER(TRIM(keyword_text)) AS keyword_normalized,
    SUM(cost)                 AS cost,
    SUM(clicks)               AS clicks,
    SUM(impressions)          AS impressions
  FROM
    `your_project.ads_data.keyword_stats`
  WHERE
    date BETWEEN '2025-06-01' AND '2025-06-30'
  GROUP BY
    keyword_normalized
)

-- 結合してROASを算出
SELECT
  COALESCE(g.keyword_normalized, a.keyword_normalized) AS keyword,
  COALESCE(a.cost, 0)         AS cost,
  COALESCE(a.clicks, 0)       AS clicks,
  COALESCE(a.impressions, 0)  AS impressions,
  COALESCE(g.sessions, 0)     AS ga4_sessions,
  COALESCE(g.revenue, 0)      AS ga4_revenue,
  CASE
    WHEN COALESCE(a.cost, 0) = 0 THEN NULL
    ELSE ROUND(COALESCE(g.revenue, 0) / a.cost, 2)
  END AS roas
FROM keyword_ga4 g
FULL OUTER JOIN keyword_ads a
  ON g.keyword_normalized = a.keyword_normalized
ORDER BY
  ga4_revenue DESC;
```

このクエリを実行すると、キーワードごとに「広告費・クリック数・GA4セッション数・GA4売上・ROAS」が一覧で確認できます。

:::message
ROAS（Return On Ad Spend）= 売上 ÷ 広告費 で計算しています。たとえば広告費1万円で売上3万円なら ROAS = 3.0 です。利益率を考慮した「真の費用対効果」を見たい場合は、売上ではなく粗利額を分子に使うことを検討してください。
:::

---

## 結果をLooker Studioで可視化するヒント

上記のSQLをBigQueryのビュー（View）として保存しておくと、Looker StudioからBigQueryコネクタで直接参照して可視化できます。

ビューの作成は以下のように行います。

```sql
CREATE OR REPLACE VIEW `your_project.reporting.keyword_roas_monthly` AS
(
  -- 上記の最終SELECT文をここに貼り付ける
);
```

Looker Studioでは「キーワード別ROASの棒グラフ」「費用対売上の散布図」「期間比較の折れ線グラフ」などを作成することで、広告運用担当者が直感的に判断できるダッシュボードを構築できます。

月次でデータが蓄積されると、「先月は高ROASだったキーワードが今月は落ちている」といったトレンド変化も把握できるようになります。

---

## まとめ

本記事では、BigQueryを使ってGoogle広告のキーワード別広告費データとGA4のセッション・売上データを結合し、キーワード単位のROASを算出する方法を解説しました。要点を整理します。

- **GA4のga_session_idはUNNEST(event_params)経由**で取得する必要があります
- **流入元の判定には`collected_traffic_source.manual_medium / manual_source`**を使用します
- Google広告データはAPI・スプレッドシート・データパイプラインツールなどでBigQueryに取り込みます
- **FULL OUTER JOINでGA4と広告費を結合**することで、どちらかにしかないキーワードも漏れなく確認できます
- 結果をBigQueryビューとして保存すると、Looker Studioでのダッシュボード化がスムーズです

次のアクションとしては、このクエリを自社のプロジェクトIDに合わせて修正し、まず1ヶ月分のデータで動作確認することをおすすめします。データが蓄積されてきたら、キャンペーン単位・広告グループ単位での分析にも応用できます。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
