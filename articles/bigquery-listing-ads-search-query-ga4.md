---
title: "BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する"
emoji: "🔎"
type: "tech"
topics: ["bigquery","googleads","googleanalytics","sql","advertising"]
published: false
---

## はじめに

リスティング広告を運用していると、「どの検索キーワードが実際にコンバージョンにつながっているのか」という問いに直面することがあります。Google広告の管理画面でも検索クエリレポートは確認できますが、そこで見えるのはあくまでクリック数やコンバージョン数といった広告側の指標にとどまります。

実際にサイトに来訪したユーザーが、どのページを閲覧し、どの商品を見て、最終的に購入や問い合わせに至ったのか――そういったサイト内行動との接続は、広告管理画面だけでは把握しきれません。

こうした課題を解決する手段のひとつが、BigQueryを活用したデータ統合です。Google広告の検索クエリデータとGA4のイベントデータをBigQuery上で結合することで、「どのクエリで来訪したユーザーが、その後どのような行動を取ったか」をSQLで柔軟に分析できるようになります。

本記事では、BigQueryへのデータエクスポート設定が完了していることを前提に、実際に使えるSQLクエリを交えながら突合分析の考え方と手順を解説します。Google広告とGA4の両方をBigQueryに連携済みの方、あるいはこれから連携を検討している方に向けた内容です。

---

## データ基盤の準備：Google広告とGA4をBigQueryに連携する

分析を始める前に、BigQueryに必要なデータが揃っているかを確認します。

**GA4のBigQueryエクスポート**は、GA4プロパティの設定画面から有効化できます。有効化すると、Googleが管理するBigQueryプロジェクトに `events_YYYYMMDD` 形式のテーブルが日次で作成されます。テーブルには、セッションID・イベント名・パラメータ・ページURL・流入元などの情報がネスト構造で格納されています。

**Google広告のBigQueryエクスポート**は、Google広告の「データのリンク」設定からBigQueryへのリンクを追加することで有効化できます。こちらには `SearchQueryPerformance` などのパフォーマンスレポートが格納され、検索クエリごとのインプレッション・クリック・コスト・コンバージョン数を確認できます。

:::message
両方のエクスポートが完了するまで最低1日程度かかります。また、GA4側のデータはイベント発生から24〜48時間後に反映されることがあります。分析はデータが安定した翌々日以降に行うことをお勧めします。
:::

---

## GA4テーブルから流入クエリとセッション行動を抽出する

GA4のBigQueryエクスポートデータには、ユーザーがどのような経路でサイトに来訪したかが記録されています。リスティング広告経由のセッションを特定するには、`collected_traffic_source` フィールドの `manual_medium` および `manual_source` を使用します。

また、セッションを一意に識別する `ga_session_id` は、イベントパラメータにネストされているため、`UNNEST(event_params)` を経由して取得する必要があります。

以下のSQLは、cpc（クリック課金）経由で来訪したセッションの基本情報を取得する例です。

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source AS traffic_source,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_term AS keyword,
  event_name,
  event_timestamp,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location
FROM
  `your_project.your_dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND event_name IN ('page_view', 'purchase', 'generate_lead')
```

`manual_term` にはGoogleタグマネージャーやGoogleタグで自動タグ付けを設定している場合にキーワードが格納されます。自動タグ付けが有効な場合は `gclid` を経由してGoogle広告側のデータと結合する方法も有効です。

---

## Google広告の検索クエリデータと突合する

Google広告のBigQueryエクスポートには、実際にユーザーが入力した検索クエリが `SearchQueryPerformance` テーブルに格納されています。このテーブルには、クエリごとのクリック数・コスト・コンバージョン数などが含まれます。

以下のSQLは、GA4のセッションデータとGoogle広告の検索クエリデータをキーワードで結合し、クエリごとのサイト内行動を集計する例です。

```sql
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_term AS keyword,
    event_name,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'page_location'
    ) AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date
  FROM
    `your_project.your_dataset.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'cpc'
),

ads_queries AS (
  SELECT
    Query AS search_query,
    Clicks,
    Cost,
    Conversions,
    Date AS query_date
  FROM
    `your_project.google_ads_export.SearchQueryPerformance`
  WHERE
    Date BETWEEN '2025-06-01' AND '2025-06-30'
)

