"""Claude CodeでEC×GA4のA/Bテスト結果をBigQueryから自動集計する

出典記事: articles/claude-code-ab-test-bigquery-ga4.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: ab_test_analyzer.py
目的: A/Bテスト結果の統計的有意性を検定する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas, scipy
"""

from google.cloud import bigquery
import pandas as pd
from scipy import stats

def fetch_ab_test_results(client: bigquery.Client, project_id: str, dataset: str, test_name: str) -> pd.DataFrame:
    """指定テストのA/B集計結果をBigQueryから取得する"""
    query = f"""
    WITH ab_impressions AS (
      SELECT
        user_pseudo_id,
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_name') AS test_name,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_variant') AS variant
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        event_name = 'ab_test_impression'
        AND _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    ),
    session_conversions AS (
      SELECT DISTINCT
        user_pseudo_id,
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
      FROM
        `{project_id}.{dataset}.events_*`
      WHERE
        event_name = 'purchase'
        AND _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    )
    SELECT
      ai.variant,
      COUNT(DISTINCT ai.ga_session_id) AS sessions,
      COUNT(DISTINCT sc.ga_session_id) AS conversions
    FROM ab_impressions ai
    LEFT JOIN session_conversions sc
      ON ai.user_pseudo_id = sc.user_pseudo_id
      AND ai.ga_session_id = sc.ga_session_id
    WHERE ai.test_name = '{test_name}'
    GROUP BY ai.variant
    ORDER BY ai.variant
    """
    return client.query(query).to_dataframe()

def chi_square_test(df: pd.DataFrame) -> dict:
    """カイ二乗検定でCVRの差の有意性を判定する"""
    if len(df) != 2:
        return {'error': 'バリアントが2つではありません'}

    row_a = df.iloc[0]
    row_b = df.iloc[1]

    # 分割表を作成
    # [[CVあり_A, CVなし_A], [CVあり_B, CVなし_B]]
    table = [
        [row_a['conversions'], row_a['sessions'] - row_a['conversions']],
        [row_b['conversions'], row_b['sessions'] - row_b['conversions']]
    ]

    chi2, p_value, dof, expected = stats.chi2_contingency(table)

    cvr_a = row_a['conversions'] / row_a['sessions'] if row_a['sessions'] > 0 else 0
    cvr_b = row_b['conversions'] / row_b['sessions'] if row_b['sessions'] > 0 else 0
    relative_uplift = (cvr_b - cvr_a) / cvr_a * 100 if cvr_a > 0 else 0

    return {
        'variant_a': {
            'name': row_a['variant'],
            'sessions': int(row_a['sessions']),
            'conversions': int(row_a['conversions']),
            'cvr': round(cvr_a * 100, 2),
        },
        'variant_b': {
            'name': row_b['variant'],
            'sessions': int(row_b['sessions']),
            'conversions': int(row_b['conversions']),
            'cvr': round(cvr_b * 100, 2),
        },
        'chi2': round(chi2, 4),
        'p_value': round(p_value, 4),
        'significant': p_value < 0.05,
        'relative_uplift': round(relative_uplift, 2),
        'recommendation': get_recommendation(p_value, relative_uplift)
    }

def get_recommendation(p_value: float, uplift: float) -> str:
    """検定結果に基づいた推奨アクションを返す"""
    if p_value >= 0.05:
        return "統計的に有意な差は認められません。テスト期間の延長またはサンプルサイズの拡大を検討してください。"
    elif uplift > 0:
        return f"バリアントBが{uplift:.1f}%優位です（p={p_value:.4f}）。バリアントBの採用を検討してください。"
    else:
        return f"バリアントAが{abs(uplift):.1f}%優位です（p={p_value:.4f}）。現行のバリアントAを維持してください。"
