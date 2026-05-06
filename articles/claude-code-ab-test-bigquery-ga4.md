---
title: "Claude CodeでEC×GA4のA/Bテスト結果をBigQueryから自動集計する"
emoji: "🧪"
type: "tech"
topics: ["claudecode","bigquery","abtesting"]
published: false
---

## はじめに

「A/Bテストを実施したものの、結果の集計と統計的な判定に毎回時間がかかる」

ECサイトでLP、商品ページ、CTAボタンのA/Bテストを行う機会は多いものの、GA4のデータをBigQueryから取り出して統計的有意性を検証する作業は手間がかかります。

本記事では、Claude Codeを使ってGA4のA/BテストデータをBigQueryから自動集計し、統計的有意性の検定まで行うスクリプトを構築した方法を紹介します。

## 前提: GA4でのA/Bテスト計測設計

A/Bテストのバリアント情報をGA4で計測するには、カスタムイベントパラメータを使います。

### GTMでの設定例

テスト対象ページでJavaScriptによりバリアントを振り分け、dataLayerにpushします。

```javascript
// A/Bテストのバリアント振り分け（例: 50/50）
const variant = Math.random() < 0.5 ? 'A' : 'B';

// ローカルストレージで同一ユーザーのバリアントを固定
const storedVariant = localStorage.getItem('ab_test_lp_v1');
const finalVariant = storedVariant || variant;
if (!storedVariant) {
  localStorage.setItem('ab_test_lp_v1', finalVariant);
}

// GA4にイベント送信
dataLayer.push({
  event: 'ab_test_impression',
  ab_test_name: 'lp_v1',
  ab_test_variant: finalVariant
});
```

:::message
テストのバリアントは同一ユーザーに対して一貫性を保つ必要があります。ローカルストレージやCookieで振り分け結果を保持し、再訪問時も同じバリアントが表示されるようにしてください。
:::

## Step 1: BigQueryでA/Bテストデータを集計するSQL

GA4のBigQueryエクスポートから、テスト名・バリアント別のKPIを集計します。

```sql
WITH ab_impressions AS (
  -- A/Bテストのインプレッション
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_name') AS test_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_variant') AS variant
  FROM
    `project.dataset.events_*`
  WHERE
    event_name = 'ab_test_impression'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
session_conversions AS (
  -- 購入イベントのあったセッション
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `project.dataset.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)

SELECT
  ai.test_name,
  ai.variant,
  COUNT(DISTINCT ai.user_pseudo_id) AS users,
  COUNT(DISTINCT ai.ga_session_id) AS sessions,
  COUNT(DISTINCT sc.ga_session_id) AS conversions,
  SAFE_DIVIDE(
    COUNT(DISTINCT sc.ga_session_id),
    COUNT(DISTINCT ai.ga_session_id)
  ) AS cvr,
  SUM(sc.revenue) AS total_revenue,
  SAFE_DIVIDE(
    SUM(sc.revenue),
    COUNT(DISTINCT ai.ga_session_id)
  ) AS revenue_per_session
FROM
  ab_impressions ai
LEFT JOIN
  session_conversions sc
  ON ai.user_pseudo_id = sc.user_pseudo_id
  AND ai.ga_session_id = sc.ga_session_id
GROUP BY
  ai.test_name, ai.variant
ORDER BY
  ai.test_name, ai.variant
```

:::message
`SAFE_DIVIDE` を使うことで、ゼロ除算エラーを回避できます。テスト初期のデータが少ない段階でもクエリが正常に完了します。
:::

## Step 2: Pythonで統計的有意性を検定する

BigQueryの集計結果をPythonに取り込み、カイ二乗検定でCVRの差が統計的に有意かどうかを判定します。

```python
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
```

## Step 3: Markdownレポートを自動生成する

検定結果をMarkdownで出力します。

```python
def generate_ab_report(result: dict, test_name: str) -> str:
    """A/Bテスト結果のMarkdownレポートを生成する"""
    a = result['variant_a']
    b = result['variant_b']
    sig_label = "有意差あり" if result['significant'] else "有意差なし"

    report = f"""# A/Bテスト結果レポート: {test_name}

## 結果サマリー

| 項目 | バリアントA ({a['name']}) | バリアントB ({b['name']}) |
|------|--------------------------|--------------------------|
| セッション数 | {a['sessions']:,} | {b['sessions']:,} |
| CV数 | {a['conversions']:,} | {b['conversions']:,} |
| CVR | {a['cvr']}% | {b['cvr']}% |

## 統計検定

| 指標 | 値 |
|------|-----|
| カイ二乗値 | {result['chi2']} |
| p値 | {result['p_value']} |
| 判定 | **{sig_label}**（有意水準5%）|
| 相対リフト | {result['relative_uplift']}% |

## 推奨アクション

{result['recommendation']}
"""
    return report