SELECT
  aq.search_query,
  aq.Clicks,
  aq.Cost,
  aq.Conversions,
  COUNT(DISTINCT CONCAT(gs.user_pseudo_id, CAST(gs.ga_session_id AS STRING))) AS ga4_sessions,
  COUNTIF(gs.event_name = 'purchase') AS purchase_events,
  COUNTIF(gs.event_name = 'generate_lead') AS lead_events
FROM
  ads_queries aq
LEFT JOIN
  ga4_sessions gs
  ON aq.search_query = gs.keyword
  AND aq.query_date = gs.event_date
GROUP BY
  aq.search_query, aq.Clicks, aq.Cost, aq.Conversions
ORDER BY
  aq.Cost DESC
LIMIT 100
```

:::message
Google広告のBigQueryエクスポートで利用できるテーブル名やフィールド名は、リンク設定時の構成によって異なる場合があります。実際の環境では `INFORMATION_SCHEMA.TABLES` で確認することをお勧めします。
:::

---

## 分析視点：クエリごとのサイト行動をどう読むか

SQLでデータを取得したあとは、どのような視点で分析を進めるかが重要です。以下にいくつかの観点を挙げます。

**クリックはあるがGA4セッションが少ないクエリ**は、ランディングページの表示速度の問題や、ページとの関連性が低い可能性があります。広告のランディングURLとGA4のpage_locationを照合することで、トラフィックのロスを検出できます。

**コストが高いのに購入・リードが発生していないクエリ**は、入札停止や除外キーワードへの追加を検討する根拠になります。単に広告管理画面のコンバージョン数だけで判断するのではなく、GA4側の行動データ（特定ページの閲覧有無や滞在時間など）を合わせて確認することで、判断の精度が上がります。

**購入に至ったセッションが多いクエリ**は、広告グループの強化や予算配分の優先度引き上げの候補になります。GA4のイベントデータを使えば、コンバージョンに至るまでに閲覧したページ数や滞在時間なども集計できるため、「どのような行動パターンの人が購入しているか」という解像度で分析できます。

以下は、購入セッションにおける直前のページ閲覧パターンを見るための補助クエリです。

```sql
SELECT
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS view_count
FROM
  `your_project.your_dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'page_view'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND CONCAT(user_pseudo_id, CAST(
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS STRING
  )) IN (
    -- 購入セッションのIDリスト（サブクエリやWITH句で生成）
    SELECT DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (
          SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      ))
    FROM
      `your_project.your_dataset.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
      AND event_name = 'purchase'
  )
GROUP BY page_location
ORDER BY view_count DESC
```

---

## Looker Studioでの可視化に向けて

BigQueryで集計したデータは、Looker Studio（旧Data Studio）に接続することで視覚的に確認しやすくなります。Looker StudioのデータソースとしてBigQueryを直接指定するか、BigQueryのビュー（VIEW）を作成してから連携することで、毎日最新のデータを参照するダッシュボードが実現できます。

推奨するダッシュボード構成の例を以下に示します。

| 指標 | 集計軸 |
|------|--------|
| クリック数・コスト | 検索クエリ別 |
| GA4セッション数 | 検索クエリ別・日付別 |
| 購入・リード数 | 検索クエリ別 |
| 閲覧ページTop10 | 購入セッション内 |

Looker Studio上でフィルタを設定することで、期間や特定のキャンペーンに絞った分析がノーコードで行えるようになります。経営者や非エンジニアのメンバーと共有する際には、このようなダッシュボード形式に落とし込むことで、分析結果の活用が広がります。

---

## まとめ

本記事では、BigQueryを使ってGoogle広告の検索クエリデータとGA4の行動データを突合分析する方法を解説しました。

- GA4のBigQueryエクスポートでは、`ga_session_id` は `UNNEST(event_params)` 経由で取得する
- 流入元の判定には `collected_traffic_source.manual_medium` / `manual_source` を使用する
- Google広告の検索クエリテーブルとGA4データを結合することで、クエリごとのサイト内行動が把握できる
- 「クリックはあるがGA4セッションが少ない」「コスト高・成果なし」「購入率が高い」という3軸でクエリを評価することが、広告改善の出発点になる

広告費の最適化は、広告管理画面だけを見ていては限界があります。サイト内のユーザー行動と組み合わせることで、より実態に近い判断ができるようになります。まずは1ヶ月分のデータで試してみることをお勧めします。

## 関連記事

- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)
- [BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）](https://zenn.dev/web_benriya/articles/ga4-bigquery-bounce-rate-calculation)
- [GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する](https://zenn.dev/web_benriya/articles/ga4-bigquery-cac-by-channel)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
