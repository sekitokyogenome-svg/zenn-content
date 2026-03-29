---
title: "BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】"
emoji: "🚨"
type: "tech"
topics: ["bigquery", "claudecode", "monitoring"]
published: false
---

## はじめに

「月末の売上報告で初めて、2週間前から売上が半減していたことに気づいた」

こんな経験をしたことがあるEC事業者は少なくないはずです。GA4のダッシュボードは毎日見ていても、数値の微妙な変化には気づきにくい。特に複数チャネルを運用していると、全体の売上は横ばいでも特定チャネルだけ急落している、というケースは珍しくありません。

この記事では、**BigQueryに蓄積されたGA4データから売上・セッションの異常を自動検知し、Slack/メールで即通知する仕組み**をClaude Codeと一緒に構築する方法を解説します。

---

## 全体のアプローチ

異常検知のロジックはシンプルです。

1. 当日の売上・セッション数を取得する
2. 直近7日間の移動平均と比較する
3. 乖離率が閾値を超えたらアラートを発報する

統計的に高度な手法を使う必要はありません。移動平均との乖離率だけでも、売上急落やセッション激減のような明確な異常は十分に捕捉できます。

---

## 日次メトリクスと移動平均のSQL

まずは、日別の売上とセッション数を7日移動平均と合わせて取得するクエリです。

```sql
WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
)

SELECT
  event_date,
  sessions,
  revenue,
  AVG(sessions) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_sessions_7d,
  AVG(revenue) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_revenue_7d
FROM daily_metrics
ORDER BY event_date DESC
```

:::message
`ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING` で当日を含めない7日間の平均を算出しています。当日を含めると異常値が平均に混入してしまうため、除外するのがポイントです。
:::

---

## 異常検知ロジックのSQL

移動平均との乖離率を計算し、閾値を超えた日をフラグ付けします。

```sql
WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
  FROM
    `beeracle.analytics_263425816.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
),

with_moving_avg AS (
  SELECT
    *,
    AVG(sessions) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_sessions_7d,
    AVG(revenue) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_revenue_7d
  FROM daily_metrics
)

SELECT
  event_date,
  sessions,
  revenue,
  avg_sessions_7d,
  avg_revenue_7d,
  SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 AS session_deviation_pct,
  SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 AS revenue_deviation_pct,
  CASE
    WHEN SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) < -0.3 THEN TRUE
    WHEN SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) < -0.3 THEN TRUE
    ELSE FALSE
  END AS is_anomaly
FROM with_moving_avg
WHERE event_date = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
```

ここでは **乖離率 -30%** をデフォルトの閾値にしています。この数値は後述の閾値チューニングで調整します。

---

## Pythonスクリプト：クエリ実行 → 閾値判定 → アラート送信

BigQueryのクエリ結果を取得し、異常があればSlackとメールに通知するスクリプトです。

```python
"""
モジュール名: anomaly_alert.py
目的: BigQueryから日次メトリクスを取得し異常検知アラートを送信する
作成日: 2026-03-29
依存: google-cloud-bigquery, anthropic, slack_sdk, smtplib
"""

import os
from datetime import datetime
from google.cloud import bigquery
from slack_sdk import WebClient
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()

DEVIATION_THRESHOLD = float(os.getenv("ANOMALY_THRESHOLD", "-30"))

def run_anomaly_query():
    """BigQueryで異常検知クエリを実行し結果を返す"""
    client = bigquery.Client(project="beeracle")

    query = """
    WITH daily_metrics AS (
      SELECT
        event_date,
        COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
          (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        )) AS sessions,
        IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
      FROM `beeracle.analytics_263425816.events_*`
      WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      GROUP BY event_date
    ),
    with_moving_avg AS (
      SELECT *,
        AVG(sessions) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_sessions_7d,
        AVG(revenue) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_revenue_7d
      FROM daily_metrics
    )
    SELECT
      event_date, sessions, revenue,
      avg_sessions_7d, avg_revenue_7d,
      SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 AS session_deviation_pct,
      SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 AS revenue_deviation_pct
    FROM with_moving_avg
    WHERE event_date = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    """

    result = client.query(query).to_dataframe()
    return result

def check_anomaly(row):
    """閾値と比較して異常かどうか判定する"""
    alerts = []
    if row["session_deviation_pct"] < DEVIATION_THRESHOLD:
        alerts.append(f"セッション数が7日平均比 {row['session_deviation_pct']:.1f}% 減少")
    if row["revenue_deviation_pct"] < DEVIATION_THRESHOLD:
        alerts.append(f"売上が7日平均比 {row['revenue_deviation_pct']:.1f}% 減少")
    return alerts

def generate_alert_message(row, alerts):
    """Claude APIで人が読みやすいアラートメッセージを生成する"""
    client = Anthropic()

    prompt = f"""以下のEC売上異常データについて、日本語で簡潔なアラートメッセージを作成してください。
考えられる原因候補を3つ挙げてください。

日付: {row['event_date']}
セッション数: {row['sessions']}（7日平均: {row['avg_sessions_7d']:.0f}）
売上: ¥{row['revenue']:,.0f}（7日平均: ¥{row['avg_revenue_7d']:,.0f}）
検出された異常: {', '.join(alerts)}

フォーマット:
- 1行目にサマリ
- 箇条書きで原因候補
- 最後に推奨アクション"""

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text

