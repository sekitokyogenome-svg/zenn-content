---
title: "BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する"
emoji: "📊"
type: "tech"
topics: ["bigquery","machinelearning","ec","sql","googlecloud"]
published: true
---

## はじめに

「来週の売上、だいたいいくらになるだろう？」——ECを運営していると、在庫の手配や広告予算の調整のために、こうした予測が必要になる場面は少なくありません。感覚や過去の経験をもとに判断しているケースも多いと思いますが、データに基づいた予測ができれば、意思決定の精度を上げる一助になります。

かつて売上予測といえば、統計の専門知識や高価なBIツールが必要でした。しかし現在は、Google CloudのBigQuery MLを使うことで、SQLに近い感覚で時系列予測モデルを構築できるようになっています。特に`ARIMA_PLUS`という時系列モデルは、季節性や傾向を自動で検出してくれるため、パラメータ調整の手間が大幅に少なくなっています。

この記事では、GA4のBigQueryエクスポートデータをもとに週次の売上データを集計し、BigQuery MLの`ARIMA_PLUS`モデルで今後数週間の売上を予測する手順をご紹介します。SQLの基本的な読み書きができる方であれば、機械学習の専門知識がなくても試せる内容を心がけました。

---

## ARIMA_PLUSとは何か

`ARIMA_PLUS`は、BigQuery MLが提供する時系列予測モデルです。ARIMA（自己回帰和分移動平均）をベースとしつつ、以下のような機能が自動で組み込まれています。

- **季節性の自動検出**: 週次・月次といった繰り返しパターンを自動で認識します
- **ホリデー効果の組み込み**: 日本の祝日などの特殊な需要変動を考慮できます
- **外れ値の処理**: スパイク状の異常値が予測精度に悪影響を与えにくい設計になっています
- **複数モデルの自動選定**: 内部で複数のパラメータ候補を試し、精度の高いものを選んでくれます

これらをすべて自前で実装しようとすると相当な手間がかかりますが、`ARIMA_PLUS`はSQLのクエリを数行書くだけで利用できます。ECの週次・月次売上予測に非常に向いたモデルといえます。

---

## ステップ1: GA4データから週次売上を集計する

まず、GA4のBigQueryエクスポートテーブルから、週ごとの売上金額（purchase イベントのrevenue）を集計します。

:::message
GA4のBigQueryエクスポートでは、`ga_session_id`などのパラメータは`event_params`配列の中に格納されています。直接カラムとして参照することはできないため、`UNNEST`で展開する必要があります。
:::

```sql
-- 週次売上集計（GA4 BigQueryエクスポートを使用）
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  SUM(
    (SELECT COALESCE(ep.value.double_value, ep.value.int_value)
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS weekly_revenue
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  week_start
ORDER BY
  week_start ASC;
```

`your_project.analytics_XXXXXXXX` の部分はご自身のプロジェクトIDとGA4プロパティIDに合わせて書き換えてください。`value` パラメータにはpurchaseイベントの売上金額が入っています。

また、流入元ごとに売上を分けて分析したい場合は、`collected_traffic_source` を使います。

```sql
-- 流入元別の週次売上集計
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(
    (SELECT COALESCE(ep.value.double_value, ep.value.int_value)
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS weekly_revenue
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  week_start, medium, source
ORDER BY
  week_start ASC;
```

上記のクエリ結果をBigQueryのテーブルとして保存しておくと、次のモデル学習ステップがスムーズになります。

---

## ステップ2: ARIMA_PLUSモデルを学習させる

集計した週次売上データをもとに、`ARIMA_PLUS`モデルを作成します。`CREATE MODEL`構文を使うだけで、モデルの学習まで自動で行われます。

```sql
CREATE OR REPLACE MODEL
  `your_project.your_dataset.ec_weekly_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'week_start',
  time_series_data_col = 'weekly_revenue',
  data_frequency = 'WEEKLY',
  horizon = 8,
  holiday_region = 'JP'
) AS
SELECT
  week_start,
  weekly_revenue
