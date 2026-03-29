---
title: "Claude Code × Python × BigQueryでLTV予測モデルを作った"
emoji: "🔮"
type: "tech"
topics: ["claudecode","bigquery","machinelearning"]
published: false
---

## はじめに

「顧客のLTV（顧客生涯価値）を予測したいが、機械学習の知見がなくて手が出せない」

ECサイトの運営では、新規顧客の獲得コスト（CPA）とLTVのバランスが収益性を左右します。しかし、LTVの予測モデルを構築するには統計・機械学習の知識とデータ基盤の整備が必要で、ハードルが高いと感じる方も多いのではないでしょうか。

本記事では、BigQueryに蓄積されたGA4の購買データを使い、Claude CodeでLTV予測モデルを構築した過程を紹介します。BG/NBDモデル（Beta-Geometric/Negative Binomial Distribution）と回帰ベースの2つのアプローチを解説します。

## LTV予測の2つのアプローチ

### アプローチ1: BG/NBDモデル（確率モデル）

顧客の購買頻度と離脱確率を同時にモデル化する確率的手法です。`lifetimes` ライブラリで実装できます。

- 少ないデータでも動作する
- 購買回数と最終購買日からの経過日数だけで予測可能
- 解釈性が高い

### アプローチ2: 回帰モデル

顧客の属性や行動データを特徴量として、LTVを直接予測する回帰モデルです。

- 多くの特徴量を活用できる
- 予測精度が高くなりやすい
- ある程度のデータ量が必要

本記事では両方のアプローチを実装しますが、EC事業の初期段階ではデータ量が限られるため、BG/NBDモデルから始めることを推奨します。

## Step 1: BigQueryから購買データを取得する

### RFM（Recency, Frequency, Monetary）データの取得SQL

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.purchase_revenue AS revenue,
    ecommerce.transaction_id
  FROM
    `project.dataset.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
user_metrics AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase,
    MAX(purchase_date) AS last_purchase,
    COUNT(DISTINCT transaction_id) AS frequency,
    SUM(revenue) AS monetary,
    DATE_DIFF(MAX(purchase_date), MIN(purchase_date), DAY) AS recency_days,
    DATE_DIFF(CURRENT_DATE(), MIN(purchase_date), DAY) AS tenure_days
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  frequency,
  recency_days,
  tenure_days,
  monetary,
  monetary / frequency AS avg_order_value,
  first_purchase,
  last_purchase
FROM user_metrics
WHERE frequency >= 1
ORDER BY monetary DESC
```

:::message
`transaction_id` が `NULL` のレコードを除外しています。GA4のecommerceイベントが正しく設定されていない場合、`transaction_id` が欠損することがあります。事前にデータの品質を確認してください。
:::

### セッション行動データの取得SQL（回帰モデル用）

```sql
SELECT
  user_pseudo_id,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS total_sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count,
  COUNTIF(event_name = 'add_to_cart') AS add_to_cart_count,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  collected_traffic_source.manual_medium AS first_medium,
  device.category AS device_category
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  user_pseudo_id, first_medium, device_category
```

## Step 2: BG/NBDモデルによるLTV予測

### lifetimesライブラリのインストール

```bash
pip install lifetimes pandas google-cloud-bigquery
```

### モデルの構築と予測

