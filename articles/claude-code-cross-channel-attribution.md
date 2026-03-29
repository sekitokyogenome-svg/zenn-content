---
title: "Claude Codeでクロスチャネルアトリビューション分析を自動化した"
emoji: "🔀"
type: "tech"
topics: ["claudecode", "bigquery", "attribution"]
published: false
---

## はじめに

「広告の成果をラストクリックだけで判断していいのか、ずっと疑問だった」

ECサイトのマーケティングでは、ユーザーが複数のチャネルを経由してコンバージョンに至るケースが一般的です。しかし、GA4のデフォルトレポートではラストクリック中心の評価になりがちで、認知系チャネルの貢献が見えにくいという問題があります。

この記事では、BigQueryのGA4データを使ってマルチタッチアトリビューション分析を行い、Claude Codeで自動化した方法を紹介します。

---

## アトリビューションモデルとは

アトリビューションモデルは「コンバージョンへの貢献度を各タッチポイントにどう配分するか」を決めるルールです。

| モデル | 特徴 |
|--------|------|
| ラストクリック | 最後のタッチポイントに100%配分 |
| ファーストクリック | 最初のタッチポイントに100%配分 |
| 線形（リニア） | すべてのタッチポイントに均等配分 |
| 時間減衰 | コンバージョンに近いタッチポイントほど高く配分 |
| 接点ベース | 最初と最後に40%ずつ、残りに20%を均等配分 |

GA4はデータドリブンモデルを採用していますが、BigQueryの生データを使えば、自分で任意のモデルを実装できます。

---

## Step 1：ユーザーのタッチポイント経路を抽出する

まず、各ユーザーのセッション経路（コンバージョンまでのチャネル遷移）を抽出します。

```sql
-- ユーザーのタッチポイント経路を抽出
WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    PARSE_TIMESTAMP(
      '%Y%m%d%H%M%S',
      CONCAT(event_date, LPAD(
        CAST(EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(MINUTE FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(SECOND FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0')
      )
    ) AS session_start,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260201' AND '20260331'
  GROUP BY user_pseudo_id, session_id, session_start, channel
),
converting_users AS (
  SELECT user_pseudo_id
  FROM user_sessions
  WHERE has_purchase = 1
)
SELECT
  s.user_pseudo_id,
  s.channel,
  s.session_start,
  s.has_purchase,
  s.revenue,
  ROW_NUMBER() OVER (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.session_start
  ) AS touchpoint_order,
  COUNT(*) OVER (
    PARTITION BY s.user_pseudo_id
  ) AS total_touchpoints
FROM user_sessions s
INNER JOIN converting_users c
  ON s.user_pseudo_id = c.user_pseudo_id
ORDER BY s.user_pseudo_id, s.session_start;
```

---

## Step 2：線形モデルを実装する

線形モデルは、すべてのタッチポイントにコンバージョンの貢献度を均等に配分します。

```sql
-- 線形アトリビューション
WITH touchpoints AS (
  -- Step 1のCTEをここに入れる（省略）
),
linear_attribution AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 各タッチポイントに均等配分
    SAFE_DIVIDE(
      MAX(revenue) OVER (PARTITION BY user_pseudo_id),
      total_touchpoints
    ) AS attributed_revenue
  FROM touchpoints
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(attributed_revenue), 0) AS linear_revenue,
  ROUND(AVG(attributed_revenue), 0) AS avg_attributed_revenue
FROM linear_attribution
GROUP BY channel
ORDER BY linear_revenue DESC;
```

---

## Step 3：時間減衰モデルを実装する

時間減衰モデルでは、コンバージョンに近いタッチポイントほど高い貢献度を割り当てます。

```sql
-- 時間減衰アトリビューション
WITH touchpoints AS (
  -- Step 1のCTEをここに入れる（省略）
),
time_decay AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 指数関数的に重みを増やす（半減期7日）
    EXP(
      -0.693 * TIMESTAMP_DIFF(
        MAX(session_start) OVER (PARTITION BY user_pseudo_id),
        session_start,
        DAY
      ) / 7.0
    ) AS decay_weight
  FROM touchpoints
),
weighted AS (
  SELECT
    *,
    SAFE_DIVIDE(
      decay_weight,
      SUM(decay_weight) OVER (PARTITION BY user_pseudo_id)
    ) AS normalized_weight,
    MAX(revenue) OVER (PARTITION BY user_pseudo_id) AS total_revenue
  FROM time_decay
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(normalized_weight * total_revenue), 0) AS decay_revenue
FROM weighted
GROUP BY channel
ORDER BY decay_revenue DESC;
```

