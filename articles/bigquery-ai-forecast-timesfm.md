---
title: "AI.FORECASTとTimesFM — 学習不要で時系列予測する"
emoji: "📈"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "timesfm", "sql"]
published: true
---

## はじめに

シリーズ第14回です。

前回（第13回）では差分エンベディングを自動生成してベクトルインデックスを自動同期するパイプラインを解説しました。今回は **`AI.FORECAST`** と **TimesFM** を使った時系列予測を取り上げます。

売上予測や在庫計画には従来 ARIMA や BigQuery ML の `ARIMA_PLUS` モデルが使われてきました。どちらも「モデルを学習させる」フェーズが必要で、データ量・学習時間・運用コストが課題でした。`AI.FORECAST` は時系列ファンデーションモデル **TimesFM** を用い、**学習なしに予測値を返す**関数です。SQLを1本書くだけで翌日・翌週・翌月の予測が取れます。

:::message
本記事は 2026年9月時点で確認できた情報に基づいています。AI 関数の仕様は更新が速いため、採用前に公式ドキュメントの最新版をご確認ください。
:::

---

## TimesFM とは

TimesFM（Time Series Foundation Model）は Google Research が開発した時系列予測用のファンデーションモデルです。大量の時系列データで事前学習されており、ドメイン固有のデータで追加学習をしなくても幅広い時系列に対して汎用的に機能します。

ARIMA_PLUS と TimesFM の主な違いを整理します。

| 観点 | ARIMA_PLUS | AI.FORECAST（TimesFM）|
|---|---|---|
| 学習フェーズ | 必要（データごとにモデル作成） | 不要（ゼロショット） |
| 前処理の手間 | 欠損値補完・季節性設定が必要 | 最小限 |
| 精度のチューニング | ハイパーパラメータ調整が可能 | 調整の余地は少ない |
| 向いているケース | 精度を追い込みたい長期的な本番運用 | 素早く試したい・中短期予測 |
| BigQuery SQL での実装 | `CREATE MODEL` → `ML.FORECAST` | `AI.FORECAST` 一発 |

「まず予測値を手早く見たい」「学習リソースをかけずにざっくりと将来値を確認したい」という用途に TimesFM は向いています。

---

## 基本構文

```sql
AI.FORECAST(
  MODEL model_name,
  input_query,
  STRUCT(
    horizon           AS horizon,
    confidence_level  AS confidence_level
  )
)
```

| 引数 | 説明 |
|---|---|
| `model_name` | TimesFM のリモートモデルオブジェクト |
| `input_query` | 時系列データを返すサブクエリ |
| `horizon` | 予測するステップ数（整数） |
| `confidence_level` | 予測区間の信頼水準（0.0〜1.0。例：0.9） |

### input_query に必要な列

| 列名 | 型 | 説明 |
|---|---|---|
| `time_series_id` | STRING | 系列を識別するID（商品IDなど） |
| `time_series_timestamp` | TIMESTAMP または DATE | 時刻 |
| `time_series_data` | FLOAT64 | 予測したい値 |

`time_series_id` は複数系列を一括処理する場合に必要です。単一系列でも空文字などを入れて列を合わせてください。

### 戻り値

| 列名 | 型 | 説明 |
|---|---|---|
| `time_series_id` | STRING | 元のID |
| `time_series_timestamp` | TIMESTAMP | 予測対象の時刻 |
| `time_series_data` | FLOAT64 | 予測値（点推定） |
| `prediction_interval_lower_bound` | FLOAT64 | 予測区間の下限 |
| `prediction_interval_upper_bound` | FLOAT64 | 予測区間の上限 |

---

## モデルオブジェクトの作成

`AI.FORECAST` を実行する前に TimesFM のリモートモデルを作成します。

```sql
CREATE OR REPLACE MODEL `your-project.ai_lab.timesfm_model`
REMOTE WITH CONNECTION `your-project.asia-northeast1.vertex-ai-conn`
OPTIONS (
  endpoint = 'timesfm-1.0-200m'
);
```

接続（`vertex-ai-conn`）の作成手順は第2回（IAM・Vertex AI 接続セットアップ）を参照してください。

---

## EC売上の週次予測

過去90日間の日次売上を入力し、今後14日間の予測値を取得する例です。