```python
"""
モジュール名: ltv_bgnbd_model.py
目的: BG/NBDモデルでLTV予測を行う
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas, lifetimes
"""

import pandas as pd
from google.cloud import bigquery
from lifetimes import BetaGeoFitter, GammaGammaFitter
from lifetimes.utils import summary_data_from_transaction_data

def fetch_transaction_data(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """トランザクションデータを取得する"""
    query = f"""
    SELECT
      user_pseudo_id AS customer_id,
      PARSE_DATE('%Y%m%d', event_date) AS date,
      ecommerce.purchase_revenue AS revenue
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      event_name = 'purchase'
      AND ecommerce.transaction_id IS NOT NULL
      AND ecommerce.purchase_revenue > 0
      AND _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    """
    df = client.query(query).to_dataframe()
    df['date'] = pd.to_datetime(df['date'])
    return df

def build_rfm_summary(transactions: pd.DataFrame) -> pd.DataFrame:
    """トランザクションデータからRFMサマリーを構築する"""
    summary = summary_data_from_transaction_data(
        transactions,
        customer_id_col='customer_id',
        datetime_col='date',
        monetary_value_col='revenue',
        observation_period_end=pd.Timestamp.now()
    )
    # monetary_value > 0 のフィルタ（Gamma-Gammaモデルの要件）
    summary = summary[summary['monetary_value'] > 0]
    return summary

def fit_bgnbd_model(summary: pd.DataFrame) -> BetaGeoFitter:
    """BG/NBDモデルを学習する"""
    bgf = BetaGeoFitter(penalizer_coef=0.01)
    bgf.fit(
        summary['frequency'],
        summary['recency'],
        summary['T']
    )
    print("BG/NBDモデルの学習が完了しました")
    print(f"  パラメータ: {bgf.summary}")
    return bgf

def fit_gamma_gamma_model(summary: pd.DataFrame) -> GammaGammaFitter:
    """Gamma-Gammaモデル（購入金額）を学習する"""
    ggf = GammaGammaFitter(penalizer_coef=0.01)
    ggf.fit(
        summary['frequency'],
        summary['monetary_value']
    )
    print("Gamma-Gammaモデルの学習が完了しました")
    return ggf

def predict_ltv(
    bgf: BetaGeoFitter,
    ggf: GammaGammaFitter,
    summary: pd.DataFrame,
    months: int = 12,
    discount_rate: float = 0.01
) -> pd.DataFrame:
    """LTVを予測する"""
    ltv = ggf.customer_lifetime_value(
        bgf,
        summary['frequency'],
        summary['recency'],
        summary['T'],
        summary['monetary_value'],
        time=months,
        discount_rate=discount_rate,
        freq='D'
    )
    summary['predicted_ltv'] = ltv
    summary['predicted_purchases_30d'] = bgf.conditional_expected_number_of_purchases_up_to_time(
        30,
        summary['frequency'],
        summary['recency'],
        summary['T']
    )
    return summary

def main():
    client = bigquery.Client(project='your-project')
    transactions = fetch_transaction_data(client, 'your-project', 'your_dataset')

    if len(transactions) < 100:
        print("トランザクション数が不足しています（100件未満）")
        return

    summary = build_rfm_summary(transactions)
    print(f"分析対象ユーザー数: {len(summary)}")

    bgf = fit_bgnbd_model(summary)
    ggf = fit_gamma_gamma_model(summary)
    result = predict_ltv(bgf, ggf, summary)

    # 上位顧客の予測結果を表示
    top_customers = result.nlargest(20, 'predicted_ltv')
    print("\n=== LTV上位20顧客 ===")
    print(top_customers[['frequency', 'recency', 'monetary_value', 'predicted_ltv']].to_string())

    # CSVに出力
    result.to_csv('data/processed/ltv_predictions.csv')
    print("\n予測結果をCSVに保存しました")

if __name__ == "__main__":
    main()
```

:::message
BG/NBDモデルは「非契約型」のビジネス（ECサイトなど、顧客が明示的に解約しないモデル）に適しています。サブスクリプション型のビジネスでは別のモデル（sBG/sBGモデルなど）を検討してください。
:::

## Step 3: 回帰モデルによるLTV予測

BG/NBDモデルよりも多くの特徴量を活用したい場合、回帰モデルを使います。

```python
"""
モジュール名: ltv_regression_model.py
目的: 回帰モデルでLTV予測を行う
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas, scikit-learn
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.preprocessing import LabelEncoder

def prepare_features(rfm_df: pd.DataFrame, behavior_df: pd.DataFrame) -> pd.DataFrame:
    """特徴量を準備する"""
    # RFMデータとセッション行動データを結合
    merged = rfm_df.merge(behavior_df, on='user_pseudo_id', how='left')

    # カテゴリ変数のエンコード
    le_medium = LabelEncoder()
    le_device = LabelEncoder()
    merged['medium_encoded'] = le_medium.fit_transform(merged['first_medium'].fillna('(none)'))
    merged['device_encoded'] = le_device.fit_transform(merged['device_category'].fillna('(none)'))

    # 特徴量の選定
    features = [
        'frequency', 'recency_days', 'tenure_days', 'avg_order_value',
        'total_sessions', 'view_item_count', 'add_to_cart_count',
        'page_view_count', 'medium_encoded', 'device_encoded'
    ]

    return merged, features

def train_ltv_model(df: pd.DataFrame, features: list[str], target: str = 'monetary'):
    """LTV予測モデルを学習する"""
    X = df[features].fillna(0)
    y = df[target]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = GradientBoostingRegressor(
        n_estimators=200,
        max_depth=5,
        learning_rate=0.1,
        random_state=42
    )
    model.fit(X_train, y_train)

    # 評価
    y_pred = model.predict(X_test)
    mae = mean_absolute_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)

    print(f"モデル評価:")
    print(f"  MAE: ¥{mae:,.0f}")
    print(f"  R²スコア: {r2:.3f}")

    # 特徴量重要度
    importance = pd.DataFrame({
        'feature': features,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)

    print(f"\n特徴量重要度:")
    for _, row in importance.iterrows():
        print(f"  {row['feature']}: {row['importance']:.3f}")

    return model, importance
```

