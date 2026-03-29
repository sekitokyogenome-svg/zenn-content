---
title: "BigQueryでEC季節商品の売上予測モデルを作った話"
emoji: "📈"
type: "tech"
topics: ["bigquery", "ec", "machinelearning"]
published: false
---

## EC運営者の悩み: 「来月の発注量、どうする？」

季節性のある商品を扱うECサイトにとって、在庫管理は永遠の課題です。

- クリスマス商品を多めに仕入れたのに売れ残った
- 夏物が予想以上に売れて在庫切れを起こした
- 「去年と同じくらい」で発注して痛い目にあった

過去の勘と経験に頼った発注判断から脱却するために、BigQuery ML（BQML）を使った売上予測モデルの構築方法を紹介します。SQLだけで機械学習モデルを作成・評価できるため、Pythonの機械学習ライブラリを使う必要はありません。

## BigQuery MLとは

BigQuery ML（BQML）は、BigQuery上でSQLを使って機械学習モデルを作成・トレーニング・予測できる機能です。以下のモデルタイプが利用可能です。

| モデルタイプ | 用途 |
|-------------|------|
| LINEAR_REG | 線形回帰（売上金額の予測） |
| ARIMA_PLUS | 時系列予測（トレンド+季節性） |
| LOGISTIC_REG | 二項分類（購入/非購入の予測） |
| KMEANS | クラスタリング（顧客セグメンテーション） |

今回は、季節商品の売上予測に適した `ARIMA_PLUS` モデルを中心に解説します。

## Step 1: 日別売上データの準備

まず、予測モデルのインプットとなる日別売上データを用意します。

```sql
CREATE OR REPLACE TABLE `beeracle.beeracle_mart.daily_sales` AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS sale_date,
  SUM(ecommerce.purchase_revenue) AS daily_revenue,
  COUNT(DISTINCT user_pseudo_id) AS unique_buyers,
  COUNT(*) AS transaction_count
FROM
  `beeracle.analytics_263425816.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20251231'
  AND event_name = 'purchase'
  AND ecommerce.purchase_revenue > 0
GROUP BY sale_date
ORDER BY sale_date
```

時系列モデルの精度を上げるには、少なくとも1年分（理想的には2年分以上）のデータが必要です。季節パターンを学習させるためです。

## Step 2: ARIMA_PLUSモデルの作成

ARIMA_PLUSは、BigQuery MLが提供する時系列予測モデルです。トレンド・季節性・祝日効果を自動的に検出してモデルに組み込みます。

```sql
CREATE OR REPLACE MODEL `beeracle.beeracle_mart.sales_forecast_model`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT
  sale_date,
  daily_revenue
FROM
  `beeracle.beeracle_mart.daily_sales`
WHERE
  sale_date BETWEEN '2024-01-01' AND '2025-12-31'
```

ポイントは以下の通りです。

- `auto_arima = TRUE`: 最適なARIMAパラメータ（p, d, q）を自動選択
- `data_frequency = 'DAILY'`: 日次データとして処理
- `holiday_region = 'JP'`: 日本の祝日効果をモデルに組み込む

## Step 3: モデルの評価

作成したモデルの精度を確認します。

```sql
SELECT
  *
FROM
  ML.ARIMA_EVALUATE(MODEL `beeracle.beeracle_mart.sales_forecast_model`)
```

主要な評価指標の意味は以下の通りです。

| 指標 | 意味 | 目安 |
|------|------|------|
| AIC | 赤池情報量基準（低いほど良い） | 相対比較に使用 |
| variance | 残差の分散 | 低いほど良い |
| log_likelihood | 対数尤度 | 高いほど良い |
| seasonal_periods | 検出された季節周期 | 7（週次）、365（年次）など |

## Step 4: 売上予測の実行

今後90日間の売上を予測します。

```sql
SELECT
  forecast_timestamp AS predicted_date,
  forecast_value AS predicted_revenue,
  prediction_interval_lower_bound AS lower_bound,
  prediction_interval_upper_bound AS upper_bound
FROM
  ML.FORECAST(
    MODEL `beeracle.beeracle_mart.sales_forecast_model`,
    STRUCT(90 AS horizon, 0.95 AS confidence_level)
  )
