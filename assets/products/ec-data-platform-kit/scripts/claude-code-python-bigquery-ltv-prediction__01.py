"""Claude Code × Python × BigQueryでLTV予測モデルを作った

出典記事: articles/claude-code-python-bigquery-ltv-prediction.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

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
