---
title: "Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み"
emoji: "🔍"
type: "tech"
topics: ["claude","googleanalytics","bigquery","ai","gtm"]
published: false
---

## はじめに

「GA4のダッシュボードを見ても、どのデータが正しくてどこが欠けているのかわからない」——そんなお悩みを抱えていませんか？

GA4は柔軟なイベント設計が可能な反面、計測設定のミスや抜け漏れが発生しやすい仕組みでもあります。特にGTM（Googleタグマネージャー）でタグを追加・変更した際に、一部のページやデバイスでのみイベントが飛ばなくなるケースは珍しくありません。それに気づかないまま施策の判断をしてしまうと、誤った意思決定につながるリスクがあります。

本記事では、**Claude Code**（AIコーディングアシスタント）とGA4のBigQueryエクスポートデータを組み合わせて、イベント計測の漏れを自動で検知し、修正提案まで行う仕組みをご紹介します。エンジニアでなくても概念を理解いただけるよう、SQLとPythonのサンプルを交えながら丁寧に解説していきます。

---

## GA4のイベント計測漏れが起きやすい典型パターン

GA4では、発火するイベントごとにデータが蓄積されていきます。しかしBigQueryエクスポートのデータを確認すると、「特定の日だけevent_nameが消えている」「特定のデバイスでのみconversionイベントが記録されていない」といった現象が頻繁に見つかります。

主な原因としては、以下が挙げられます。

- GTMのタグ設定変更後に一部トリガーが機能しなくなった
- SPAサイト（シングルページアプリケーション）でのページ遷移を正しく検知できていない
- iOS・Safariのプライバシー制限によりイベントがブロックされている
- dataLayerへのプッシュタイミングのズレ

こうしたケースは、GA4の管理画面だけを見ていると気づきにくいのが難点です。BigQueryにエクスポートされた生データを分析することで、初めて「どの日から」「どのイベントが」「どのデバイスで」欠けているかを特定できます。

---

## BigQueryでイベント計測漏れを検知するSQL

まず、日次でイベントの発火件数を集計し、急激な減少がないか確認します。以下のSQLはGA4のBigQueryエクスポートテーブルを対象にしています。

```sql
-- イベント別・日別の発火件数推移を集計
SELECT
  event_date,
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS session_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date,
  event_name
ORDER BY
  event_name,
  event_date
```

このクエリで取得したデータをClaude Codeに渡すと、「直近7日間で`purchase`イベントが前週比50%以上減少している日があります。GTMの変更履歴と照合することを推奨します」といった分析コメントを自動生成させることができます。

さらに、流入元ごとに計測状況を比較したい場合は、`collected_traffic_source`を活用します。

```sql
-- 流入元別にイベント発火件数を集計
SELECT
  event_date,
  event_name,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name IN ('add_to_cart', 'begin_checkout', 'purchase')
GROUP BY
  event_date,
  event_name,
  medium,
  source
ORDER BY
  event_date,
  event_name
```

「メール流入のユーザーだけ`begin_checkout`が発火していない」というような流入元固有の問題も、このクエリで浮かび上がらせることができます。

---

## Claude Codeに分析・修正提案をさせる方法

BigQueryからCSVやJSON形式でデータを取得したら、それをClaude Codeのコンテキストとして渡します。Claude Codeはターミナル上で動作するAIアシスタントであり、データを読み込んだうえで「何が異常か」「なぜそうなっているか」「どう修正すればよいか」を自然言語で提案してくれます。

以下は、PythonでBigQueryからデータを取得し、Claude Code（Anthropic APIを使用）に解析させるシンプルなスクリプト例です。