def send_slack_alert(text):
    """Slackにアラートを送信する"""
    client = WebClient(token=os.getenv("SLACK_BOT_TOKEN"))
    client.chat_postMessage(
        channel=os.getenv("SLACK_ALERT_CHANNEL", "#活動ログ"),
        text=f"🚨 売上異常検知アラート\n\n{text}"
    )

def main():
    df = run_anomaly_query()
    if df.empty:
        print("データなし。スキップします。")
        return

    row = df.iloc[0]
    alerts = check_anomaly(row)

    if not alerts:
        print(f"{row['event_date']}: 異常なし")
        return

    print(f"{row['event_date']}: 異常検知 - {alerts}")
    message = generate_alert_message(row, alerts)
    send_slack_alert(message)
    print("アラート送信完了")

if __name__ == "__main__":
    main()
```

:::message alert
`ANTHROPIC_API_KEY`、`SLACK_BOT_TOKEN` などの認証情報は必ず `.env` ファイルに記載し、コードにハードコードしないでください。
:::

---

## Claude Codeで原因を推定するアラートメッセージ

上記スクリプトの `generate_alert_message` 関数では、Claude APIを使って異常値の原因候補を自動生成しています。

実際に生成されるメッセージのイメージは以下のとおりです。

```text
【売上異常検知】2026-03-28

昨日の売上が7日平均比で42%減少しました。

■ 考えられる原因
・Google広告キャンペーンの予算切れまたは配信停止
・サイトの決済導線に障害が発生している可能性
・季節要因や競合セール時期による一時的な需要減

■ 推奨アクション
→ まずGoogle広告管理画面で配信状況を確認してください
→ 決済完了率をGA4で確認し、エラーが増えていないか調査してください
```

数値の羅列だけでなく「何を確認すべきか」までメッセージに含めることで、アラートを受け取った後の初動が速くなります。

---

## スケジュール実行の設定

毎朝自動でチェックを走らせるには、Cloud SchedulerまたはCronを利用します。

### Cloud Scheduler + Cloud Functions の場合

```bash
# Cloud Functionsにデプロイ
gcloud functions deploy anomaly_alert \
  --runtime python311 \
  --trigger-http \
  --entry-point main \
  --region asia-northeast1 \
  --set-env-vars ANOMALY_THRESHOLD=-30

# Cloud Schedulerでジョブ作成（毎朝9時JST）
gcloud scheduler jobs create http anomaly-check-daily \
  --schedule="0 9 * * *" \
  --time-zone="Asia/Tokyo" \
  --uri="https://asia-northeast1-beeracle.cloudfunctions.net/anomaly_alert" \
  --http-method=POST
```

### ローカルCronの場合

```bash
# crontab -e で以下を追加（毎朝9時に実行）
0 9 * * * cd /path/to/project && /usr/bin/python3 anomaly_alert.py >> logs/anomaly.log 2>&1
```

:::message
GA4のBigQueryエクスポートは日次の場合、前日分のデータが翌朝に反映されます。朝9時であれば前日分のデータは揃っている前提で問題ありません。
:::

---

## 閾値チューニングで誤検知を減らす

閾値を厳しくしすぎると毎日アラートが飛び、緩すぎると本当の異常を見逃します。以下の考え方で調整するのが実用的です。

**初期値の目安**

| メトリクス | 閾値 | 根拠 |
|---|---|---|
| セッション数 | -30% | 曜日変動を考慮してもこの水準の減少は異常 |
| 売上 | -30% | 売上は変動幅が大きいため、セッションと同じかやや緩めに |

**チューニングの手順**

1. まず `-30%` で1-2週間運用する
2. 誤検知（アラートが出たが実際は問題なし）が多い場合は `-40%` に緩める
3. 見逃し（異常があったのにアラートが出なかった）があれば `-20%` に締める
4. 曜日による変動が大きいサイトは、曜日別の移動平均に切り替える

```sql
-- 曜日別移動平均にする場合のウィンドウ関数
AVG(sessions) OVER (
  PARTITION BY EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d', event_date))
  ORDER BY event_date
  ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
) AS avg_sessions_same_dow
```

また、セールやキャンペーン期間中はアラートを一時停止する仕組みも検討してください。意図的に数値が跳ねる時期にアラートが鳴り続けると、オオカミ少年状態になり、本当の異常時に反応が遅れます。

---

## まとめ

BigQueryに蓄積されているGA4データを活用すれば、移動平均と乖離率というシンプルなロジックで売上・セッションの異常検知が実現できます。

- **SQL**で移動平均と乖離率を算出
- **Python**で閾値判定とSlack通知を自動化
- **Claude API**で原因候補と推奨アクションを含む人間向けメッセージを生成
- **Cloud Scheduler**で毎朝自動チェック

「気づいたら手遅れだった」を防ぐための仕組みとして、ぜひ導入を検討してみてください。

---

GA4 × BigQueryの基盤構築やアラート設計について相談したい方は、以下からお気軽にどうぞ。

https://coconala.com/services/554778