ORDER BY forecast_timestamp
```

`confidence_level = 0.95` は95%信頼区間を意味します。`lower_bound` と `upper_bound` の間に95%の確率で実際の値が収まると予測されます。

## Step 5: 予測精度の検証（バックテスト）

モデルの実用性を評価するために、過去データでバックテストを行います。学習データを2024年1月〜2025年9月に制限し、2025年10月〜12月の予測値と実績値を比較します。

```sql
-- 学習用モデル（バックテスト用）
CREATE OR REPLACE MODEL `beeracle.beeracle_mart.sales_forecast_backtest`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT sale_date, daily_revenue
FROM `beeracle.beeracle_mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-09-30';

-- 予測と実績の比較
WITH forecast AS (
  SELECT
    forecast_timestamp AS predicted_date,
    forecast_value AS predicted_revenue
  FROM ML.FORECAST(
    MODEL `beeracle.beeracle_mart.sales_forecast_backtest`,
    STRUCT(92 AS horizon, 0.95 AS confidence_level)
  )
),
actual AS (
  SELECT
    sale_date,
    daily_revenue AS actual_revenue
  FROM `beeracle.beeracle_mart.daily_sales`
  WHERE sale_date BETWEEN '2025-10-01' AND '2025-12-31'
)
SELECT
  a.sale_date,
  a.actual_revenue,
  f.predicted_revenue,
  ROUND(ABS(a.actual_revenue - f.predicted_revenue) / a.actual_revenue * 100, 1) AS error_pct
FROM actual a
INNER JOIN forecast f
  ON a.sale_date = DATE(f.predicted_date)
ORDER BY a.sale_date
```

## 線形回帰モデルとの比較

季節性に加えて、曜日や広告出稿量などの外部要因を考慮したい場合は、線形回帰モデルも選択肢になります。

```sql
CREATE OR REPLACE MODEL `beeracle.beeracle_mart.sales_linear_model`
OPTIONS (
  model_type = 'LINEAR_REG',
  input_label_cols = ['daily_revenue']
) AS
SELECT
  daily_revenue,
  EXTRACT(MONTH FROM sale_date) AS month,
  EXTRACT(DAYOFWEEK FROM sale_date) AS day_of_week,
  CASE
    WHEN EXTRACT(MONTH FROM sale_date) IN (12, 1, 7, 8) THEN 1
    ELSE 0
  END AS is_peak_season,
  unique_buyers,
  transaction_count
FROM `beeracle.beeracle_mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-12-31'
```

線形回帰モデルは解釈性が高く、「どの要因が売上に影響しているか」を把握しやすいメリットがあります。一方、時系列のトレンドや自己相関は考慮されないため、ARIMA_PLUSと比較して精度が劣るケースが多いです。

## 予測結果の活用方法

予測モデルの出力を実務に活かすには、以下のような運用フローが効果的です。

**在庫発注への活用**

予測値の上限（upper_bound）を基準に安全在庫を設定します。信頼区間の幅が広い時期は、需要の不確実性が高い時期と解釈できるため、在庫バッファを厚めに持つ判断ができます。

**予算策定への活用**

月次の売上予測を集計し、四半期・年次の予算策定に活用できます。予測値はあくまで「現状の延長線上」の数値であるため、施策効果の上乗せは別途見積もる必要があります。

**異常検知への活用**

予測値と実績値の乖離が信頼区間を大きく超えた場合、何らかの異常（サイト障害、大口キャンセル、外部要因など）が発生した可能性を示すアラートとして活用できます。

## BQMLの制約と注意点

BigQuery MLは手軽に使える反面、以下の制約を理解しておく必要があります。

- モデルのチューニング自由度はPythonの機械学習ライブラリほど高くない
- 特徴量エンジニアリングの柔軟性に限界がある
- モデルの保存期間やクエリコストに注意が必要
- 予測精度は入力データの量と質に大きく依存する

## まとめ

BigQuery MLを使えば、SQLの知識だけでEC売上の予測モデルを構築できます。ARIMA_PLUSモデルは季節性の自動検出機能を備えており、季節商品の需要予測に適しています。

まずは自社の日別売上データでモデルを作成し、バックテストで精度を確認するところから始めてみてください。予測精度が十分でない場合は、データ期間を延ばす、外部データ（天候・イベント情報）を追加するなどの改善策を検討できます。

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
