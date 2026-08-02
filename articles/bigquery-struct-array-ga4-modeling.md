---
title: "BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする"
emoji: "🗄️"
type: "tech"
topics: ["bigquery","sql","googleanalytics","googlecloud","dataengineering"]
published: false
---

## はじめに

GA4のデータをBigQueryにエクスポートしてSQLで分析しようとしたとき、「event_paramsの中身が取り出せない」「ネストされた構造が複雑でクエリが書けない」と感じた経験はありませんか。GA4のBigQueryエクスポートデータは、従来のフラットなテーブル構造とは異なり、STRUCT（構造体）やARRAY（配列）が入れ子になった独特のスキーマを持っています。

この構造は最初こそ難解に見えますが、正しく理解すると「1行のイベントデータに複数のパラメータをまとめて持てる」という強力な設計思想が見えてきます。つまり、BigQueryのSTRUCT・ARRAY型はGA4データの多様なイベント属性を効率よく格納するために選ばれた仕組みです。

本記事では、BigQueryのSTRUCT型とARRAY型の基本概念から、GA4のイベントデータに対する実践的なクエリの書き方、そしてデータマートとして整形・再利用しやすい形にモデリングする方法までを解説します。SQLの経験が浅い方でも理解できるよう、具体的なコード例を交えて丁寧に説明していきます。

---

## STRUCT型とARRAY型の基本を理解する

BigQueryにおける **STRUCT型** は、複数のフィールドを1つの値としてまとめたデータ型です。たとえば「名前・年齢・都市」をひとつのSTRUCTにまとめると、1つのカラムにオブジェクトのような構造を持たせることができます。

一方、**ARRAY型** は同じ型の値を複数並べたリスト（配列）です。GA4では `event_params` や `user_properties` がARRAY型になっており、1つのイベント行に対して複数のキーと値のペアが格納されています。

GA4のBigQueryエクスポートスキーマでは、この2つが組み合わさり `ARRAY<STRUCT<key STRING, value STRUCT<...>>>` という構造になっています。

```sql
-- event_paramsの構造イメージ（スキーマ確認用）
SELECT
  event_name,
  event_params
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = '20240801'
LIMIT 1
```

このクエリを実行すると、`event_params` カラムにはキーと値のペアがリスト形式で返ってきます。これをそのまま使うのではなく、`UNNEST` 関数を使って展開する必要があります。

:::message
STRUCT・ARRAYのネスト構造はBigQueryの「繰り返しフィールド」と呼ばれます。1行のレコードに複数の値を持てるため、データの正規化コストを下げながら高速な集計ができる設計になっています。
:::

---

## UNNESTでevent_paramsを展開する

GA4データを分析するうえで最初の壁となるのが、`event_params` の展開です。`UNNEST` 関数はARRAY型を行に展開するBigQuery固有の操作で、これを使うことで特定のパラメータ値を取り出せます。

たとえば `ga_session_id`（セッションID）はイベントパラメータの中に格納されており、カラムとして直接参照することはできません。以下のように `UNNEST` を使って取り出します。

```sql
-- ga_session_idをevent_paramsから取得する例
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
```

サブクエリ形式の `UNNEST` は、特定のキーだけを取り出すときに便利です。`value` の中には `string_value`・`int_value`・`float_value`・`double_value` の4種類があるため、取得したいパラメータに合わせて適切なフィールドを指定してください。

`ga_session_id` は整数値なので `int_value` を使います。ページのURLやタイトルは `string_value` で取得します。

```sql
-- ページタイトルとセッションIDを同時に取得する例
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_title'
  ) AS page_title,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_location'
  ) AS page_location
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
```

---

## 流入元データをcollected_traffic_sourceから取得する

GA4のBigQueryエクスポートには、セッションの流入元情報を取得するフィールドとして `collected_traffic_source` があります。これはSTRUCT型のカラムであり、UTMパラメータを含む流入元データをドット記法でアクセスできます。

流入元の取得には `collected_traffic_source.manual_source`（参照元）と `collected_traffic_source.manual_medium`（メディア）を使います。

```sql
-- 流入元ごとのpage_viewイベント数を集計する例
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS page_view_count
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date,
  page_view_count DESC
```

:::message
`collected_traffic_source` はGA4のイベント収集時に付与される流入元情報です。`traffic_source`（ユーザー初回流入元）と混同しないよう注意してください。セッション単位の流入元分析には `collected_traffic_source` が適しています。
:::

STRUCT型はドット記法でフィールドにアクセスできるため、UNNESTを使わずシンプルに記述できます。これがARRAY型との大きな違いです。

---

## セッションテーブルをデータマートとして整形する

毎回 `UNNEST` を含む複雑なクエリを書くのは非効率です。よく使うディメンションやメトリクスをあらかじめ展開した「セッションマートテーブル」を作成しておくと、後続の分析クエリがシンプルになります。

以下は、セッションIDを軸に流入元・デバイス情報・コンバージョン数をまとめたセッションレベルの集計テーブルを作成するクエリの例です。

```sql
-- セッションマートテーブルの作成例（CREATE TABLE AS SELECT）
CREATE OR REPLACE TABLE `project_id.your_dataset.session_mart` AS

WITH base AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    geo.country AS country
  FROM
    `project_id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
)

SELECT
  event_date,
  user_pseudo_id,
  ga_session_id,
  MAX(source) AS source,
  MAX(medium) AS medium,
  MAX(device_category) AS device_category,
  MAX(country) AS country,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM
  base
WHERE
  ga_session_id IS NOT NULL
GROUP BY
  event_date,
  user_pseudo_id,
  ga_session_id
```

このようにWITH句（CTE）でベーステーブルを整形し、GROUP BYでセッション単位に集約することで、後続のダッシュボード用クエリを簡潔に保てます。LookerStudioや他のBIツールからこのマートテーブルを参照すると、クエリのパフォーマンスも向上します。

:::message
BigQueryではパーティションテーブルやクラスタリングを活用することで、スキャン量を削減できます。セッションマートテーブルには `event_date` でパーティション設定することを検討してください。
:::

---

## まとめ

本記事では、BigQueryのSTRUCT・ARRAY型の基本から、GA4のBigQueryエクスポートデータへの実践的なクエリ手法、そしてセッションマートテーブルの構築方法を解説しました。

- **STRUCT型** はドット記法でフィールドにアクセスでき、`collected_traffic_source` のような流入元データに活用されます
- **ARRAY型** は `UNNEST` で展開することで個々の値を取り出せ、`event_params` の取得に使います
- `ga_session_id` は `UNNEST(event_params)` 経由で取得し、`int_value` で値を参照します
- よく使うディメンションをあらかじめ整形したセッションマートテーブルを作成しておくと、分析効率が高まります

GA4のBigQueryデータはネスト構造が特殊なため、最初は難しく感じるかもしれません。しかし構造のパターンを掴んでしまえば、SQLの書き方は比較的シンプルです。まずは小規模な日付範囲でクエリを試してみて、スキャン量を確認しながら段階的に本番環境へ適用していくアプローチが現実的です。

次のステップとして、スケジュールドクエリを使ってマートテーブルを定期更新したり、LookerStudioと連携してダッシュボードを構築したりする方向に進んでみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
