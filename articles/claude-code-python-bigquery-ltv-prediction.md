---
title: "Claude Code × Python × BigQueryでLTV予測モデルを作った"
emoji: "🔮"
type: "tech"
topics: ["claudecode","bigquery","machinelearning"]
published: true
---

:::message
2026-10-10 に、コードの誤りと古い記述を修正しました。変更点: (0) 動作確認の範囲（BG/NBD の fit まで）の明記、特徴量の窓の長さの統一、`predicted_ltv` が初回購入額を含まない点の明記 (1) 回帰モデルを「観測期間の特徴量 → 将来期間の購入額」に作り直し、目的変数のリークを解消 (2) BG/NBD を 1回購入者を含む全顧客で学習し、検証に `calibration_and_holdout_data` を使う形に変更。`lifetimes` がアーカイブ済みである点も追記 (3) CPA上限の式と数値の食い違い、SQLの結合の重複、レポート例が架空である旨の明記などを修正
:::

## この記事でわかること

- GA4 の BigQuery エクスポートから、LTV 予測に使う顧客単位のデータを作る SQL
- BG/NBD + Gamma-Gamma モデルと、時間で分割した回帰モデルの 2 つの実装
- 予測値を CPA 上限の設定に使うときの計算と注意点

### 前提

- GA4 の BigQuery エクスポート（日次テーブル `events_YYYYMMDD`）が有効で、`purchase` イベントに `transaction_id` が入っていること
- BigQuery の読み取り権限と Python 3.10 以上の環境。クエリ料金は読み込むデータ量で決まるため、期間を絞って試してください
- 購入額は `ecommerce.purchase_revenue` をそのまま使います。**通貨は現地通貨のままなので、複数通貨で販売しているショップは合算できません**（通貨ごとに分けるか、換算してから使ってください）
- **`lifetimes` は 2024-06-28 にアーカイブされ、最新版は 0.11.3（[PyPI](https://pypi.org/project/Lifetimes/) の表示で 2020-07-06 公開）です。** 現行の NumPy / pandas での動作は保証されません。自分の環境の一例として、合成データで Python 3.11・NumPy 2.4・pandas 3.0 に `pip install lifetimes==0.11.3` を入れ、**BG/NBD の `fit` までは動くことを確認しました。** `calibration_and_holdout_data`・Gamma-Gamma・`customer_lifetime_value`・`conditional_probability_alive` は、呼び出しの署名を公式ドキュメントと照合しただけで、実行は確認していません。実データでの確認でもありません。動かない場合は、同じ種類のモデル（BG/NBD・Gamma-Gamma）を扱える別のライブラリである PyMC-Marketing への置き換えを検討してください（後述）

## LTV予測の2つのアプローチ

| | BG/NBD + Gamma-Gamma | 回帰モデル |
|---|---|---|
| 考え方 | 購買頻度と離脱を確率モデルで表す | 特徴量から将来の購入額を直接予測する |
| 入力 | 購入回数・最終購入までの期間・観測期間の長さ・平均購入額 | 上記に加えてセッション行動・流入・デバイスなど |
| 向いている場面 | データが少ない初期段階。解釈しやすい | 特徴量を増やして精度を上げたいとき |
| 注意 | 仮定（後述）が外れると当たらない | 期間の切り方を間違えるとリークする |

EC の初期段階ではデータ量が限られるため、BG/NBD から始めるのが取り組みやすいです。

## Step 1: BigQueryから購買データを取得する

GA4 の `events_*` を読むときは、次の 2 点を押さえます。

- `_TABLE_SUFFIX` は `REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')` で日次テーブルに絞る（`events_intraday_` を拾わないため）
- 期間は固定値ではなく、クエリパラメータで渡す

### BG/NBD 用: 購入明細を取得する

BG/NBD の入力は「顧客ID・購入日・購入額」の明細です。集計は後段のライブラリが行います。

```sql
-- 購入（注文）単位の明細を取得する。@start_date〜@end_date は期間のパラメータ
SELECT
  user_pseudo_id AS customer_id,
  transaction_id,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS date,
  MAX(ecommerce.purchase_revenue) AS revenue
FROM
  `project.dataset.events_*`
WHERE
  REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
  AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', @start_date) AND FORMAT_DATE('%Y%m%d', @end_date)
  AND event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
GROUP BY customer_id, transaction_id
```

:::message
`transaction_id` が `NULL` の購入は除外しています。GA4 の ecommerce イベントが正しく設定されていないと欠損することがあるため、事前に欠損率を確認してください。同じ `transaction_id` の `purchase` が重複して送信されるケースを `GROUP BY` でまとめています。
:::

### 回帰モデル用: 観測期間の特徴量と、予測期間の購入額

回帰モデルでは **特徴量を作る期間（観測期間）と、予測したい期間（予測期間）を時間で分けます。** 基準日 `@cutoff_date` より前のデータから特徴量を作り、基準日以降 `@horizon_days` 日間の購入額を目的変数 `future_revenue` にします。

- 対象は「基準日より前に 1 回以上購入した顧客」
- 予測期間に購入がなければ `future_revenue` は 0
- 初回流入は、イベント単位の `collected_traffic_source` ではなく、ユーザー単位の `traffic_source.medium` を使う
- 顧客ごとに 1 行へ集約してから結合するので、結合は 1 対 1 になる
- 特徴量の窓の長さ（`@cutoff_date − @obs_start`）は、学習用と検証用で揃える（例: `@obs_start = @cutoff_date − 365 日`）。窓の長さが違うと `frequency`・`tenure_days`・各 count の水準がずれ、MAE や R² が歪む

```sql
-- 基準日より前の特徴量と、基準日以降 @horizon_days 日間の購入額を顧客ごとに1行で返す
WITH events AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    event_name,
    event_params,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue,
    traffic_source.medium AS first_medium,
    device.category AS device_category
  FROM `project.dataset.events_*`
  WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
    AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', @obs_start)
    AND _TABLE_SUFFIX < FORMAT_DATE('%Y%m%d', DATE_ADD(@cutoff_date, INTERVAL @horizon_days DAY))
),
orders AS (
  SELECT
    user_pseudo_id,
    transaction_id,
    MIN(event_dt) AS order_dt,
    MAX(revenue) AS revenue
  FROM events
  WHERE event_name = 'purchase' AND transaction_id IS NOT NULL AND revenue IS NOT NULL
  GROUP BY user_pseudo_id, transaction_id
),
cohort AS (
  -- 観測期間に購入した顧客だけが対象
  SELECT
    user_pseudo_id,
    COUNT(*) AS frequency,
    SUM(revenue) / COUNT(*) AS avg_order_value,
    DATE_DIFF(@cutoff_date, MAX(order_dt), DAY) AS days_since_last_order,
    DATE_DIFF(@cutoff_date, MIN(order_dt), DAY) AS tenure_days
  FROM orders
  WHERE order_dt < @cutoff_date
  GROUP BY user_pseudo_id
),
future AS (
  SELECT user_pseudo_id, SUM(revenue) AS future_revenue
  FROM orders
  WHERE order_dt >= @cutoff_date
  GROUP BY user_pseudo_id
),
behavior AS (
  -- 観測期間の行動。ユーザー単位に集約する
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')) AS total_sessions,
    COUNTIF(event_name = 'view_item') AS view_item_count,
    COUNTIF(event_name = 'add_to_cart') AS add_to_cart_count,
    COUNTIF(event_name = 'page_view') AS page_view_count,
    ANY_VALUE(first_medium) AS first_medium,
    ARRAY_AGG(device_category IGNORE NULLS ORDER BY event_timestamp DESC LIMIT 1)[SAFE_OFFSET(0)] AS device_category  -- NULL を除き、全件 NULL なら NULL を返す
  FROM events
  WHERE event_dt < @cutoff_date
  GROUP BY user_pseudo_id
)
SELECT
  c.user_pseudo_id,
  c.frequency,
  c.days_since_last_order,
  c.tenure_days,
  c.avg_order_value,
  b.total_sessions,
  b.view_item_count,
  b.add_to_cart_count,
  b.page_view_count,
  b.first_medium,
  b.device_category,
  IFNULL(f.future_revenue, 0) AS future_revenue
FROM cohort AS c
LEFT JOIN behavior AS b USING (user_pseudo_id)
LEFT JOIN future AS f USING (user_pseudo_id)
```

:::message
このSQLは BigQuery 上で実行して確認したものではありません。自分の環境のデータで実行し、行数が購入者数と一致すること（1 顧客 1 行になっていること）を先に確認してください。`traffic_source.medium` は GA4 の「ユーザーを最初に獲得した流入」に当たる値です。
:::

## Step 2: BG/NBDモデルによるLTV予測

### 用語: lifetimes の recency は一般的な RFM と逆

一般的な RFM の Recency は「最終購入からの経過日数」です。一方 `lifetimes` の `recency` は **「初回購入から最終購入までの期間」** で、向きが逆です。本記事では混乱を避けるため、次のように呼び分けます。

| 本記事の名前 | 意味 | 使う場所 |
|---|---|---|
| `recency`（lifetimes の列名） | 初回購入〜最終購入の期間 | BG/NBD |
| `days_since_last_order` | 基準日 − 最終購入日（一般的な Recency） | 回帰モデル |

### BG/NBD の仮定

BG/NBD は「顧客はアクティブな間は一定の購入率（ポアソン過程）で購入し、購入の直後に確率 p で離脱する」と考えるモデルです。購入率はガンマ分布、離脱確率はベータ分布に従うと仮定します。使う前に次の仮定を確認してください。

- 顧客どうしは独立していると仮定する（口コミ・キャンペーンの影響などは扱わない）
- 購入率と離脱確率は、顧客ごとに違う値を持つ（上記のガンマ分布・ベータ分布から来る）と仮定する
- 顧客が明示的に解約しない「非契約型」の業態向け。サブスクのような契約型には別のモデルを使う

Gamma-Gamma は、購入額が購入回数と独立であると仮定します。分析前に `frequency` と `monetary_value` の相関を確認し、強い相関があれば使いません。

### インストール

```bash
# lifetimes はアーカイブ済みのためバージョンを固定する。db-dtypes は to_dataframe() に必要
pip install "lifetimes==0.11.3" pandas google-cloud-bigquery db-dtypes
```

### 学習と検証（学習期間とホールドアウト期間を分ける）

学習には **1 回しか購入していない顧客を含む全顧客** を使います。1 回購入者（`frequency = 0`）を落とすと、購入頻度が過大に推定されます。`monetary_value > 0` の絞り込みが必要なのは Gamma-Gamma だけで、対象も `frequency > 0` の顧客に限ります。

検証は `calibration_and_holdout_data` を使い、学習期間の末尾までのデータで学習し、その後のホールドアウト期間の購入回数と比べます。

```python
# ltv_bgnbd_model.py: BG/NBD + Gamma-Gamma で LTV を予測する（lifetimes==0.11.3）
import datetime as dt

import pandas as pd
from google.cloud import bigquery
from lifetimes import BetaGeoFitter, GammaGammaFitter
from lifetimes.utils import calibration_and_holdout_data, summary_data_from_transaction_data

QUERY = """
SELECT
  user_pseudo_id AS customer_id,
  transaction_id,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS date,
  MAX(ecommerce.purchase_revenue) AS revenue
FROM `{project}.{dataset}.events_*`
WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\\d{{8}}$')
  AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', @start_date) AND FORMAT_DATE('%Y%m%d', @end_date)
  AND event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
GROUP BY customer_id, transaction_id
"""


def fetch_transactions(
    client: bigquery.Client, project: str, dataset: str, start: dt.date, end: dt.date
) -> pd.DataFrame:
    """期間を指定して購入明細（customer_id, date, revenue）を取得する"""
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("start_date", "DATE", start),
            bigquery.ScalarQueryParameter("end_date", "DATE", end),
        ]
    )
    df = client.query(QUERY.format(project=project, dataset=dataset), job_config=job_config).to_dataframe()
    df["date"] = pd.to_datetime(df["date"])
    return df.dropna(subset=["revenue"])


def evaluate_holdout(transactions: pd.DataFrame, calibration_end: str, observation_end: str) -> pd.DataFrame:
    """学習期間で BG/NBD を学習し、ホールドアウト期間の購入回数と比べた表を返す"""
    cal = calibration_and_holdout_data(
        transactions,
        customer_id_col="customer_id",
        datetime_col="date",
        calibration_period_end=calibration_end,
        observation_period_end=observation_end,
        freq="D",
        monetary_value_col="revenue",
    )
    bgf = BetaGeoFitter(penalizer_coef=0.01)  # 0.01 は出発点の一例。収束しない場合や過学習が疑われる場合に調整する
    bgf.fit(cal["frequency_cal"], cal["recency_cal"], cal["T_cal"])
    cal["predicted_holdout"] = bgf.conditional_expected_number_of_purchases_up_to_time(
        cal["duration_holdout"], cal["frequency_cal"], cal["recency_cal"], cal["T_cal"]
    )
    return cal


def fit_models(transactions: pd.DataFrame, observation_end: str) -> tuple[pd.DataFrame, BetaGeoFitter, GammaGammaFitter]:
    """全期間で再学習する。BG/NBD は全顧客、Gamma-Gamma は frequency>0 かつ monetary_value>0 のみ"""
    summary = summary_data_from_transaction_data(
        transactions,
        customer_id_col="customer_id",
        datetime_col="date",
        monetary_value_col="revenue",
        observation_period_end=observation_end,
        freq="D",
    )
    bgf = BetaGeoFitter(penalizer_coef=0.01)
    bgf.fit(summary["frequency"], summary["recency"], summary["T"])

    repeat = summary[(summary["frequency"] > 0) & (summary["monetary_value"] > 0)]
    print("frequency と monetary_value の相関:", repeat["frequency"].corr(repeat["monetary_value"]))
    ggf = GammaGammaFitter(penalizer_coef=0.01)
    ggf.fit(repeat["frequency"], repeat["monetary_value"])
    return summary, bgf, ggf


def predict_ltv(
    summary: pd.DataFrame, bgf: BetaGeoFitter, ggf: GammaGammaFitter, months: int = 12, discount_rate: float = 0.01
) -> pd.DataFrame:
    """購入回数は全顧客、LTV（金額込み）は frequency>0 の顧客について予測する"""
    summary = summary.copy()
    summary["predicted_purchases_30d"] = bgf.conditional_expected_number_of_purchases_up_to_time(
        30, summary["frequency"], summary["recency"], summary["T"]
    )
    repeat = summary[(summary["frequency"] > 0) & (summary["monetary_value"] > 0)]
    summary["predicted_ltv"] = ggf.customer_lifetime_value(
        bgf,
        repeat["frequency"],
        repeat["recency"],
        repeat["T"],
        repeat["monetary_value"],
        time=months,  # 月数
        discount_rate=discount_rate,  # 月次の割引率
        freq="D",  # T と recency の単位（日）
    )
    return summary


def main() -> None:
    project, dataset = "your-project", "your_dataset"
    start, end = dt.date(2025, 1, 1), dt.date(2026, 9, 30)  # 実際のデータ期間に合わせる
    client = bigquery.Client(project=project)
    transactions = fetch_transactions(client, project, dataset, start, end)

    cal = evaluate_holdout(transactions, calibration_end="2026-03-31", observation_end=end.isoformat())
    print("ホールドアウト期間の実績購入回数:", cal["frequency_holdout"].sum())
    print("BG/NBD の予測購入回数:", round(cal["predicted_holdout"].sum(), 1))

    summary, bgf, ggf = fit_models(transactions, observation_end=end.isoformat())
    result = predict_ltv(summary, bgf, ggf)
    print(result.nlargest(20, "predicted_ltv")[["frequency", "recency", "monetary_value", "predicted_ltv"]].to_string())
    result.to_csv("ltv_predictions.csv")


if __name__ == "__main__":
    main()
```

読み方のポイントは次の 3 つです。

- ホールドアウト期間の「実績の購入回数合計」と「予測の合計」が大きく離れていないかをまず見る
- 離れている場合は、仮定（顧客の独立・購入率が時間で一定）が外れていないか、セールや季節要因を含む期間になっていないかを疑う
- `predicted_ltv` が NaN の行は、`frequency = 0`（1 回購入者）でそもそも計算していない。**LTV の平均を CPA の判断に使うときは、これが「リピート購入者だけの平均」である点に注意する**
- `predicted_ltv` は **将来の期待売上のみ**で、初回購入額や過去の購入分を含まない（`monetary_value` も初回を除くリピート購入の平均）。新規顧客の CPA 判断では、初回の平均注文額を加算して考える
- 上のコードの `freq="D"` では、同じ日の複数注文は 1 回に集約される（`lifetimes` の `frequency` は「購入日数」）。回帰モデル側の `frequency`（注文数）とは定義が違うので、混ぜて比較しない

:::message
`lifetimes` が動かない場合は、後継の PyMC-Marketing（`pymc_marketing.clv`）への置き換えを検討してください。公式ドキュメント（https://www.pymc-marketing.io/en/stable/notebooks/clv/clv_quickstart.html）によると、`BetaGeoModel`（BG/NBD）と `GammaGammaModel` が用意され、入力は `customer_id` / `frequency` / `recency` / `T` / `monetary_value` の表です。ベイズ推定のため API・学習方法・実行時間が異なり、本記事のコードはそのままでは動きません。
:::

## Step 3: 回帰モデルによるLTV予測

BG/NBD より多くの特徴量を使いたい場合に回帰モデルを使います。

### 構成: 時間で分けた 2 つのスナップショット

以前の版は目的変数が特徴量から再構成できるリークした構成でした（冒頭の更新ブロック参照）。現在の構成は次のとおりです。

1. 基準日 T1 より前で特徴量を作り、T1 から `horizon_days` 日間の購入額を目的変数にする（学習用）
2. 基準日 T2 = T1 + `horizon_days` でも同じ表を作る（検証用）。T2 の目的変数の期間は、学習用の期間と重ならない
3. ランダム分割ではなく、**過去の基準日で学習し、より後の基準日で評価する**（時系列での分割）

### 実装

```python
# ltv_regression_model.py: 時間で分けた2つのスナップショットで回帰モデルを学習・評価する
import datetime as dt

import numpy as np
import pandas as pd
from google.cloud import bigquery
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.preprocessing import OrdinalEncoder

CATEGORICAL = ["first_medium", "device_category"]
FEATURES = [
    "frequency", "days_since_last_order", "tenure_days", "avg_order_value",
    "total_sessions", "view_item_count", "add_to_cart_count", "page_view_count",
]
TARGET = "future_revenue"


def fetch_snapshot(
    client: bigquery.Client, sql: str, obs_start: dt.date, cutoff: dt.date, horizon_days: int
) -> pd.DataFrame:
    """Step 1 の回帰用SQLを、基準日 cutoff について実行する。obs_start は cutoff − 365日 のように窓の長さを揃えて渡す（sql 内の project.dataset は置き換えておく）"""
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("obs_start", "DATE", obs_start),
            bigquery.ScalarQueryParameter("cutoff_date", "DATE", cutoff),
            bigquery.ScalarQueryParameter("horizon_days", "INT64", horizon_days),
        ]
    )
    return client.query(sql, job_config=job_config).to_dataframe()


def prepare_features(
    df: pd.DataFrame, encoder: OrdinalEncoder | None = None
) -> tuple[pd.DataFrame, OrdinalEncoder]:
    """特徴量の表を作る。encoder が None なら学習用（fit）、渡されたら検証用（transform のみ）"""
    out = df.copy()
    cats = out[CATEGORICAL].fillna("(none)")
    if encoder is None:
        encoder = OrdinalEncoder(handle_unknown="use_encoded_value", unknown_value=-1)
        encoder.fit(cats)
    out[[f"{c}_code" for c in CATEGORICAL]] = encoder.transform(cats)
    columns = FEATURES + [f"{c}_code" for c in CATEGORICAL]
    return out[columns].fillna(0), encoder


def train_and_evaluate(
    train_df: pd.DataFrame, test_df: pd.DataFrame
) -> tuple[GradientBoostingRegressor, dict[str, float], pd.Series]:
    """train_df（過去の基準日）で学習し、test_df（より後の基準日）で評価する"""
    X_train, encoder = prepare_features(train_df)
    X_test, _ = prepare_features(test_df, encoder)
    y_train, y_test = train_df[TARGET], test_df[TARGET]

    model = GradientBoostingRegressor(
        n_estimators=200, max_depth=3, learning_rate=0.05, subsample=0.8, random_state=42
    )
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    baseline = np.full(len(y_test), y_train.mean())  # 「全員に学習データの平均を当てる」比較対象
    metrics = {
        "MAE": mean_absolute_error(y_test, y_pred),
        "RMSE": float(np.sqrt(mean_squared_error(y_test, y_pred))),
        "R2": r2_score(y_test, y_pred),
        "MAE_baseline": mean_absolute_error(y_test, baseline),
    }
    importance = pd.Series(model.feature_importances_, index=X_train.columns).sort_values(ascending=False)
    return model, metrics, importance
```

使い方は、`fetch_snapshot` を 2 回呼びます。たとえば `horizon_days = 90` として、1 回目は基準日 T1（学習用）、2 回目は T1 + 90 日（検証用）です。**特徴量の窓の長さは 2 回で揃えます。** 例として `obs_start = cutoff − 365 日` とすると、学習用は `obs_start = T1 − 365 日`、検証用は `obs_start = (T1 + 90 日) − 365 日` です。`obs_start` を 2 回とも同じ日にすると、検証用の `frequency`・`tenure_days`・各 count が長い窓で積み上がり、学習時と分布がずれて MAE や R² が歪みます。なお、検証用にも学習用と同じ顧客が入るため、評価はやや楽観的になります。

### 評価指標の読み方

| 指標 | 意味 | 読み方 |
|---|---|---|
| MAE | 予測と実績の差の絶対値の平均（円） | 1 人あたり平均でどれだけ外れるか。直感的 |
| RMSE | 差の二乗平均の平方根（円） | 大きく外れた顧客に敏感。MAE より極端に大きければ外れ値に弱い |
| R² | 平均を当てる予測に比べてどれだけ改善したか | 0 に近い、またはマイナスなら、平均を当てるのと同じかそれ以下 |

購入額は少数の高額顧客に偏り、予測期間に買わない顧客（目的変数が 0）も多いため、R² は低めに出ることがよくあります。`MAE_baseline`（平均を当てる予測の MAE）より MAE が小さいかどうかを必ず見比べてください。リークした構成では R² が高く出ますが、それは良いモデルの証拠ではありません。

## Step 4: Claude Codeで分析フローを実行する

Claude Code に指示して、取得・学習・出力の流れを任せることもできます。`claude "..."` は対話画面を起動するコマンドで、非対話で実行するときは `claude -p` を使います。

```bash
# 非対話（-p）で実行し、結果をファイルに出力させる例
claude -p "BigQueryのGA4データから購入明細を取得し、BG/NBDモデルでLTV予測を行ってください。
学習期間とホールドアウト期間を分けて検証し、結果をCSVとMarkdownレポートで出力してください。" \
  --allowedTools "Bash,Read,Write"
```

`-p` では権限の確認画面に答える人がいないため、コマンド実行（Bash）やファイル書き込み（Write）を使わせるには `--allowedTools` で許可を渡します（[公式ドキュメント](https://code.claude.com/docs/en/headless)）。

:::message
Claude Code が生成するコードと数値は、必ず自分で確認してください。特に「学習期間と予測期間が分かれているか」「1 回購入者を含めて学習しているか」は、生成結果をそのまま信じず読み合わせます。BigQuery の認証（Application Default Credentials など）は事前に済ませておく必要があります。
:::

### レポートの出力例

以下は **架空のサンプルデータによる例です**（実在のストアの数値ではありません）。

```markdown
# LTV予測分析レポート（架空のサンプル）

## モデルサマリー
- 分析対象ユーザー: 2,450名
- 予測期間: 12ヶ月
- モデル: BG/NBD + Gamma-Gamma

## セグメント分析

| セグメント | ユーザー数 | 平均LTV | 平均購入回数 |
|-----------|-----------|---------|------------|
| 高LTV | 245 | ¥85,000 | 5.2回 |
| 中LTV | 980 | ¥32,000 | 2.8回 |
| 低LTV | 1,225 | ¥8,500 | 1.2回 |
```

高LTV層の特徴（流入元・デバイス・初回からリピートまでの期間など）は、実データの集計結果を見て判断してください。

## LTV予測の活用方法

### 1. 広告のCPA上限の設定

CPA上限は、次の式 1 本で決めます。

```
CPA上限 = 平均LTV × 利益率 ÷ target_roi
```

- `平均LTV × 利益率` は、顧客 1 人から見込める粗利
- `target_roi` は「広告費 1 円に対して、何円の粗利を回収したいか」の倍率。`1.0` なら損益分岐（回収のみ）、`2.0` なら広告費の 2 倍の粗利を回収する水準

平均LTVが ¥32,000（仮の値。上の架空レポートの「中LTV層」の値で、サンプル全体の加重平均は約 ¥25,550 です）で利益率が 30% の場合、粗利は ¥9,600 です。`target_roi = 1.0` なら CPA 上限は ¥9,600、`target_roi = 2.0` なら ¥4,800 になります。

```python
# CPA上限 = 平均LTV × 利益率 ÷ target_roi
def calculate_max_cpa(avg_ltv: float, profit_margin: float, target_roi: float = 1.0) -> float:
    """target_roi は広告費1円あたりに回収したい粗利の倍率（1.0 = 損益分岐）"""
    return avg_ltv * profit_margin / target_roi


print(f"CPA上限(target_roi=1.0): ¥{calculate_max_cpa(32000, 0.3, 1.0):,.0f}")  # ¥9,600
print(f"CPA上限(target_roi=2.0): ¥{calculate_max_cpa(32000, 0.3, 2.0):,.0f}")  # ¥4,800
```

平均LTVには、予測期間の長さ（12ヶ月など）と、Step 2 の注意（リピート購入者だけの平均になっていないか）が効きます。Step 2 の `predicted_ltv` は将来の期待売上のみで初回購入額を含まないため、新規顧客の CPA 上限に使うと過小評価になります。初回の平均注文額を加算し、初回購入しかしない顧客も含めた平均で考えてください。

### 2. 離脱予測とリテンション施策

BG/NBD の「alive 確率」（現在も購入を続ける状態にある確率）を使い、離脱しそうな顧客を抽出できます。`threshold` は仮の値なので、確率の分布を見て決めてください。

```python
import pandas as pd
from lifetimes import BetaGeoFitter


def identify_at_risk_customers(bgf: BetaGeoFitter, summary: pd.DataFrame, threshold: float = 0.3) -> pd.DataFrame:
    """alive確率が threshold 未満の顧客を、確率の低い順に返す（threshold は仮の値）"""
    summary = summary.copy()
    summary["alive_probability"] = bgf.conditional_probability_alive(
        summary["frequency"], summary["recency"], summary["T"]
    )
    at_risk = summary[summary["alive_probability"] < threshold]
    return at_risk.sort_values("alive_probability")
```

`frequency = 0`（1 回購入者）の alive 確率は常に 1.0 になるため、このリストには出てきません。離脱予測の対象はリピート購入者です。

## 注意点

### データ量の目安

BG/NBD を安定して学習できるリピート購入者の数に、公式な基準はありません。リピート購入者が少ない場合は収束しなかったり、パラメータが不安定になったりするので、`penalizer_coef` を大きくする、期間を延ばす、といった調整が必要です（本記事の 0.01 は出発点の一例で、要調整です）。

### 予測の限界

LTV 予測は過去の購買パターンの延長です。大規模なサイトリニューアル、価格変更、競合の参入などの変化には対応できません。定期的に再学習し、ホールドアウト期間の実績との差を監視してください。また、`user_pseudo_id` はブラウザ・端末単位の ID なので、同じ人が複数の ID に分かれていると、リピート購入が実際より少なく見えます。

### プライバシーへの配慮

`user_pseudo_id` は GA4 が発行する匿名 ID ですが、CRM データと結合する場合は個人情報保護法や GDPR への準拠を確認してください。

## まとめ

- 回帰モデルは「観測期間の特徴量 → 将来期間の購入額」で作り、時間で分けて評価する。BG/NBD は 1 回購入者を含む全顧客で学習し、Gamma-Gamma だけ `frequency > 0` で学習する
- `lifetimes` はアーカイブ済み。バージョンを固定して使い、動かなければ PyMC-Marketing を検討する
- CPA 上限は「平均LTV × 利益率 ÷ target_roi」の 1 式で決め、数値は自社のデータで置き換える

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
[データ分析スポットプラン](https://coconala.com/services/554778)
:::

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::
