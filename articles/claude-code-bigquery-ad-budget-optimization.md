---
title: "Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った"
emoji: "💰"
type: "tech"
topics: ["claudecode", "bigquery", "advertising"]
published: false
---

## はじめに

「広告費を月100万円かけているが、どのチャネルにいくら配分すべきかの根拠がない」

EC事業において広告予算の配分は売上に直結する重要な意思決定です。しかし、多くの事業者が過去の慣習や感覚で予算を決めているのが現状ではないでしょうか。

この記事では、BigQueryのGA4データからチャネル別ROASを算出し、Claude Codeで予算再配分の提案書を自動生成するツールを作った方法を紹介します。

---

## 全体の流れ

```
BigQuery（GA4 + 広告コストデータ）
    ↓ チャネル別ROAS算出
ROAS分析結果
    ↓ Claude Code
予算再配分ロジック適用
    ↓
提案書（Markdown）自動生成
```

---

## Step 1：チャネル別ROASを算出する

ROASは「広告費に対してどれだけの売上を得たか」を示す指標です。

```
ROAS = 売上 ÷ 広告費 × 100（%）
```

ROAS 300%なら、広告費1万円に対して3万円の売上があったことを意味します。

### GA4データから売上を抽出するSQL

```sql
-- チャネル別売上（GA4 BigQuery）
WITH channel_revenue AS (
  SELECT
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(
        user_pseudo_id,
        CAST((SELECT value.int_value FROM UNNEST(event_params)
              WHERE key = 'ga_session_id') AS STRING)
      ) END) AS conversions,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY channel
)
SELECT
  channel,
  sessions,
  conversions,
  revenue,
  SAFE_DIVIDE(conversions, sessions) * 100 AS cvr,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM channel_revenue
ORDER BY revenue DESC;
```

### 広告コストデータを結合する

広告費のデータはGA4には含まれないため、別途テーブルを用意して結合します。

```sql
-- 広告コストテーブルの例
CREATE TABLE IF NOT EXISTS `project.dataset.ad_costs` (
  month STRING,
  channel STRING,
  cost FLOAT64
);

-- ROAS算出クエリ
WITH revenue AS (
  -- 上記の channel_revenue CTEと同じ
),
costs AS (
  SELECT channel, cost
  FROM `project.dataset.ad_costs`
  WHERE month = FORMAT_DATE(
    '%Y-%m', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
)
SELECT
  r.channel,
  r.sessions,
  r.conversions,
  r.revenue,
  c.cost AS ad_cost,
  SAFE_DIVIDE(r.revenue, c.cost) * 100 AS roas_pct,
  SAFE_DIVIDE(c.cost, r.conversions) AS cpa
FROM revenue r
LEFT JOIN costs c ON r.channel = c.channel
WHERE c.cost > 0
ORDER BY roas_pct DESC;
```

---

## Step 2：予算再配分ロジックを設計する

ROASだけで予算を決めると、高ROAS・低ボリュームのチャネルに偏ります。そこで、以下の3指標を組み合わせたスコアリングを行います。

| 指標 | 重み | 説明 |
|------|------|------|
| ROAS | 40% | 投資効率 |
| セッション数 | 30% | リーチ規模 |
| CVR | 30% | 転換効率 |

```python
"""
モジュール名: budget_optimizer.py
目的: チャネル別予算配分の最適化スコアを算出する
作成日: 2026-03-30
依存: pandas
"""

import pandas as pd

def calculate_allocation_score(df: pd.DataFrame) -> pd.DataFrame:
    """チャネル別の予算配分スコアを算出する"""

    # 各指標を0-1に正規化
    for col in ["roas_pct", "sessions", "cvr"]:
        min_val = df[col].min()
        max_val = df[col].max()
        df[f"{col}_norm"] = (df[col] - min_val) / (max_val - min_val) \
            if max_val > min_val else 0

    # 重み付きスコアを算出
    df["score"] = (
        df["roas_pct_norm"] * 0.4 +
        df["sessions_norm"] * 0.3 +
        df["cvr_norm"] * 0.3
    )

    # スコアに基づく予算配分比率
    total_score = df["score"].sum()
    df["allocation_pct"] = df["score"] / total_score * 100

    return df[["channel", "roas_pct", "sessions", "cvr",
               "score", "allocation_pct", "ad_cost"]]
```

---

## Step 3：現状と推奨の差分を算出する

```python
def calculate_budget_changes(
    df: pd.DataFrame, total_budget: float
) -> pd.DataFrame:
    """現在の予算配分と推奨配分の差分を算出する"""

    # 推奨予算額
    df["recommended_budget"] = (
        df["allocation_pct"] / 100 * total_budget
    ).round(0)

    # 差分
    df["budget_change"] = df["recommended_budget"] - df["ad_cost"]
    df["change_pct"] = (
        (df["budget_change"] / df["ad_cost"]) * 100
    ).round(1)

    return df.sort_values("budget_change", ascending=False)
```

---

## Step 4：Claude Codeで提案書を自動生成する

