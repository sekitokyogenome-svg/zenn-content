---
title: "BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した"
emoji: "📈"
type: "idea"
topics: ["lookerstudio","bigquery","ec"]
published: false
---

## はじめに

「月末になると、GA4を開いてスプレッドシートに数字を転記して、グラフを作り直して、メールで共有する」という作業を毎月繰り返していないでしょうか。

私はある中小EC事業者のデータ基盤を構築する案件で、この月次レポート作成作業を完全に自動化しました。BigQueryでデータを集計し、Looker Studioでダッシュボード化することで、毎月半日かかっていたレポート作成がゼロになりました。

この記事では、実際にどのような設計で自動化したのか、その手順と工夫を共有します。

## 自動化前の状態

自動化前のレポート作成フローは以下のようなものでした。

1. GA4の管理画面にログイン
2. 月初〜月末の日付を指定してデータを表示
3. セッション数、売上、CVRなどをExcelに転記
4. Google広告の管理画面にログイン
5. 広告費、ROAS、CPAをExcelに転記
6. Excel上でグラフを作成・更新
7. メールに添付して関係者に送信

この作業にかかっていた時間は、毎月約4時間。年間にすると約48時間です。

## 自動化後のアーキテクチャ

```
[GA4]  → BigQueryエクスポート → [BigQuery staging] → [BigQuery mart]
[Google Ads] → BigQuery Data Transfer ↗

[BigQuery mart] → Looker Studio → 自動メール配信
```

データの流れはすべて自動化されており、人手が介入するポイントはありません。Looker Studioのダッシュボードは常に最新のデータを表示し、月次レポートは毎月1日に自動配信されます。

## ステップ1: BigQueryのデータマートを設計する

### 3層アーキテクチャ

```
raw層:    GA4エクスポートテーブル（events_*）、Google広告テーブル
staging層: イベントデータの正規化・セッション単位の集約
mart層:   KPI集計（月次、日次、チャネル別）
```

### mart層のKPIビュー

```sql
CREATE OR REPLACE VIEW `project.dataset.mart_monthly_kpi` AS
WITH sessions AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    user_pseudo_id,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    device.category AS device,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase' THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM
    `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH))
  GROUP BY
    month, session_id, user_pseudo_id, source, medium, device
)

SELECT
  month,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  SUM(has_purchase) AS purchases,
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT session_id)) AS cvr,
  SAFE_DIVIDE(SUM(revenue), COUNT(DISTINCT session_id)) AS revenue_per_session,
  SAFE_DIVIDE(SUM(revenue), SUM(has_purchase)) AS avg_order_value
FROM
  sessions
GROUP BY
  month
ORDER BY
  month DESC
```

### 広告データとの統合ビュー

```sql
CREATE OR REPLACE VIEW `project.dataset.mart_monthly_kpi_with_ads` AS
SELECT
  kpi.month,
  kpi.sessions,
  kpi.users,
  kpi.purchases,
  kpi.revenue,
  kpi.cvr,
  kpi.revenue_per_session,
  kpi.avg_order_value,
  ads.ad_cost,
  SAFE_DIVIDE(kpi.revenue, ads.ad_cost) AS roas,
  SAFE_DIVIDE(ads.ad_cost, kpi.purchases) AS cpa
FROM
  `project.dataset.mart_monthly_kpi` kpi