FROM
  `your_project.your_dataset.weekly_revenue_summary`
WHERE
  weekly_revenue IS NOT NULL;
```

各オプションの意味は次のとおりです。

| オプション | 設定値 | 意味 |
|---|---|---|
| `model_type` | `ARIMA_PLUS` | 時系列予測モデルを指定 |
| `data_frequency` | `WEEKLY` | 週次データであることを明示 |
| `horizon` | `8` | 8週先まで予測する |
| `holiday_region` | `JP` | 日本の祝日を考慮する |

`horizon`の値は予測したい期間に合わせて調整してください。四半期先まで見たい場合は`13`程度が目安になります。

:::message
モデルの学習には数分かかる場合があります。BigQueryコンソールのジョブ履歴からステータスを確認できます。
:::

---

## ステップ3: 予測結果を取得する

モデルが学習できたら、`ML.FORECAST`関数で将来の売上を予測します。

```sql
SELECT
  forecast_timestamp AS week_start,
  ROUND(forecast_value, 0) AS predicted_revenue,
  ROUND(prediction_interval_lower_bound, 0) AS lower_bound,
  ROUND(prediction_interval_upper_bound, 0) AS upper_bound
FROM
  ML.FORECAST(
    MODEL `your_project.your_dataset.ec_weekly_forecast_model`,
    STRUCT(8 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp ASC;
```

`confidence_level = 0.9` は「90%の確率でこの範囲に収まる」という予測区間を意味します。予測値の一点だけでなく、上限・下限の幅も把握することで、楽観・悲観シナリオを合わせて検討できます。

結果はLooker Studioと接続すると、週次でグラフとして可視化することも容易です。BigQueryのテーブルとして保存してからLooker Studioのデータソースとして追加するだけで、予測折れ線グラフを含むダッシュボードを構築できます。

---

## ステップ4: 予測精度を評価する

予測モデルを実運用に使う前に、過去データに対する精度を確認しておくと安心です。`ML.EVALUATE`を使うと評価指標を確認できます。

```sql
SELECT
  mean_absolute_error,
  mean_squared_error,
  root_mean_squared_error,
  mean_absolute_percentage_error,
  symmetric_mean_absolute_percentage_error
FROM
  ML.EVALUATE(MODEL `your_project.your_dataset.ec_weekly_forecast_model`);
```

注目したいのは `mean_absolute_percentage_error`（MAPE）です。これは「実際の値に対して平均何%ズレているか」を示す指標で、たとえば値が`0.15`であれば平均15%の誤差があることを意味します。業種・商品特性によって許容できる誤差の幅は異なりますが、ECの週次予測では20〜30%以内であれば傾向把握には十分活用できるケースが多いです。

精度が想定より低い場合は、以下を見直してみてください。

- 学習データ期間が短すぎないか（最低でも1年分、できれば2年分以上が望ましい）
- セール期間や特殊イベントの影響が大きく出ていないか
- 商品カテゴリや流入元でセグメントを分けて別モデルにする必要がないか

---

## まとめ

BigQuery MLの`ARIMA_PLUS`を使うと、以下のようなフローでEC売上の週次予測が実現できます。

1. GA4のBigQueryエクスポートから週次売上を集計する
2. `CREATE MODEL`でARIMA_PLUSモデルを学習させる
3. `ML.FORECAST`で今後数週間の予測値と予測区間を取得する
4. `ML.EVALUATE`でモデルの精度を確認する

専用の分析ツールや複雑なPythonコードを書かずとも、SQLの延長線上で時系列予測が手軽に試せる点がBigQuery MLの大きな利点です。予測結果をLooker Studioで可視化すれば、非エンジニアのスタッフやクライアントへの共有も容易になります。

まずは手元のGA4データで週次集計のクエリを試してみることから始めてみてください。データの傾向が見えてきたら、モデルの学習まで一歩進めてみましょう。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