```sql
WITH daily_sales AS (
  SELECT
    'total' AS time_series_id,
    DATE(order_date)              AS time_series_timestamp,
    SUM(revenue)                  AS time_series_data
  FROM `your-project.your_dataset.orders`
  WHERE
    order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND order_date < CURRENT_DATE()
    AND status != 'cancelled'
  GROUP BY DATE(order_date)
)
SELECT
  time_series_timestamp,
  time_series_data                    AS forecast_revenue,
  prediction_interval_lower_bound     AS lower_bound,
  prediction_interval_upper_bound     AS upper_bound
FROM
  AI.FORECAST(
    MODEL `your-project.ai_lab.timesfm_model`,
    (SELECT * FROM daily_sales),
    STRUCT(14 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY time_series_timestamp;
```

`horizon = 14` で14日先まで予測します。`confidence_level = 0.9` は90%予測区間を計算します。

---

## 商品カテゴリ別の売上予測（複数系列）

`time_series_id` に商品カテゴリを使い、複数系列を一括処理する例です。

```sql
WITH category_daily AS (
  SELECT
    category                          AS time_series_id,
    DATE(order_date)                  AS time_series_timestamp,
    SUM(revenue)                      AS time_series_data
  FROM `your-project.your_dataset.orders`
  WHERE
    order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND order_date < CURRENT_DATE()
    AND status != 'cancelled'
    AND category IS NOT NULL
  GROUP BY category, DATE(order_date)
)
SELECT
  time_series_id AS category,
  time_series_timestamp,
  ROUND(time_series_data, 0)             AS forecast_revenue,
  ROUND(prediction_interval_lower_bound, 0) AS lower_bound,
  ROUND(prediction_interval_upper_bound, 0) AS upper_bound
FROM
  AI.FORECAST(
    MODEL `your-project.ai_lab.timesfm_model`,
    (SELECT * FROM category_daily),
    STRUCT(7 AS horizon, 0.8 AS confidence_level)
  )
ORDER BY time_series_id, time_series_timestamp;
```

複数系列を同時に処理できるため、カテゴリごとに別クエリを実行する手間が省けます。

---

## GA4セッション数の予測

GA4の日次セッション数を予測する例です。`ga_session_id` は `UNNEST(event_params)` で取り出し、流入元は `collected_traffic_source.manual_medium` を使います。

```sql
WITH session_events AS (
  SELECT
    event_date,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    )                                     AS ga_session_id,
    collected_traffic_source.manual_medium AS medium
  FROM `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
),
daily_sessions AS (
  SELECT
    COALESCE(medium, '(none)')            AS time_series_id,
    PARSE_DATE('%Y%m%d', event_date)      AS time_series_timestamp,
    COUNT(DISTINCT ga_session_id)         AS time_series_data
  FROM session_events
  WHERE ga_session_id IS NOT NULL
  GROUP BY medium, event_date
)
SELECT
  time_series_id AS medium,
  time_series_timestamp,
  ROUND(time_series_data, 0)              AS forecast_sessions,
  ROUND(prediction_interval_lower_bound, 0) AS lower_bound,
  ROUND(prediction_interval_upper_bound, 0) AS upper_bound
