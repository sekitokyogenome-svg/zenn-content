# ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する

## はじめに

「倉庫に眠り続けている商品がある」「どの商品が売れていて、どの商品が滞留しているのか把握しきれていない」——そのような悩みを持つEC運営者は少なくありません。商品点数が増えるほど、感覚的な管理では限界が生じ、知らぬ間に死に筋商品がキャッシュフローを圧迫していきます。

在庫回転率は、手持ちの在庫が一定期間でどれほど売れたかを示す指標です。回転率が低い商品ほど資金が寝ている状態であり、保管コストや廃棄リスクも高まります。逆に回転率が高すぎると機会損失が発生することもあるため、商品ごとの適正な水準を把握することが重要です。

本記事では、GA4のBigQueryエクスポートデータと在庫データを組み合わせて、商品別の在庫回転率を算出・可視化するSQLと、Looker Studioでのダッシュボード構築の流れを解説します。非エンジニアの方でも手順を追えるよう、SQLのポイントについても丁寧に説明しています。

## 在庫回転率とは何か——算式と読み方

在庫回転率は一般的に以下の式で計算されます。

```
在庫回転率 = 売上原価（または売上数量） ÷ 平均在庫数
```

たとえば、ある商品の月間販売数が100個で、月初在庫が50個・月末在庫が30個であれば、平均在庫は40個です。この場合の在庫回転率は `100 ÷ 40 = 2.5` となります。つまり、その月のあいだに在庫が2.5回転したことを意味します。

ECの文脈では、GA4の購買イベント（`purchase`）から商品ごとの販売数量を取得し、倉庫管理システム（WMS）やスプレッドシートで管理している在庫数と組み合わせる形が現実的です。BigQueryにGA4データがエクスポートされていれば、SQLで商品ごとの販売数量を集計できます。

> 在庫回転率に正解の数値はなく、業種や商品カテゴリによって目安が異なります。ファッション系では月次10回転以上を目指す場合もあれば、高単価・低回転が前提の商材もあります。まずは自社商品間での相対比較から始めることをお勧めします。

<!-- ここから有料 -->

## GA4のBigQueryエクスポートから商品別販売数量を取得するSQL

GA4のBigQueryエクスポートでは、`events_*` テーブルに購買イベントが記録されています。商品情報は `items` 配列の中に格納されているため、`UNNEST` を使って展開する必要があります。

以下のSQLは、指定した期間内の商品別販売数量と売上金額を集計するものです。プロジェクトIDとデータセット名はご自身の環境に合わせて書き換えてください。

```sql
-- 商品別 販売数量・売上金額の集計（GA4 BigQueryエクスポート）
SELECT
  item.item_id                          AS product_id,
  item.item_name                        AS product_name,
  SUM(item.quantity)                    AS total_quantity_sold,
  ROUND(SUM(item.item_revenue), 2)      AS total_revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  product_id,
  product_name
ORDER BY
  total_quantity_sold DESC
;
```

このSQLをベースに、BigQueryのストレージに在庫マスタを別テーブルとして持たせることで、回転率の計算まで一気通貫で行えます。

> GA4の `purchase` イベントには返品や取り消しは通常含まれません。精度を上げたい場合は、ECプラットフォーム側の注文データをBigQueryに連携してGA4データと照合することも検討してください。

## 在庫マスタと結合して回転率を算出するSQL

在庫データをBigQueryにアップロード（またはGoogle スプレッドシートと連携）した前提で、商品別の在庫回転率を算出するSQLを示します。

在庫マスタテーブルの想定スキーマは以下の通りです。

**product_id**
- 型: STRING
- 内容: 商品ID

**product_name**
- 型: STRING
- 内容: 商品名

**stock_start**
- 型: INT64
- 内容: 期初在庫数

**stock_end**
- 型: INT64
- 内容: 期末在庫数

```sql
-- 在庫回転率の算出（GA4販売実績 × 在庫マスタ）
WITH sales AS (
  SELECT
    item.item_id                     AS product_id,
    SUM(item.quantity)               AS total_quantity_sold
  FROM
    `your_project.analytics_XXXXXXX.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND item.quantity > 0
  GROUP BY
    product_id
),
inventory AS (
  SELECT
    product_id,
    product_name,
    stock_start,
    stock_end,
    SAFE_DIVIDE(stock_start + stock_end, 2) AS avg_stock
  FROM
    `your_project.your_dataset.inventory_master`
)
SELECT
  inv.product_id,
  inv.product_name,
  COALESCE(s.total_quantity_sold, 0)              AS total_quantity_sold,
  inv.avg_stock,
  ROUND(
    SAFE_DIVIDE(COALESCE(s.total_quantity_sold, 0), inv.avg_stock),
    2
  )                                               AS inventory_turnover_rate
