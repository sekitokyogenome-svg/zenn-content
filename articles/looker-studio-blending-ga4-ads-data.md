---
title: "Looker StudioのブレンディングでGA4×広告データを結合する方法"
emoji: "🔗"
type: "tech"
topics: ["lookerstudio","bigquery","googleads"]
published: false
---

## はじめに

「GA4のコンバージョンデータとGoogle広告の費用データを、1つのダッシュボードで並べて見たい」と思ったことはないでしょうか。

GA4だけでは広告費用が取れず、Google広告だけではサイト内の行動データが見られません。この2つを横断的に分析するには、データの結合が必要です。

Looker Studioには「ブレンディング」という機能があり、異なるデータソースを結合キーで紐づけることができます。この記事では、GA4とGoogle広告のデータをブレンディングで結合し、ROAS（広告費用対効果）まで可視化する方法を解説します。

## ブレンディングとは何か

ブレンディングは、Looker Studio上で複数のデータソースを結合する機能です。SQLのJOINに近い概念ですが、GUI操作で設定できます。

### ブレンディングの種類

| 結合タイプ | 説明 |
|---|---|
| 左外部結合 | 左テーブルの全行を保持し、右テーブルの一致する行を結合 |
| 右外部結合 | 右テーブルの全行を保持 |
| 内部結合 | 両方に存在する行のみ |
| 完全外部結合 | 両方の全行を保持 |
| クロス結合 | すべての組み合わせ |

GA4と広告データの結合では「左外部結合」を使うケースが多いです。日付をキーにして、GA4のデータに広告費用を紐づけます。

## 事前準備: データソースの追加

### GA4データソースの追加

1. Looker Studioでレポートを開く
2. 「リソース」→「データソースの管理」→「データソースを追加」
3. 「Googleアナリティクス」コネクタを選択
4. 対象のGA4プロパティを選択して接続

### Google広告データソースの追加

1. 同じ手順で「データソースを追加」
2. 「Google広告」コネクタを選択
3. 対象のGoogle広告アカウントを選択して接続

:::message
BigQuery経由でGA4データを使う場合は、「BigQuery」コネクタでGA4エクスポートテーブルを指定してください。よりカスタマイズ性の高い分析が可能になります。
:::

## ブレンディングの設定手順

### ステップ1: グラフを追加してブレンドデータを選択

1. Looker Studioの編集画面で「グラフを追加」→「表」を選択
2. データソースパネルで「データをブレンド」をクリック
3. ブレンディング設定画面が開く

### ステップ2: 左テーブルにGA4を設定

左テーブル（テーブル1）にGA4データソースを指定し、以下のフィールドを設定します。

- **結合キー**: 日付
- **ディメンション**: 日付、セッションのデフォルトチャネルグループ
- **指標**: セッション、コンバージョン、購入による収益

### ステップ3: 右テーブルにGoogle広告を設定

右テーブル（テーブル2）にGoogle広告データソースを指定します。

- **結合キー**: 日付
- **ディメンション**: 日付
- **指標**: 費用、クリック数、表示回数

### ステップ4: 結合条件を確認

結合キーが「日付」で一致していることを確認し、結合タイプを「左外部結合」に設定します。

## BigQuery経由で結合する方法（推奨）

Looker Studioのブレンディングは手軽ですが、パフォーマンスや柔軟性に限界があります。大規模なデータや複雑な結合条件が必要な場合は、BigQueryでSQLを書いて結合する方が安定します。

### Google広告のデータをBigQueryに取り込む

Google広告のデータをBigQueryに連携するには、BigQuery Data Transferを使います。

1. BigQueryコンソールで「データ転送」→「転送を作成」
2. ソースに「Google Ads」を選択
3. 対象の広告アカウントIDを入力
4. 転送先データセットを指定

転送が完了すると、`p_Campaigns`、`p_AdGroupStats` などのテーブルが自動的に作成されます。

### GA4とGoogle広告を結合するSQL

```sql
WITH ga4_daily AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  GROUP BY
    date
),

ads_daily AS (
  SELECT
    segments_date AS date,
    SUM(metrics_cost_micros / 1000000) AS ad_cost,
    SUM(metrics_clicks) AS ad_clicks,
    SUM(metrics_impressions) AS ad_impressions
  FROM
    `project.dataset.p_CampaignStats_XXXXXXX`
  GROUP BY
    date
)

SELECT
  g.date,
  g.sessions,
  g.purchases,
  g.revenue,
  a.ad_cost,
  a.ad_clicks,
  a.ad_impressions,
  SAFE_DIVIDE(g.revenue, a.ad_cost) AS roas,
  SAFE_DIVIDE(a.ad_cost, g.purchases) AS cpa
FROM
  ga4_daily g
LEFT JOIN
  ads_daily a ON g.date = a.date
ORDER BY
  g.date DESC;
```

このクエリをBigQueryのビューとして保存し、Looker Studioから接続すれば、ROASやCPAが自動で計算された状態でダッシュボードに表示できます。

## ダッシュボードの構成例

結合データを使って、以下のようなダッシュボードを構成できます。

### 上段: KPIスコアカード

| 指標 | 表示内容 |
|---|---|
| 広告費用 | 期間合計の広告費 |
| ROAS | 収益 ÷ 広告費 |
| CPA | 広告費 ÷ コンバージョン数 |
| 収益 | GA4の購入収益 |

### 中段: 時系列チャート

- X軸: 日付
- Y軸（左）: 広告費用、収益
- Y軸（右）: ROAS

折れ線グラフと棒グラフの複合チャートにすると、費用と効果の関係が直感的にわかります。

### 下段: キャンペーン別の内訳テーブル

キャンペーン単位で結合する場合は、UTMパラメータやキャンペーン名を結合キーに追加します。

## ブレンディングの注意点

### 結合キーのデータ型を揃える

GA4の日付が文字列型（`20260330`）で、Google広告の日付が`DATE`型の場合、結合がうまくいきません。BigQuery側で型を揃えてからLooker Studioに渡すのが安全です。

### ブレンディングではフィルタの挙動が変わる

ブレンドされたデータに対するフィルタは、結合後のデータに適用されます。個々のデータソースへのフィルタはブレンド前に適用する必要があるため、設定画面で「データソースフィルタ」を使い分けてください。

### サンプリングに注意する

GA4コネクタは大量データに対してサンプリングが発生する場合があります。正確な数値が必要な場合は、BigQueryコネクタを使ってください。

## まとめ

GA4と広告データの結合は、広告投資の効果を正しく評価するために不可欠な分析です。

- **手軽に始めるなら**: Looker Studioのブレンディング機能で日付キー結合
- **正確性・パフォーマンスを重視するなら**: BigQueryでSQLを書いてビュー化

どちらの方法でも、ROASやCPAをダッシュボード上でリアルタイムに確認できる環境が構築できます。まずはブレンディングで試してみて、データ量が増えてきたらBigQuery移行を検討するのが現実的な進め方です。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
