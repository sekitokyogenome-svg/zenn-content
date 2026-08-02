---
title: "BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する"
emoji: "🗂️"
type: "tech"
topics: ["bigquery","googleanalytics","sql","googlecloud","dataengineering"]
published: false
---

## はじめに

GA4のデータをBigQueryにエクスポートして分析を始めてみたものの、「どのフィールドがどこに入っているのかわからない」という経験はないでしょうか。GA4のBigQueryエクスポートテーブルは、`event_params`や`user_properties`のようなREPEATED RECORDフィールドが複数含まれており、フラットなテーブルに慣れた方には直感的に扱いにくい構造をしています。

GUIでスキーマを確認しようとしても、ネストが深くなるほどどのフィールドパスを指定すればよいかが把握しにくくなります。また、サードパーティツールから接続しているケースでは、スキーマ定義書を手作業でメンテナンスしているチームも少なくありません。

そこで活用したいのが、BigQueryの情報スキーマビュー `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` です。このビューを使うと、ネストされた全フィールドのパスを一覧で取得でき、スキーマ調査の工数を大幅に削減できます。本記事では、GA4のBigQueryエクスポートデータを例に、`COLUMN_FIELD_PATHS`の使い方を実践的に解説します。

---

## GA4のBigQueryエクスポートスキーマが複雑な理由

GA4のイベントデータをBigQueryにエクスポートすると、`events_YYYYMMDD`という日付シャーディングテーブルが生成されます。このテーブルの特徴は、ほとんどの計測値がREPEATED RECORD型（配列の中にSTRUCT）として格納されている点です。

代表的なネスト構造の例を挙げます。

- `event_params`：イベントごとに付与されたカスタムパラメータが配列として入っている
- `user_properties`：ユーザー単位のプロパティが同様の配列構造で格納される
- `items`：Eコマースで計測した商品情報が配列として入っている
- `collected_traffic_source`：流入元情報がSTRUCT型でまとまっている

例えば `ga_session_id` はテーブルの直接のカラムとして存在するわけではなく、`event_params` の中に `key = 'ga_session_id'` という形でネストされています。これを知らずにクエリを書くと、エラーが返ってきて原因がわからず詰まることがあります。

このような構造を素早く把握するためには、スキーマを「テキストとして一覧取得できる」仕組みが必要です。

---

## COLUMN_FIELD_PATHSとは

`INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` はBigQueryが提供する情報スキーマのひとつで、テーブル内のすべてのフィールド（ネストされたサブフィールドを含む）のパスをフラットな形で返します。

通常の `INFORMATION_SCHEMA.COLUMNS` はトップレベルのカラムしか返しませんが、`COLUMN_FIELD_PATHS` はRECORD型の中に入ったサブフィールドまでドット記法で展開して返してくれます。

基本的な構文は以下のとおりです。

```sql
SELECT
  field_path,
  data_type,
  description
FROM
  `プロジェクトID.データセット名`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'テーブル名'
ORDER BY
  field_path;
```

返ってくる主なカラムは下記です。

| カラム名 | 内容 |
|---|---|
| `table_name` | テーブル名 |
| `column_name` | トップレベルのカラム名 |
| `field_path` | ネストを含む完全なパス（ドット区切り） |
| `data_type` | データ型（STRUCT、ARRAY、STRING等） |
| `description` | カラムの説明（設定されている場合） |

このビューをうまく使うと、どのフィールドがどの階層に存在するかを一度のクエリで把握できます。

---

## 実践：GA4テーブルのスキーマ全体を取得する

では実際にGA4のテーブルに対してクエリを実行してみましょう。GA4のBigQueryエクスポートはデイリーテーブルのため、特定の日付テーブルを指定します。

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
ORDER BY
  field_path;