分析結果をClaude APIに渡し、経営者向けの提案書を生成します。

```python
import anthropic
import os
import json
from dotenv import load_dotenv

load_dotenv()

def generate_proposal(analysis_data: dict) -> str:
    """予算配分の提案書を自動生成する"""
    client = anthropic.Anthropic(
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    prompt = f"""
以下のEC広告チャネル別パフォーマンスデータに基づき、
予算配分の見直し提案書をMarkdown形式で作成してください。

## データ
{json.dumps(analysis_data, ensure_ascii=False, indent=2)}

## 提案書の構成
1. エグゼクティブサマリ（3行以内）
2. 現状分析
   - チャネル別ROAS一覧（テーブル）
   - 課題のあるチャネルの特定
3. 予算再配分の提案
   - 現在の配分と推奨配分の比較テーブル
   - 増額チャネルの根拠
   - 減額チャネルの根拠
4. 期待される効果
   - 推定売上増加額
   - 推定ROAS改善幅
5. 実行上の注意点

金額はカンマ区切り、割合は小数点1桁まで表示してください。
数値のインパクトが伝わるように記載してください。
"""

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=4096,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )
    return message.content[0].text
```

:::message
提案書の生成にはClaude APIを使用しています。APIキーは `.env` ファイルに記載し、コードにハードコードしないでください。
:::

---

## Step 5：メインスクリプトで一気通貫実行

```python
from google.cloud import bigquery

def main():
    """予算最適化提案の自動生成メインフロー"""
    # 1. BigQueryからROASデータを取得
    print("チャネル別ROASを算出中...")
    client = bigquery.Client()
    roas_query = open("queries/channel_roas.sql").read()
    df = client.query(roas_query).to_dataframe()

    # 2. 予算配分スコアを算出
    print("予算配分スコアを算出中...")
    scored_df = calculate_allocation_score(df)

    # 3. 予算変更額を算出
    total_budget = df["ad_cost"].sum()
    result_df = calculate_budget_changes(scored_df, total_budget)

    # 4. Claude APIで提案書を生成
    print("提案書を生成中...")
    analysis_data = {
        "total_budget": total_budget,
        "channels": result_df.to_dict(orient="records")
    }
    proposal = generate_proposal(analysis_data)

    # 5. ファイルに保存
    from datetime import date
    output_path = f"reports/budget_proposal_{date.today()}.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(proposal)
    print(f"提案書を保存しました: {output_path}")

if __name__ == "__main__":
    main()
```

---

## 生成される提案書の例

```markdown
# 広告予算配分 見直し提案書（2026年3月実績ベース）

## エグゼクティブサマリ
現在の広告費100万円の配分を見直し、ROAS効率の高いチャネルに
予算を寄せることで、月間売上を推定15〜20万円改善できる見込みです。

## 現状分析
| チャネル | 広告費 | 売上 | ROAS | CVR |
|---------|--------|------|------|-----|
| google / cpc | ¥500,000 | ¥1,500,000 | 300% | 2.1% |
| yahoo / cpc | ¥200,000 | ¥320,000 | 160% | 0.8% |
| instagram / paid | ¥200,000 | ¥480,000 | 240% | 1.5% |
| facebook / paid | ¥100,000 | ¥120,000 | 120% | 0.5% |

## 予算再配分の提案
| チャネル | 現在 | 推奨 | 差分 |
|---------|------|------|------|
| google / cpc | ¥500,000 | ¥520,000 | +¥20,000 |
| instagram / paid | ¥200,000 | ¥280,000 | +¥80,000 |
| yahoo / cpc | ¥200,000 | ¥150,000 | -¥50,000 |
| facebook / paid | ¥100,000 | ¥50,000 | -¥50,000 |
```

---

## 運用上の注意点

### 1. ROASだけで判断しない

認知系チャネル（ディスプレイ広告、SNS広告）はラストクリックベースのROASが低くなりがちですが、ファネル上部での貢献がある場合もあります。アトリビューション分析と組み合わせて判断してください。

### 2. 予算変更は段階的に

提案書の通りに一度に大きく予算を動かすのではなく、2〜4週間かけて段階的に変更し、効果を確認しながら進めるのが安全です。

### 3. 月次で継続実行する

広告のパフォーマンスは時期によって変動します。月次で自動実行し、トレンドの変化を継続的に捉えることが重要です。

### 4. 広告プラットフォームの制約を考慮する

予算を減らしたチャネルでは、最低入札額の制約や学習期間のリセットが発生する場合があります。プラットフォーム側の仕様も確認してください。

---

## まとめ

BigQueryのGA4データからチャネル別ROASを算出し、Claude Codeで予算配分の提案書を自動生成する仕組みを作りました。

1. GA4 + 広告コストデータからROAS・CVR・セッション数を抽出する
2. 3指標のスコアリングで予算配分比率を算出する
3. Claude APIで経営者向けの提案書を自動生成する

「広告費の使い方に根拠が欲しい」という方は、まずチャネル別ROASの可視化から始めてみてください。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
