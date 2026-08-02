---
title: "BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順"
emoji: "📈"
type: "tech"
topics: ["bigquery","machinelearning","ec","googlecloud","sql"]
published: false
---

## はじめに

「季節が変わると売れ筋が変わるのはわかっているのに、いつも仕入れ量が合わない」「売り切れで機会損失が出るか、過剰在庫で資金が眠るかの繰り返し」——そうした悩みを抱えるEC事業者の方は少なくないでしょう。

仕入れ判断をベテランスタッフの経験や勘に頼っている場合、属人化によるリスクも伴います。担当者が変わるたびに精度がブレるという声もよく耳にします。

そこで本記事では、Google Cloudが提供する **BigQuery ML** を活用して、過去の販売データ・サイトアクセスデータをもとに需要予測モデルを構築し、仕入れ計画へ組み込む手順をご紹介します。SQLを中心とした実装なので、Pythonのコーディング経験がない方でも取り組みやすい内容です。

なお、サイトの行動データとして **GA4のBigQueryエクスポート** を活用する部分も含みます。GA4とBigQueryの連携が済んでいることを前提に進めますが、連携手順については末尾のサービスリンクからご相談いただくことも可能です。

---

## BigQuery MLとは何か

BigQuery MLとは、Google BigQueryのSQLインターフェース上で機械学習モデルを構築・学習・予測できる機能です。Pythonや専用のMLフレームワークを別途用意する必要がなく、BigQueryにアクセスできる環境があれば利用できます。

対応しているモデルの種類は多岐にわたりますが、需要予測（時系列予測）には **ARIMA_PLUS** モデルが適しています。このモデルは季節性・トレンド・外れ値を自動で考慮しながら将来の値を推定します。複雑なパラメータ設定を手動で行わなくても、BigQuery MLが内部で最適な設定を探索してくれるため、機械学習の専門知識がなくても導入しやすいのが特徴です。

料金面では、BigQuery MLのモデル学習にはBigQueryのクエリ料金とは別にML料金が発生しますが、中小規模のデータ量であれば月数百円以内に収まるケースがほとんどです。Google Cloudの料金計算ツールで事前に見積もることをおすすめします。

---

## データ準備：GA4のBigQueryエクスポートを活用する

需要予測の精度を上げるためには、単純な売上数量だけでなく、**サイトへの流入データや商品ページの閲覧数** も特徴量として組み合わせることが効果的です。

GA4のBigQueryエクスポートテーブルからは、セッションごとの流入元や商品閲覧イベントを抽出できます。以下のSQLは、日付ごとの商品詳細ページ閲覧数と流入元（メディア）を集計する例です。

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count
FROM
  `your_project.analytics_xxxxxxxxx.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  date, medium, source
ORDER BY
  date;
```

:::message
`ga_session_id` はイベントパラメータの中に格納されているため、`UNNEST(event_params)` を使って取り出す必要があります。カラムとして直接参照することはできません。また、流入元の参照には `traffic_source` ではなく `collected_traffic_source.manual_medium` / `collected_traffic_source.manual_source` を使用してください。
:::

このクエリで取得したデータを、注文管理システムや在庫システムの売上日次データと日付キーで結合することで、モデル学習用のテーブルを作成できます。

---

## ARIMA_PLUSモデルの構築手順

データの準備ができたら、BigQuery MLで時系列予測モデルを構築します。以下は日次販売数量を予測するモデルを作成するSQLです。

```sql
CREATE OR REPLACE MODEL `your_project.your_dataset.demand_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'date',
  time_series_data_col = 'units_sold',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  decompose_time_series = TRUE,
  holiday_region = 'JP'
) AS
SELECT
  date,
  units_sold
FROM
  `your_project.your_dataset.daily_sales_summary`
WHERE
  date BETWEEN '2023-01-01' AND '2024-12-31'
ORDER BY
  date;