FROM
  AI.FORECAST(
    MODEL `your-project.ai_lab.timesfm_model`,
    (SELECT * FROM daily_sessions),
    STRUCT(7 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY time_series_id, time_series_timestamp;
```

:::message
GA4 の `ga_session_id` はイベントテーブルに直接カラムとして存在しません。`UNNEST(event_params)` でキー名 `ga_session_id` の値を取り出す必要があります。流入元の取得には `collected_traffic_source.manual_medium` を使ってください。
:::

---

## 予測結果をテーブルに保存してダッシュボード連携する

Looker Studio で予測グラフを表示するためにスケジュールクエリで予測結果を保存します。

```sql
CREATE OR REPLACE TABLE `your-project.your_dataset.sales_forecast_daily` AS
WITH daily_sales AS (
  SELECT
    'total'             AS time_series_id,
    DATE(order_date)    AS time_series_timestamp,
    SUM(revenue)        AS time_series_data
  FROM `your-project.your_dataset.orders`
  WHERE
    order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND order_date < CURRENT_DATE()
    AND status != 'cancelled'
  GROUP BY DATE(order_date)
)
SELECT
  time_series_timestamp         AS forecast_date,
  time_series_data              AS forecast_revenue,
  prediction_interval_lower_bound AS lower_bound,
  prediction_interval_upper_bound AS upper_bound,
  CURRENT_TIMESTAMP()           AS generated_at
FROM
  AI.FORECAST(
    MODEL `your-project.ai_lab.timesfm_model`,
    (SELECT * FROM daily_sales),
    STRUCT(14 AS horizon, 0.9 AS confidence_level)
  );
```

このテーブルをスケジュールクエリで毎朝更新すれば、Looker Studio 側の設定を変えることなく予測値が常に最新化されます。

---

## 精度を検証する：予測値と実績値の照合

前日の予測値と実績値を比較して予測精度を継続的に監視します。

```sql
WITH actuals AS (
  SELECT
    DATE(order_date) AS actual_date,
    SUM(revenue)     AS actual_revenue
  FROM `your-project.your_dataset.orders`
  WHERE
    order_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND status != 'cancelled'
  GROUP BY DATE(order_date)
),
forecasts AS (
  SELECT
    forecast_date,
    forecast_revenue,
    lower_bound,
    upper_bound
  FROM `your-project.your_dataset.sales_forecast_daily`
  WHERE forecast_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
)
SELECT
  a.actual_date,
  a.actual_revenue,
  f.forecast_revenue,
  f.lower_bound,
  f.upper_bound,
  ABS(a.actual_revenue - f.forecast_revenue)
    / NULLIF(a.actual_revenue, 0) AS mape,
  CASE
    WHEN a.actual_revenue BETWEEN f.lower_bound AND f.upper_bound
    THEN TRUE ELSE FALSE
  END AS within_interval
FROM actuals AS a
LEFT JOIN forecasts AS f ON a.actual_date = f.forecast_date;
```

`mape`（平均絶対パーセント誤差）と予測区間カバー率を定期的に確認し、精度が低下したら過去データの範囲を広げるか ARIMA_PLUS への切り替えを検討します。

---

## AI.FORECAST の制約と注意点

### 入力データの要件

- 等間隔のタイムスタンプを想定している（日次・週次・月次）
- 欠損日がある場合は 0 で補完するか、欠損行を除外してから入力する
- 系列が短すぎる（数十点以下）と予測精度が低下しやすい

### 長期予測には向いていない

`horizon` を大きくするほど予測区間が広がり、実用的な精度を保てる期間は限られます。中小 EC の日次データであれば2〜4週間先が現実的な上限の目安です。

### 外部要因を組み込めない

セール開始・広告予算増加・季節イベントなどのスパイクを事前に学習していないため、外部要因による急変を予測には取り込めません。こうした特殊な変動を考慮したい場合は ARIMA_PLUS の `holiday_region` 指定や外部回帰変数を使う方が向いています。

---

## コスト管理

`AI.FORECAST` は呼び出しごとにトークン換算でコストが発生します。

| 対策 | 方法 |
|---|---|
| 系列数を絞る | 全商品SKUではなくカテゴリ単位で予測する |
| 入力期間を適切に設定 | 90〜180日分が実用的。過剰に長くしない |
| 結果をマテリアライズする | 毎クエリ呼ぶのではなくスケジュール結果をテーブル保存 |

日次で1〜数系列を予測する規模であれば月額数百円程度に収まるケースが多いです。系列数が増える場合は事前にクエリプレビューで処理バイト数を確認してください。

---

## まとめ

- `AI.FORECAST` は TimesFM を使い、モデル学習不要でゼロショット時系列予測を行う
- `time_series_id`・`time_series_timestamp`・`time_series_data` の3列を揃えれば動く
- 複数系列を一括処理でき、商品カテゴリ別・流入経路別などの予測に対応できる
- 結果はスケジュールクエリでテーブルに保存してダッシュボード連携するのが基本
- 精度検証は MAPE と予測区間カバー率で定期的に確認する
- 外部要因・長期予測が必要な場合は ARIMA_PLUS が引き続き有力

次回（第15回）は `ObjectRef` を使って画像・PDF などの非構造化データをSQLから扱う方法を解説します。

---

## 参考

- [AI.FORECAST function | BigQuery | Google Cloud Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/ai-functions#ai_forecast)
- [TimesFM overview | Google Cloud](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/timesfm)
- [Forecast time series data by using AI.FORECAST | Google Cloud](https://cloud.google.com/bigquery/docs/forecast-time-series-tutorial)

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
