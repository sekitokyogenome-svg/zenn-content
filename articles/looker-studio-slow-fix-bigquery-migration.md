---
title: "Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した"
emoji: "⚡"
type: "idea"
topics: ["lookerstudio", "bigquery", "performance"]
published: false
---

## はじめに

「Looker Studioのダッシュボードが重すぎて、毎朝の数値確認がストレスになっている」

GA4のネイティブコネクタでLooker Studioを使っている方なら、一度はこの問題にぶつかったことがあるのではないでしょうか。ページを開くたびに30秒以上待たされる。フィルタを変えるたびにまた待つ。期間を変更するとタイムアウトする。

自分もまさにこの状況でした。クライアントに共有しているダッシュボードが遅すぎて「このレポート、使いにくいです」と言われたこともあります。

この記事では、データソースをGA4コネクタからBigQueryに切り替えることで、Looker Studioの表示速度を大幅に改善した方法を共有します。

---

## なぜGA4コネクタは遅いのか

GA4のネイティブコネクタが遅い原因は、主に3つあります。

### 1. 毎回生データを処理している

GA4コネクタはダッシュボードを開くたびに、GA4側の生データに対してクエリを実行します。事前に集計されたデータを返しているわけではないため、データ量が増えるほど処理時間が伸びます。

### 2. サンプリングがかかる

一定以上のデータ量になると、GA4はサンプリング（データの一部だけを使った推計）を適用します。速度の問題だけでなく、数値の正確性にも影響が出ます。

### 3. タイムアウトの制限

GA4コネクタには処理時間の上限があります。複雑なフィルタや長い期間を指定すると、タイムアウトでデータが表示されないことがあります。

:::message alert
GA4コネクタで「データセットが大きすぎます」や「リクエストがタイムアウトしました」というエラーが出る場合、GA4側の制限に引っかかっています。コネクタの設定を変えても根本的な解決にはなりません。
:::

---

## 解決策：データソースをBigQueryのマートテーブルに切り替える

GA4コネクタの代わりに、BigQueryで事前に集計したマートテーブルをデータソースにします。

仕組みはシンプルです。

1. GA4のデータをBigQueryにエクスポートする（GA4管理画面から設定可能）
2. BigQuery上で日別サマリーなどの集計テーブル（マートテーブル）を作る
3. Looker Studioのデータソースをそのマートテーブルに差し替える

これだけで、Looker Studioが参照するデータ量が大幅に減り、表示速度が改善します。

---

## Before / After：実際の改善結果

データソースをGA4コネクタからBigQueryマートテーブルに切り替えた結果です。

| 項目 | GA4コネクタ（Before） | BigQueryマート（After） |
|------|----------------------|------------------------|
| 初回ロード時間 | 30〜60秒 | 3〜5秒 |
| フィルタ変更時 | 15〜30秒 | 1〜3秒 |
| サンプリング | あり（データ量次第） | なし（全件集計済み） |
| タイムアウト | 頻発 | ほぼ発生しない |
| 長期間の指定 | エラーになることがある | 問題なし |

自分のケースでは体感で大幅に速くなりました。クライアントからも「見やすくなった」と好評でした。

---

## マートテーブルの作り方：日別サマリーの例

GA4の生データ（`events_*`テーブル）から、日別のサマリーテーブルを作成するSQLの例です。

```sql
CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,

  -- セッション数
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,

  -- ユーザー数
  COUNT(DISTINCT user_pseudo_id) AS users,

  -- PV数
  COUNTIF(event_name = 'page_view') AS page_views,

  -- コンバージョン数
  COUNTIF(event_name = 'purchase') AS conversions,

  -- 収益
  SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS revenue

FROM `your_project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1, 2, 3, 4
```

:::message
`PARTITION BY event_date` を指定しておくと、Looker Studio側で期間フィルタを使ったときにスキャン量が最小限になり、コストと速度の両方が改善します。
:::

このSQLをスケジュールクエリ（BigQueryのScheduled Query機能）で毎日自動実行すれば、手動作業なしでマートテーブルが最新状態に保たれます。

---

## Looker StudioのデータソースをBigQueryに差し替える

既存のダッシュボードのデータソースを差し替える手順です。

1. Looker Studio →「リソース」→「追加済みのデータソースの管理」
2. GA4コネクタのデータソースを編集
3. コネクタを「BigQuery」に変更
4. プロジェクト → データセット（`mart`）→ テーブル（`daily_summary`）を選択
5. フィールドのマッピングを確認し、必要に応じて調整

:::message alert
データソースを切り替えると、既存のグラフで使用しているディメンションや指標のフィールド名が変わる場合があります。切り替え後は各グラフが正しく表示されているか確認してください。
:::

---

## さらなる最適化のポイント

BigQuery化だけでも大幅に改善しますが、さらに速くする方法もあります。

### パーティションとクラスタリング

上記のSQLでは`PARTITION BY event_date`を使いましたが、加えてよく使うディメンションで`CLUSTER BY`を設定すると、クエリ効率がさらに上がります。

```sql
CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
CLUSTER BY source, medium, device_category
AS
-- (上記と同じSELECT文)
```

### Looker Studioのキャッシュ設定

Looker Studioのデータソース設定で「データの更新頻度」を12時間に設定すると、同じクエリの再実行を防げます。日次データであれば十分な頻度です。

### 抽出データソースの活用

Looker Studioの「抽出データソース」機能を使うと、BigQueryから一度データを取得してLooker Studio側にキャッシュします。頻繁に更新する必要のないレポートではこの方法が最も高速です。

---

## コストについて

「BigQueryに切り替えるとコストが上がるのでは？」という懸念はもっともですが、実際にはそこまで大きな負担にはなりません。

- **マートテーブルへのスケジュールクエリ**: 月数百円〜数千円程度（データ量次第）
- **Looker Studioからのクエリ**: マートテーブル参照なのでスキャン量が少なく、月数百円以下が多い
- **ストレージ**: マートテーブルは集計済みのため生データよりはるかに小さい

GA4コネクタの遅さによる業務ストレスや、クライアント満足度の低下を考えると、十分に見合う投資です。

---

## まとめ

Looker Studioが遅い原因の多くは、GA4ネイティブコネクタの構造的な制約にあります。

- GA4コネクタは毎回生データを処理するため遅い
- BigQueryで事前集計したマートテーブルに切り替えると、表示速度が大幅に改善する
- パーティション・キャッシュ設定でさらに最適化できる
- コストは月数千円程度で十分に見合う

「ダッシュボードが遅い」は設定の問題ではなくアーキテクチャの問題です。データソースの構成を見直すだけで、Looker Studioは快適に使えるツールに変わります。

GA4×BigQuery基盤の構築やLooker Studioダッシュボードの高速化について、お気軽にご相談ください。

https://coconala.com/services/419062