LEFT JOIN (
  SELECT
    DATE_TRUNC(segments_date, MONTH) AS month,
    SUM(metrics_cost_micros / 1000000) AS ad_cost
  FROM
    `project.dataset.p_CampaignStats_XXXXXXX`
  GROUP BY month
) ads ON kpi.month = ads.month
```

## ステップ2: Looker Studioのダッシュボードを構築する

### ページ構成

| ページ | 内容 |
|---|---|
| 1. サマリー | 月次KPIのスコアカード＋前月比 |
| 2. トレンド | 月別の売上・セッション推移 |
| 3. チャネル分析 | チャネル別のセッション・売上・CVR |
| 4. 広告パフォーマンス | ROAS・CPA・広告費の推移 |
| 5. 商品分析 | カテゴリ別・商品別の売上 |

### サマリーページの設計

```
┌────────────────────────────────────────────┐
│         EC月次KPIレポート - 2026年2月         │
├──────┬──────┬──────┬──────┬──────┬──────┤
│ 売上  │ 注文数 │ CVR  │ AOV  │ROAS │ CPA  │
│¥2.1M │ 234件 │2.8% │¥8.9K │ 3.2 │¥4.5K │
│+15%  │+12%  │+0.3p │+2%  │+0.5 │-¥800 │
├──────┴──────┴──────┴──────┴──────┴──────┤
│                                            │
│  [月別売上推移 - 棒グラフ + 前年同月の線]     │
│                                            │
├────────────────────┬───────────────────────┤
│ [チャネル別売上]     │ [デバイス別セッション]  │
│  円グラフ            │  円グラフ              │
└────────────────────┴───────────────────────┘
```

### 日付フィルタのデフォルト設定

月次レポートなので、デフォルトの日付範囲を「先月」に設定します。

1. 日付コントロールを選択
2. 「デフォルトの日付範囲」→「詳細設定」
3. 開始日: 月の初日からの1か月前 / 終了日: 月の初日からの1日前

これにより、ダッシュボードを開くと自動的に先月のデータが表示されます。

## ステップ3: 自動配信を設定する

### Looker Studio標準のメール配信

1. レポートの閲覧モードで「共有」→「メール配信のスケジュール」
2. 宛先: 経営者、マーケティング担当者のメールアドレス
3. 繰り返し: 毎月（月の第1営業日）
4. 時刻: 午前10:00

### 配信メールの改善ポイント

標準の配信メールだけでなく、GASでKPIサマリーを本文に記載するスクリプトも追加しました。メールを開いただけで先月の主要数値がわかるようにしています。

```
件名: 【EC月次レポート】2月売上 ¥2,100,000（前月比+15%）

本文:
2月のEC KPIサマリー
=====================
売上: ¥2,100,000（前月比 +15%）
注文数: 234件（前月比 +12%）
CVR: 2.8%（前月比 +0.3pt）
ROAS: 3.2（前月比 +0.5）

詳細レポート: [Looker Studioリンク]
```

## 自動化による効果

### 定量的な効果

| 項目 | 自動化前 | 自動化後 |
|---|---|---|
| レポート作成時間 | 月4時間 | 0時間 |
| データの鮮度 | 月1回更新 | リアルタイム |
| レポート配信 | メール手動送信 | 自動配信 |
| 過去データの参照 | Excel探し | ダッシュボードで即時 |

### 定性的な効果

- 経営者がいつでも最新のKPIを確認できるようになった
- 「先月の売上は？」という質問に即座に回答できるようになった
- レポート作成の属人化が解消された
- データの転記ミスがなくなった

## 構築時のつまずきポイント

### GA4のBigQueryエクスポートが遅延する

GA4からBigQueryへのデータエクスポートは、通常1日遅れで反映されます。月次レポートの配信日を「毎月2日」に設定して、前月末のデータが確実に反映されるようにしました。

### 広告データの粒度が合わない

GA4のデータとGoogle広告のデータでは、コンバージョンの定義やカウント方法が異なります。レポート上で「GA4ベースの売上」「広告管理画面ベースのコンバージョン」と明記し、混同を防いでいます。

### ダッシュボードの読み込みが遅い

初期構築時は、Looker Studioからevents_*テーブルを直接クエリしていたため、読み込みに30秒以上かかっていました。mart層のビューを作成し、さらにBI Engineを有効化することで、3秒以内に改善しました。

## 今後の拡張予定

- **異常検知の自動通知**: 売上が前月比-20%以下になった場合にSlack通知
- **コホート分析の追加**: 初回購入月ごとのリピート率をレポートに追加
- **予測値の表示**: 過去トレンドから月末着地見込みを表示

## まとめ

BigQuery × Looker Studioによる月次KPIレポートの自動化は、構築に1〜2日かかりますが、その後の運用工数はほぼゼロになります。

- **BigQuery**: 3層アーキテクチャでデータを整理し、KPIの集計ロジックをSQLに集約
- **Looker Studio**: 見やすいダッシュボードを構築し、日付フィルタで任意の期間を参照可能に
- **自動配信**: 標準機能やGASで定期的にレポートを届ける

「レポートは作るものではなく、届くもの」に変えることで、データドリブンな意思決定が自然と根付いていきます。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