FROM
  inventory AS inv
LEFT JOIN
  sales AS s
  ON inv.product_id = s.product_id
ORDER BY
  inventory_turnover_rate ASC  -- 回転率の低い順（死に筋候補が上位に）
;
```

`SAFE_DIVIDE` を使うことで、平均在庫が0の場合にエラーではなく `NULL` を返すようにしています。また、GA4に購買データが存在しない商品（販売実績ゼロ）も在庫マスタ側から全件表示されるよう `LEFT JOIN` を使用しています。

## 流入チャネル別に死に筋を掘り下げる

在庫回転率が低い商品であっても、特定の流入チャネルでは一定数売れている場合があります。たとえば、「メール経由では売れているがSEO流入では全く売れていない」という差が見えると、施策の方向性が変わってきます。

GA4のBigQueryエクスポートでは、流入元の情報を `collected_traffic_source` から取得できます。

```sql
-- 流入チャネル × 商品別 販売数量の集計
SELECT
  collected_traffic_source.manual_medium   AS medium,
  collected_traffic_source.manual_source   AS source,
  item.item_id                             AS product_id,
  item.item_name                           AS product_name,
  SUM(item.quantity)                       AS total_quantity_sold
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  medium,
  source,
  product_id,
  product_name
ORDER BY
  product_id,
  total_quantity_sold DESC
;
```

このデータを在庫回転率の結果と合わせてLooker Studioに取り込むことで、「回転率が低い商品のうち、どのチャネルへの露出が不足しているか」をビジュアルで確認できます。

> `manual_medium` / `manual_source` はUTMパラメータが付与されたセッションのみ値が入ります。UTMが設定されていない流入は空白になるため、重要チャネルには必ずUTMを設定するようにしてください。

## Looker Studioで在庫回転率ダッシュボードを構築する

BigQueryで算出した在庫回転率のクエリ結果をLooker Studioに接続することで、商品別の可視化ダッシュボードを構築できます。

**接続手順の概要**

1. Looker Studioにログインし、「データソースを追加」からBigQueryコネクタを選択する
2. プロジェクト・データセットを選択し、作成したビューまたはテーブルを指定する
3. レポートに「テーブル」チャートを追加し、ディメンションに `product_name`、指標に `inventory_turnover_rate` と `total_quantity_sold` を設定する

ダッシュボードに以下の要素を加えると、経営者やマーチャンダイザーが日々確認しやすい構成になります。

- **棒グラフ**：回転率下位10商品の比較（死に筋の一覧）
- **散布図**：横軸に在庫数、縦軸に販売数量（バブルの大きさは在庫回転率）
- **カテゴリフィルター**：商品カテゴリや仕入れ先でドリルダウンできるようにする
- **日付コントロール**：月次・四半期での比較を可能にする

Looker Studioは複数のデータソースを1つのレポートに統合できるため、GA4の行動データ（商品ページの閲覧数やカート追加数）と在庫回転率を並べると、「見られているのに買われていない商品」の特定にも役立ちます。

## まとめ

本記事では、ECにおける在庫回転率の基本概念から、GA4×BigQueryを使った商品別集計SQL、在庫マスタとの結合による回転率算出、流入チャネル別の分解、Looker Studioでのダッシュボード構築までの流れを解説しました。

要点を整理します。

- 在庫回転率は「販売数量 ÷ 平均在庫数」で算出し、低い商品が死に筋候補となる
- GA4のBigQueryエクスポートでは `UNNEST(items)` で商品情報を展開して集計する
- 流入元は `collected_traffic_source.manual_medium` / `manual_source` で取得する
- 在庫マスタをBigQueryに置き、`LEFT JOIN` で結合することで回転率を一括算出できる
- Looker Studioで可視化することで、経営判断に活用できるダッシュボードを構築できる

次のアクションとしては、まず直近1〜3ヶ月分のデータで回転率を算出し、下位10〜20商品をリストアップすることをお勧めします。そのうえで、在庫処分・値引きプロモーション・仕入れ抑制のどれが適切かを個別に検討していくと、キャッシュフローの改善につながります。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