```

実行すると、`event_params.key`、`event_params.value.string_value`、`event_params.value.int_value` のように、ネストの深いフィールドまですべてドット区切りで一覧表示されます。これにより、たとえば `items` 配列の中に `item_name`、`item_id`、`price` などのサブフィールドが存在することを素早く確認できます。

:::message
`COLUMN_FIELD_PATHS` はデイリーテーブル（`events_YYYYMMDD`）にも、インターデイテーブル（`events_intraday_YYYYMMDD`）にも使用できます。ただし、シャーディングテーブルのワイルドカード（`events_*`）はビューとして扱われないため、個別の日付テーブル名を指定する必要があります。
:::

---

## 特定フィールドだけを絞り込んで探索する

スキーマ全体を取得すると行数が多くなるため、目的のフィールドだけをフィルタリングする使い方も効果的です。

たとえば、Eコマース計測のフィールドだけを確認したい場合は次のようにします。

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
  AND field_path LIKE 'items%'
ORDER BY
  field_path;
```

また、流入元の情報は `collected_traffic_source` というSTRUCT型カラムにまとまっています。以下のクエリでそのサブフィールドを確認できます。

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
  AND field_path LIKE 'collected_traffic_source%'
ORDER BY
  field_path;
```

このクエリを実行すると、`collected_traffic_source.manual_medium` や `collected_traffic_source.manual_source` といったフィールドパスが確認でき、流入元分析のクエリを書くときに正確なカラム名を把握できます。

---

## 実際の分析クエリへの応用

`COLUMN_FIELD_PATHS` で確認したフィールドパスをもとに、実際の分析クエリを組み立てる例を示します。ここでは「流入元ごとのセッション数を集計する」クエリを書きます。

`ga_session_id` は `event_params` の中にネストされているため、`UNNEST` が必要です。また、流入元は `collected_traffic_source.manual_medium` から取得します。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `your-project.analytics_XXXXXXXXX.events_20250101`
WHERE
  event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
```

:::message
`ga_session_id` を取得する際は、`event_params` を `UNNEST` してから `key = 'ga_session_id'` で絞り込む必要があります。`value.int_value` で整数値を取得してください。`event_params` を展開しないと該当フィールドへのアクセスはできません。
:::

`COLUMN_FIELD_PATHS` で `event_params` のサブフィールドとして `value.int_value`、`value.string_value` 等があることを事前に把握しておくと、このような UNNEST クエリを迷わず書けるようになります。

---

## スキーマ定義書を自動生成する活用例

`COLUMN_FIELD_PATHS` はスキーマ探索だけでなく、ドキュメント生成にも活用できます。以下のように Python + BigQuery クライアントライブラリを使うと、取得したスキーマ情報をCSVやMarkdownとして書き出すことが可能です。

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="your-project")

query = """
SELECT
  field_path,
  data_type,
  description
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
ORDER BY
  field_path
"""

df = client.query(query).to_dataframe()
df.to_csv("ga4_schema.csv", index=False)
print(df.head(20))
```

このスクリプトを定期実行するか、スキーマ変更が疑われるタイミングで手動実行することで、GA4の仕様変更による意図せぬフィールドの追加・削除を検知できます。

:::message
GA4は定期的にBigQueryエクスポートのスキーマが更新されることがあります。`COLUMN_FIELD_PATHS` を活用したスキーマ監視の仕組みを用意しておくと、分析クエリが突然動かなくなるリスクを低減できます。
:::

---

## まとめ

本記事では、BigQueryの `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` を使ってGA4のネストされたスキーマを効率的に探索する方法を解説しました。要点を整理します。

- GA4のBigQueryエクスポートテーブルは `event_params`・`items`・`user_properties` 等のREPEATED RECORD型が多く、スキーマ把握が難しい
- `COLUMN_FIELD_PATHS` を使うとネストを含む全フィールドパスをフラット一覧で取得できる
- `LIKE` 句で絞り込むことで、特定の用途（Eコマース・流入元等）に必要なフィールドだけを確認できる
- 確認したフィールドパスをもとに、`UNNEST` を活用した正確な分析クエリを組み立てやすくなる
- Pythonと組み合わせればスキーマ定義書の自動生成・変更検知にも応用できる

スキーマ探索に使う時間を削減して、分析本来の作業に集中するために、ぜひ `COLUMN_FIELD_PATHS` を日常的なワークフローに取り入れてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