:::message
半減期の値（上記では7日）はビジネスの購買サイクルに応じて調整してください。高単価商品なら14日〜30日、日用品なら3日〜7日が目安です。
:::

---

## Step 4：Claude Codeで分析を自動化する

3つのモデルの結果を比較し、Claude Codeに解釈を任せます。

```text
以下は3つのアトリビューションモデルによるチャネル別売上配分です。

## ラストクリック
| チャネル | 売上 |
|---------|------|
| google / cpc | ¥850,000 |
| (direct) / (none) | ¥420,000 |
| yahoo / organic | ¥180,000 |

## 線形モデル
| チャネル | 売上 |
|---------|------|
| google / cpc | ¥620,000 |
| (direct) / (none) | ¥350,000 |
| instagram / social | ¥280,000 |

## 時間減衰モデル
| チャネル | 売上 |
|---------|------|
| google / cpc | ¥730,000 |
| (direct) / (none) | ¥380,000 |
| instagram / social | ¥210,000 |

以下を分析してください：
1. モデル間で評価が大きく変わるチャネルとその理由
2. 認知系チャネル（SNS、ディスプレイ）の過小評価リスク
3. 予算配分の見直し提案
```

---

## Step 5：Pythonでワンコマンド実行にする

```python
"""
モジュール名: attribution_analysis.py
目的: マルチタッチアトリビューション分析を自動実行する
作成日: 2026-03-30
依存: google-cloud-bigquery, anthropic
"""

from google.cloud import bigquery
import anthropic
import os
from dotenv import load_dotenv

load_dotenv()

def run_attribution_query(model: str) -> list:
    """指定モデルのアトリビューションSQLを実行する"""
    client = bigquery.Client()
    sql_path = f"queries/attribution/{model}.sql"
    with open(sql_path, "r") as f:
        query = f.read()
    result = client.query(query).to_dataframe()
    return result.to_dict(orient="records")

def analyze_with_claude(results: dict) -> str:
    """Claude APIでアトリビューション結果を分析する"""
    client = anthropic.Anthropic(
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    import json
    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=4096,
        messages=[{
            "role": "user",
            "content": f"""
以下のアトリビューション分析結果を比較し、
チャネル別の予算配分見直し提案を作成してください。

{json.dumps(results, ensure_ascii=False, indent=2)}
"""
        }]
    )
    return message.content[0].text

def main():
    models = ["last_click", "linear", "time_decay"]
    results = {}
    for model in models:
        print(f"{model}モデルを実行中...")
        results[model] = run_attribution_query(model)

    print("Claude APIで分析中...")
    analysis = analyze_with_claude(results)

    output_path = "reports/attribution_analysis.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(analysis)
    print(f"分析結果を保存しました: {output_path}")

if __name__ == "__main__":
    main()
```

---

## 分析で得られるインサイトの例

某ECサイトで実施した結果、以下のようなインサイトが得られました。

- **Instagram（SNS）**: ラストクリックでは売上の5%しか貢献していなかったが、線形モデルでは18%の貢献度。認知フェーズでの接触が多く、過小評価されていた
- **Google CPC**: ラストクリックでは売上の55%だが、線形モデルでは40%。刈り取りチャネルとしての役割が大きい
- **アフィリエイト**: 時間減衰モデルでの貢献度が高い。コンバージョン直前の後押しとして機能している

---

## まとめ

BigQueryのGA4データで複数のアトリビューションモデルを実装し、Claude Codeで分析を自動化しました。

1. GA4の生データからタッチポイント経路を抽出する
2. 線形・時間減衰など複数モデルをSQLで実装する
3. Claude Codeでモデル間の比較と予算配分提案を生成する

ラストクリックだけの評価に不安を感じている方は、まず線形モデルとの比較から始めてみてください。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
