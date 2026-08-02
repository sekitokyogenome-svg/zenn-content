---
title: "BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する"
emoji: "🏷️"
type: "tech"
topics: ["bigquery","googlecloud","cost","dataengineering","sql"]
published: false
---

## はじめに

「BigQueryの請求額が膨らんでいるのに、どの部署・どのプロジェクトが原因なのかわからない」——そのような悩みを抱えていませんか？Google Cloudを複数プロジェクトにわたって活用している組織では、BigQueryのコストが一つの請求書にまとまってしまい、責任部署ごとに費用を按分することが難しくなりがちです。

特に、ECサイトの分析チームとマーケティングチームが同じBigQueryプロジェクトを共有していたり、複数のクライアント案件を1つのGCPプロジェクトで動かしていたりするケースでは、「どのクエリが・誰のために・いくら消費したか」を把握することが事業上の重要課題になります。

そこで活用したいのが、BigQueryの**ラベル（Labels）機能**です。ラベルはクエリジョブやデータセット、テーブルに任意のキーと値のペアを付与できる仕組みで、Cloud Billingのエクスポートデータと組み合わせることで、コストをチーム・用途・プロジェクト単位で可視化・自動配分することができます。本記事では、ラベルの基本設定から実践的なコスト分析SQLまで、順を追って解説します。

## BigQueryラベルとは何か

BigQueryのラベルとは、GCPリソースに付与できるキーと値（Key-Value）形式のメタデータです。たとえば `team:marketing`、`env:production`、`purpose:ga4-analysis` のような形で、用途やオーナーを示す情報をリソースに紐づけられます。

ラベルを設定できる対象は以下のとおりです。

- **クエリジョブ**：SQLを実行する際にジョブオプションとしてラベルを付与
- **データセット**：データセット単位でラベルを管理
- **テーブル・ビュー**：テーブルごとにラベルを設定

ラベルはCloud Billingのエクスポート先（BigQuery）に自動的に含まれるため、後から「このラベルが付いたジョブだけのコストを集計する」という操作がSQLで行えるようになります。設定コストはほぼゼロで、すでにBigQueryを利用している組織であれば今日から導入できます。

:::message
ラベルのキー・値は英小文字、数字、ハイフン、アンダースコアのみ使用可能です。スペースや大文字が含まれると設定時にエラーになるため、命名規則を事前にチームで統一しておくことをお勧めします。
:::

## クエリジョブへのラベル付与方法

クエリ実行時にラベルを付与するには、SQLの先頭に `SET @@query_label` を使う方法と、APIやクライアントライブラリ経由でジョブオプションに指定する方法があります。以下はGA4のBigQueryエクスポートデータを集計するクエリにラベルを付与する例です。

```sql
-- ジョブラベルを設定してからクエリを実行する例（BigQuery Console）
-- ※BigQuery ConsoleではジョブラベルはAPIまたはbqコマンド経由で付与します
-- 以下はbqコマンドでラベル付きジョブとして実行する例のイメージです

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

```bash
# bqコマンドでラベルを付与してクエリを実行する例
bq query \
  --label="team:marketing" \
  --label="purpose:ga4-analysis" \
  --label="env:production" \
  --use_legacy_sql=false \
  'SELECT ... FROM `your_project.analytics_XXXXXXXXX.events_*` ...'
```

Pythonのgoogle-cloud-bigqueryライブラリを使う場合は、`QueryJobConfig` に `labels` 辞書を渡すことでジョブラベルを設定できます。

```python
from google.cloud import bigquery

client = bigquery.Client()

job_config = bigquery.QueryJobConfig(
    labels={
        "team": "marketing",
        "purpose": "ga4-analysis",
        "env": "production"
    }
)

query = """
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'session_start'
GROUP BY medium, source
"""