```python
import anthropic
from google.cloud import bigquery
import json

# BigQueryからイベントデータを取得
bq_client = bigquery.Client(project="your_project")
query = """
SELECT
  event_date,
  event_name,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date,
  event_name
ORDER BY
  event_date, event_name
"""
df = bq_client.query(query).to_dataframe()
event_json = df.to_json(orient="records", force_ascii=False)

# Claude Codeで分析・提案
client = anthropic.Anthropic()
message = client.messages.create(
    model="claude-opus-4-5",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": f"""
以下はGA4のイベント発火データ（直近14日間）です。
計測漏れや異常な減少がないか分析し、原因の仮説と修正提案を日本語で出力してください。

{event_json}
"""
        }
    ]
)
print(message.content[0].text)
```

このスクリプトを定期実行（例：毎朝Cronで動かす）することで、計測の異常を翌朝には把握できる体制を作れます。

:::message
スクリプトを実行するには、Google CloudのサービスアカウントキーとAnthropicのAPIキーが必要です。各種権限設定については公式ドキュメントをご参照ください。
:::

---

## 検知結果をSlackやメールで通知する

分析結果をターミナルで確認するだけでなく、Slackやメールで自動通知する仕組みを加えると、非エンジニアの担当者にも共有しやすくなります。

```python
import smtplib
from email.mime.text import MIMEText

def send_alert(subject: str, body: str, to_address: str):
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = "alert@example.com"
    msg["To"] = to_address

    with smtplib.SMTP_SSL("smtp.example.com", 465) as smtp:
        smtp.login("alert@example.com", "your_password")
        smtp.send_message(msg)

# 前日のevent_countが前週同曜日比で40%以上減少していた場合にアラートを送信
threshold = 0.6  # 60%未満なら異常とみなす
for _, row in df.iterrows():
    if row["event_count_ratio"] < threshold:
        send_alert(
            subject=f"[GA4アラート] {row['event_name']} の計測が減少しています",
            body=f"イベント名: {row['event_name']}\n日付: {row['event_date']}\n前週比: {row['event_count_ratio']:.0%}",
            to_address="your_team@example.com"
        )
```

このようなアラートがあれば、「計測が壊れたまま1週間気づかなかった」という事態を防ぎやすくなります。

---

## GTM修正案をClaude Codeに生成させる

計測漏れが特定できたら、次はGTMの修正方針を考える必要があります。Claude Codeに対して「どのタグ・トリガーを見直すべきか」を質問すると、設定ミスのよくあるパターンをもとにした提案を返してくれます。

たとえば「`purchase`イベントがSafariでのみ発火しない」という状況を伝えると、以下のような提案が返ってくることがあります。

- GTMのカスタムHTMLタグでdocument.writeを使用していないか確認する
- dataLayerへのプッシュがページロード完了前に行われていないか確認する
- iOS Safariでのサードパーティクッキー制限によりセッションが引き継がれていない可能性を検討する
- GTMのデバッグモードでSafari実機テストを実施する

AIが完全な回答を出すわけではありませんが、「何を確認すべきか」の道筋をスピーディに絞り込めるのは大きな利点です。担当者がGTMの設定を見直す際の出発点として活用できます。

---

## まとめ

本記事では、GA4のイベント計測漏れをClaude CodeとBigQueryを組み合わせて自動検知・修正提案する仕組みをご紹介しました。

**要点の整理：**

- GA4の計測漏れはBigQueryの生データを分析することで初めて可視化できる
- `UNNEST(event_params)`でga_session_idを取得し、`collected_traffic_source`で流入元を把握する
- BigQueryから取得したデータをClaude Codeに渡すことで、異常の分析と修正提案を自動化できる
- Cronとメール通知を組み合わせることで、毎朝の定点観測フローを構築できる

**次のアクション：**

1. GA4のBigQueryエクスポートが有効になっているか確認する
2. 本記事のSQLをBigQueryコンソールで実行し、自社データを確認してみる
3. 異常があればClaude Codeに状況を伝え、修正の方向性を相談してみる

GA4の計測データは正確であって初めて意思決定に使えます。AIを活用した自動検知の仕組みを取り入れることで、データ品質の維持に割くコストを削減しながら、精度の高い分析基盤を維持していただければ幸いです。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