```

主なオプションの説明は以下のとおりです。

| オプション | 説明 |
|---|---|
| `auto_arima` | パラメータを自動探索する（TRUE推奨） |
| `data_frequency` | データの粒度（DAILY/WEEKLY/MONTHLY） |
| `decompose_time_series` | トレンド・季節性・残差を分解して学習 |
| `holiday_region` | 祝日の影響を考慮する国コード |

日本のECであれば `holiday_region = 'JP'` を指定することで、年末年始・ゴールデンウィーク・お盆などの特需を考慮した予測が得られます。

モデルの構築が完了したら、`ML.EVALUATE` でモデルの評価指標を確認しましょう。

```sql
SELECT *
FROM ML.EVALUATE(MODEL `your_project.your_dataset.demand_forecast_model`);
```

`mean_absolute_percentage_error`（MAPE）が低いほど予測精度が高い傾向にあります。目安として10〜20%以内であれば、仕入れ計画への活用に耐えうる精度といえるでしょう。

---

## 予測結果を仕入れ計画に反映する

モデルの評価が完了したら、`ML.FORECAST` で将来の需要を予測します。以下は今後30日分の販売数量を予測するクエリです。

```sql
SELECT
  forecast_timestamp,
  forecast_value,
  prediction_interval_lower_bound,
  prediction_interval_upper_bound
FROM
  ML.FORECAST(
    MODEL `your_project.your_dataset.demand_forecast_model`,
    STRUCT(30 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp;
```

`forecast_value` が予測販売数量、`prediction_interval_lower_bound` と `upper_bound` がそれぞれ信頼区間の下限・上限です。

仕入れ計画への活用では、以下のような考え方が一般的です。

- **通常仕入れ量の目安**：`forecast_value` × リードタイム日数 + 安全在庫
- **欠品リスクを抑えたい場合**：`prediction_interval_upper_bound` を基準に仕入れ量を設定
- **過剰在庫を避けたい場合**：`forecast_value` に近い値で仕入れを計画し、短サイクルで補充発注

予測結果をLooker Studioと連携させると、発注担当者が毎日ダッシュボードで確認できる仕組みを構築できます。BigQueryをデータソースとしてLooker Studioに接続し、折れ線グラフで実績と予測を重ねて表示すると、仕入れ判断の根拠として活用しやすくなります。

:::message
予測値はあくまで過去データのパターンをもとにした推計です。新商品の投入・競合の価格変動・SNSでのバズなど、過去にないイベントが発生した際は予測から外れることがあります。予測をベースにしつつも、定性的な情報と組み合わせて判断することをおすすめします。
:::

---

## モデルの定期更新と運用のポイント

需要予測モデルは構築して終わりではなく、データが蓄積されるにつれて定期的に再学習させることで精度を維持できます。Cloud Schedulerを使ってBigQueryジョブを定期実行することで、月次・週次での自動更新が可能です。

```bash
# BigQueryジョブをスケジュール実行するCloud Schedulerの例
gcloud scheduler jobs create http demand-forecast-retrain \
  --schedule="0 3 1 * *" \
  --uri="https://bigquery.googleapis.com/bigquery/v2/projects/YOUR_PROJECT/jobs" \
  --message-body='{"configuration":{"query":{"query":"CREATE OR REPLACE MODEL ..."}}}' \
  --oauth-service-account-email=YOUR_SA@YOUR_PROJECT.iam.gserviceaccount.com
```

また、MAPE等の評価指標を定期的にモニタリングし、精度が一定水準を下回ったタイミングで人の目でデータを確認する運用フローを設けておくと安心です。

---

## まとめ

本記事では、BigQuery MLのARIMA_PLUSモデルを使った需要予測の実装手順をご紹介しました。要点を整理すると以下のとおりです。

- **BigQuery MLはSQLで機械学習モデルを構築できるサービス**であり、専門的なMLの知識がなくても取り組める
- **GA4のBigQueryエクスポートデータ** を組み合わせることで、流入状況も踏まえた予測の精度向上が期待できる
- `ga_session_id` の取得には `UNNEST(event_params)` を使用し、流入元には `collected_traffic_source.manual_medium` / `manual_source` を参照する
- **ARIMA_PLUS** モデルは季節性・祝日（`holiday_region = 'JP'`）を考慮した日本のEC向けの予測に適している
- 予測結果は `ML.FORECAST` で取得し、信頼区間を活用して欠品リスクと過剰在庫のバランスを取った仕入れ計画を立てられる
- モデルは定期的に再学習させ、精度をモニタリングする運用フローを設けることが重要

次のアクションとしては、まず自社の日次販売データを整理してBigQueryに格納し、小規模な期間でテスト的にモデルを構築してみることをおすすめします。精度を確認しながら段階的に本番運用へ移行していくアプローチが現実的です。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