job = client.query(query, job_config=job_config)
results = job.result()
```

このようにラベルを付与しておくと、後からコスト集計を行う際に「このラベルのジョブだけ抽出する」という操作が可能になります。

## ラベル別コストを集計するSQL

Cloud BillingのエクスポートをBigQueryに連携している場合、以下のようなSQLでラベル別のコストを集計できます。

```sql
-- Cloud Billing エクスポートテーブルからラベル別コストを集計
SELECT
  (SELECT value FROM UNNEST(labels) WHERE key = 'team') AS team,
  (SELECT value FROM UNNEST(labels) WHERE key = 'purpose') AS purpose,
  SUM(cost) AS total_cost_usd,
  SUM(cost) * 150 AS total_cost_jpy_approx  -- 概算換算（為替レートは適宜変更）
FROM
  `your_billing_project.billing_dataset.gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX`
WHERE
  service.description = 'BigQuery'
  AND DATE(_PARTITIONTIME) BETWEEN '2024-06-01' AND '2024-06-30'
GROUP BY
  team, purpose
ORDER BY
  total_cost_usd DESC
```

このクエリを実行すると、`team:marketing` のジョブが先月いくら消費したか、`purpose:ga4-analysis` に関するクエリのコストはいくらかといった情報をひと目で把握できます。部署ごとに予算を設けている組織では、このデータをもとに月次レポートを自動生成するパイプラインを組むことも可能です。

:::message
Cloud Billingのエクスポートは設定後しばらく（数時間〜1日程度）データが反映されるまでに時間がかかります。分析を開始する前に、エクスポート先のBigQueryテーブルにデータが蓄積されているか確認してください。
:::

## プロジェクト横断でのコスト配分を自動化するポイント

ラベル管理を組織全体で機能させるためには、以下のポイントを意識した運用設計が重要です。

**1. 命名規則をドキュメント化する**
ラベルのキーと値の命名規則を組織のWikiや共有ドキュメントにまとめておきましょう。たとえば `team` キーの値は `marketing`、`analytics`、`engineering` の3種類のみ許容する、といったルールを明文化することで、集計時に表記ゆれが起きにくくなります。

**2. Cloud Functionsで自動ラベリングを検討する**
すべてのクエリに手動でラベルを付与するのは現実的ではありません。定期バッチや特定のデータパイプラインであれば、Cloud Functionsや Cloud Composer（Airflow）のジョブオプションとしてラベルを標準設定しておくことで、作業者の意識に依存せず一貫したラベリングが実現します。

**3. INFORMATION_SCHEMAで実行ジョブを事後確認する**
Cloud BillingエクスポートとあわせてBigQueryの `INFORMATION_SCHEMA.JOBS_BY_PROJECT` ビューを参照すると、ジョブ単位のバイトスキャン量・ラベル・実行ユーザーを横断的に確認できます。ラベルが付与されていないジョブを検出するモニタリングクエリを組むことで、ラベリング漏れを早期に発見できます。

```sql
-- ラベルが付与されていないBigQueryジョブを検出するクエリ
SELECT
  job_id,
  user_email,
  total_bytes_processed,
  creation_time,
  labels
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
  DATE(creation_time) = CURRENT_DATE() - 1
  AND ARRAY_LENGTH(labels) = 0
  AND job_type = 'QUERY'
ORDER BY
  total_bytes_processed DESC
LIMIT 50
```

このクエリを日次で実行して結果をSlackやメールに通知するだけでも、ラベリング遵守率が大きく向上します。

## まとめ

BigQueryのラベル機能は、設定方法がシンプルでありながら、プロジェクト横断のコスト配分という複雑な課題に対して実践的なアプローチを提供します。本記事のポイントを整理すると以下のとおりです。

- ラベルはクエリジョブ・データセット・テーブルに付与でき、Cloud Billingエクスポートと組み合わせることでコストをチーム・用途単位で集計できる
- bqコマンドやPythonライブラリを使えば、既存のバッチ処理にラベルをほぼ無停止で追加できる
- 命名規則の統一と自動ラベリングの仕組みを整えることで、運用負担を最小化しながら継続的なコスト可視化が実現する
- `INFORMATION_SCHEMA.JOBS_BY_PROJECT` を使ったラベリング漏れ検出により、運用品質を維持しやすくなる

次のアクションとして、まず1つのチームや1つの用途に絞ってラベルを試験的に付与し、Cloud BillingエクスポートのSQLでコストが正しく集計されることを確認してみてください。小さな範囲での検証が、組織全体への展開への最短の近道です。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