```

## Step 4: Claude Codeで一連の処理を実行する

Claude Codeに以下のように指示すると、データ取得から検定、レポート出力まで一気に実行してくれます。

```bash
claude "ab_test_analyzer.py を使って、テスト名 'lp_v1' の結果を
BigQueryから取得して検定し、レポートをMarkdownで出力してください。
結果に基づいた改善提案も追加して。"
```

Claude Codeは検定結果を受けて、たとえば以下のような考察を追加します。

> バリアントBのCVRが2.8%と、バリアントA（2.1%）に対して33%のリフトを記録しています。
> p値は0.023であり、有意水準5%で統計的に有意な差が認められます。
>
> バリアントBではCTAボタンの文言を「今すぐ購入」から「カートに追加」に変更しています。
> 購入ハードルの低い表現にしたことで、ファーストアクションの心理的障壁が下がった可能性があります。

## サンプルサイズ計算の自動化

テスト開始前に必要なサンプルサイズを計算する機能も追加できます。

```python
from scipy.stats import norm
import math

def required_sample_size(
    baseline_cvr: float,
    min_detectable_effect: float,
    alpha: float = 0.05,
    power: float = 0.8
) -> int:
    """A/Bテストに必要なサンプルサイズを計算する"""
    p1 = baseline_cvr
    p2 = baseline_cvr * (1 + min_detectable_effect)
    p_avg = (p1 + p2) / 2

    z_alpha = norm.ppf(1 - alpha / 2)
    z_beta = norm.ppf(power)

    n = (
        (z_alpha * math.sqrt(2 * p_avg * (1 - p_avg)) +
         z_beta * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))) ** 2
    ) / (p2 - p1) ** 2

    return math.ceil(n)

# 使用例: 現在のCVR 2%、10%のリフトを検出したい場合
n = required_sample_size(baseline_cvr=0.02, min_detectable_effect=0.10)
print(f"各バリアントに必要なサンプルサイズ: {n:,}")
```

:::message
サンプルサイズが不足した状態でテストを終了すると、偽陽性（実際には差がないのに差があると判定）のリスクが高まります。テスト開始前に必要なサンプルサイズを把握し、十分なデータが集まってから判定するようにしましょう。
:::

## 実装時の注意点

### 1. 複数テストの同時実行

同じページで複数のA/Bテストを同時実行する場合、テスト間の干渉に注意が必要です。`ab_test_name` パラメータでテストを識別し、ユーザー単位でバリアントを固定します。

### 2. テスト期間と季節性

曜日による購買行動の違いを考慮し、テスト期間は最低でも2週間（14日間）を確保します。セールなどの特殊イベントがある期間はテスト対象から除外するか、イベントの影響を注記に含めます。

### 3. 新規ユーザーとリピーターの分離

新規ユーザーとリピーターでは購買行動が異なるため、セグメントを分けて分析することも検討してください。SQLの `WHERE` 句にユーザーの初回訪問日フィルタを追加することで対応できます。

## まとめ

A/BテストのBigQuery集計と統計検定の自動化は、以下の手順で実現できます。

1. GA4のカスタムイベントでバリアント情報を計測する
2. BigQueryでバリアント別のKPIを集計するSQLを作成する
3. Pythonのscipyでカイ二乗検定を行う
4. Claude Codeでデータ取得から検定、レポート出力まで一括実行する

テスト結果の集計時間を削減することで、次のテスト仮説の立案に時間を充てられるようになります。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
