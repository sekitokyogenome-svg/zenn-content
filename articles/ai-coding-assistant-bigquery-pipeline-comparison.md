---
title: "AIコーディングアシスタント3種でBigQueryのデータパイプラインを作り比べた"
emoji: "⚔️"
type: "idea"
topics: ["bigquery","ai","claude","gemini","dataengineering"]
published: false
---

## はじめに

「GA4のデータをBigQueryに貯めてはいるものの、そこから先をどうすればいいかわからない」——そんな声をECサイトのオーナーやWebコンサルタントの方から多くいただきます。BigQueryにエクスポートされたデータは、そのままではLooker Studioで可視化しにくく、毎日集計するためのパイプラインが別途必要になります。

かつては、こうした処理の自動化にはエンジニアへの依頼が欠かせませんでした。しかし、AIコーディングアシスタントの台頭によって、「SQLをある程度読めるレベルのビジネスパーソン」でも、データパイプラインを自分で構築できる環境が整いつつあります。

今回は実際に **Claude（Anthropic）**・**Gemini（Google）**・**ChatGPT（OpenAI）** の3種類のAIに、GA4×BigQueryの集計パイプライン構築を依頼し、生成されたコードの品質・対話のしやすさ・非エンジニアへの説明の丁寧さを比較しました。

同じタスクをAIに頼んでもここまで結果が変わるのか、と驚かれるかもしれません。ぜひ自社の状況に置き換えながら読み進めてみてください。

---

## 検証タスクの概要

今回AIに依頼したのは、以下の集計パイプラインの構築です。

- **データソース**: GA4のBigQueryエクスポートテーブル（`events_*`）
- **集計内容**: セッションごとの流入元・CV数を日次で集計し、Looker Studio用ビューを作成する
- **実行環境**: BigQuery（スケジュールクエリ）＋Cloud Functions（Python）

各AIには「非エンジニアのWebコンサルタントが使うことを前提に、コードと説明を一緒に提供してほしい」と指示しました。生成されたSQLやPythonは実際に筆者の環境で動作確認しています。

:::message
GA4のBigQueryエクスポートでは、`ga_session_id` をイベントパラメータとして取得する必要があります。`event_params` を `UNNEST` して取り出す点が初学者にとってつまずきやすいポイントです。
:::

---

## Claude（Anthropic）の評価

Claudeに依頼すると、まず「どのプロジェクトIDとデータセット名を使うか教えてください」と確認を求めてきました。こうした前置きのヒアリングは、後から修正が発生しにくいという点でビジネス用途に向いています。

生成されたSQLは以下のような構成でした。

```sql
-- セッション別の流入元とCV数を集計するクエリ
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date, medium, source
ORDER BY
  event_date DESC, sessions DESC
```

注目すべき点は、`ga_session_id` の取得に `UNNEST(event_params)` を使っており、GA4特有の構造を正しく扱えていることです。また、`collected_traffic_source.manual_medium` と `manual_source` を流入元に使用している点も正確です。

コード以外にも「このSQLをBigQueryのスケジュールクエリに設定する手順」を箇条書きで付け加えてくれたため、非エンジニアでも一連の流れを把握しやすい内容でした。

---

## Gemini（Google）の評価

Googleのサービスということもあり、BigQueryとGA4との親和性に期待して試してみました。結果として、SQLの構文自体は正確でしたが、`ga_session_id` の取り出し方に一点気になる書き方がありました。

最初の回答では `event_params.ga_session_id` という直接参照を試みるコードが含まれており、これはGA4のBigQueryエクスポートでは動作しない記法です。指摘したところすぐに修正してくれましたが、ファーストレスポンスで正しい `UNNEST` 構文を使っていなかった点は注意が必要です。

修正後のSQLは以下のように仕上がりました。

```sql
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNTIF(event_name = 'purchase') AS cv_count
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY 1, 2, 3
ORDER BY 1 DESC
```

修正後は正確に動作しました。GeminiはCloud ConsoleやBigQuery UIと連携したアドバイスが得意で、「このクエリをLooker Studioに繋ぐにはどうすれば？」という質問に対して、データソース設定の画面操作まで丁寧に案内してくれる場面が印象的でした。

---

## ChatGPT（OpenAI）の評価

ChatGPT（GPT-4o）はコード生成の速さと応答の流暢さが際立っていました。質問に対してすぐに長文のコードブロックを返してくれますが、逆に「最初から全部答えようとする」ため、途中の確認ステップが省かれることがありました。

生成されたPythonスクリプト（Cloud Functions向け）は以下のようなイメージです。

```python
from google.cloud import bigquery
from datetime import datetime, timedelta

def run_pipeline(request):
    client = bigquery.Client()

    yesterday = (datetime.today() - timedelta(days=1)).strftime('%Y%m%d')
    table_suffix = yesterday

    query = f"""
    SELECT
        event_date,
        collected_traffic_source.manual_medium AS medium,
        collected_traffic_source.manual_source AS source,
        COUNT(DISTINCT
            (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        ) AS sessions,
        COUNTIF(event_name = 'purchase') AS conversions
    FROM
        `your_project.analytics_XXXXXXX.events_{table_suffix}`
    GROUP BY 1, 2, 3
    """

    job_config = bigquery.QueryJobConfig(
        destination="your_project.your_dataset.daily_traffic_cv",
        write_disposition="WRITE_APPEND"
    )

    query_job = client.query(query, job_config=job_config)
    query_job.result()
    return "Pipeline completed."
```

SQLの構造は正しく、`UNNEST(event_params)` も適切に使用されています。ただし、Cloud FunctionsのデプロイやIAM設定について「詳しい手順を教えて」と聞くと、説明がやや抽象的になる傾向がありました。エラー発生時のデバッグ対話では、Claudeのほうがステップバイステップで丁寧に対応してくれると感じました。

---

## 3種を横並び比較

| 観点 | Claude | Gemini | ChatGPT |
|------|--------|--------|---------|
| 初回SQLの正確さ | ◎ | △（要修正） | ○ |
| GA4構造への対応 | ◎ | ○（修正後） | ◎ |
| 非エンジニア向け説明 | ◎ | ◎ | ○ |
| GCPサービスとの連携説明 | ○ | ◎ | ○ |
| エラー対話のしやすさ | ◎ | ○ | ○ |

総じて、ファーストレスポンスの精度と非エンジニアへの丁寧さという点ではClaudeが頭一つ抜けた印象でした。一方でGeminiはGoogle製サービスとの連携説明が強く、BigQuery・Looker Studio・Cloud Runを一気通貫で使いたい場合には相性が良いと感じます。ChatGPTはスピード感があり、コードの叩き台を素早く作りたい場面で重宝します。

---

## まとめ

今回の比較を通じて見えてきたのは、「どのAIが優れているか」ではなく、「目的と使い手のスキルに応じてAIを使い分けることが大切だ」という点です。

- **手順の丁寧さを重視するなら** → Claude
- **GCPサービスとの連携を重視するなら** → Gemini
- **素早くコードの叩き台が欲しいなら** → ChatGPT

いずれのAIを使う場合も、GA4のBigQueryエクスポート特有の構造（`UNNEST(event_params)` による `ga_session_id` の取得、`collected_traffic_source` による流入元取得など）は、人間側が把握しておくことでAIの出力を正しく検証できます。

まずは小さなSQLから試し、AIとの対話を重ねながら自社のパイプラインを育てていくアプローチが、非エンジニアにとって現実的な一歩となるでしょう。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