## Step 4: Claude Codeで分析フローを実行する

Claude Codeに以下のように指示すると、データ取得からモデル構築、結果の可視化まで一連の流れを実行してくれます。

```bash
claude "BigQueryからECの購買データを取得して、
BG/NBDモデルでLTV予測を行ってください。
結果はCSVとMarkdownレポートで出力して。
LTV上位セグメントの特徴も分析して。"
```

### Claude Codeが生成するレポートの例

```markdown
# LTV予測分析レポート

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

## 高LTVユーザーの特徴
- 初回購入からリピートまでの期間が平均14日と短い
- organic経由の流入が60%を占める
- モバイルよりPCからの購入比率が高い
```

## LTV予測の活用方法

### 1. 広告のCPA上限の設定

予測LTVに基づいてCPA上限を設定できます。たとえば、平均LTVが¥32,000で利益率が30%の場合、CPA上限は¥9,600となります。

```python
def calculate_max_cpa(avg_ltv: float, profit_margin: float, target_roi: float = 1.0) -> float:
    """CPA上限を計算する"""
    max_cpa = avg_ltv * profit_margin / (1 + target_roi)
    return max_cpa

# 例
max_cpa = calculate_max_cpa(avg_ltv=32000, profit_margin=0.3, target_roi=1.0)
print(f"CPA上限: ¥{max_cpa:,.0f}")  # ¥4,800
```

### 2. 離脱予測とリテンション施策

BG/NBDモデルの「alive確率」を活用し、離脱しそうな顧客を特定してリテンション施策を打てます。

```python
def identify_at_risk_customers(bgf: BetaGeoFitter, summary: pd.DataFrame, threshold: float = 0.3) -> pd.DataFrame:
    """離脱リスクの高い顧客を特定する"""
    summary['alive_probability'] = bgf.conditional_probability_alive(
        summary['frequency'],
        summary['recency'],
        summary['T']
    )
    at_risk = summary[summary['alive_probability'] < threshold]
    return at_risk.sort_values('alive_probability')
```

### 3. セグメント別マーケティング

LTVセグメントに応じてマーケティング施策を出し分けます。

- **高LTVセグメント**: ロイヤリティプログラム、限定商品の先行案内
- **中LTVセグメント**: クロスセル・アップセルのレコメンド
- **低LTVセグメント**: リピート促進のクーポン、メールナーチャリング

## 注意点

### データ量の目安

BG/NBDモデルを安定して動作させるには、リピート購入者が少なくとも50名程度は必要です。データが不足している場合は、モデルのpenalizer_coefを大きめに設定して正則化を強めます。

### 予測の限界

LTV予測はあくまで過去の購買パターンの延長です。大規模なサイトリニューアル、価格変更、競合の参入など外部環境の変化には対応できません。定期的にモデルを再学習し、予測精度を監視することが重要です。

### プライバシーへの配慮

`user_pseudo_id` はGA4が発行する匿名IDですが、CRMデータと結合する場合は個人情報保護法やGDPRへの準拠を確認してください。

## まとめ

Claude Code × Python × BigQueryでLTV予測モデルを構築する手順は以下のとおりです。

1. BigQueryからRFMデータと行動データを取得する
2. BG/NBDモデルで購買頻度と離脱確率を予測する
3. Gamma-Gammaモデルで購入金額を予測し、LTVを算出する
4. 回帰モデルで多くの特徴量を活用した予測も試みる
5. 予測結果をCPA設定やセグメント施策に活用する

データの規模や事業フェーズに合わせてアプローチを選択し、段階的にモデルの精度を高めていくことが実用的です。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
