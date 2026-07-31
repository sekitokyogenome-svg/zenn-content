---
title: "Claude CodeのOpenTelemetryをBigQueryに流してAIコーディングのコストと失敗を可視化する"
emoji: "🔭"
type: "tech"
topics: ["opentelemetry", "claudecode", "bigquery", "observability", "googlecloud"]
published: false
publish_queue: false
---

## はじめに

AIコーディングエージェントを日常業務に組み込むと、ほどなくして「で、これ結局いくらかかってるんだ？」という疑問にぶつかります。

月末の請求額は分かる。でも、**どのタスクが高かったのか**、**どのツール呼び出しが失敗を繰り返しているのか**、**キャッシュはちゃんと効いているのか**は分からない。ダッシュボードの合計値だけ見て「まあ、こんなもんか」と流している方も多いのではないでしょうか。

これは要するに**オブザーバビリティの問題**です。そして幸いなことに、Claude Code は OpenTelemetry をネイティブでサポートしています。メトリクス・イベント・分散トレースを OTLP で吐き出せるので、あとは受け止めて分析するだけです。

この記事では、Claude Code のテレメトリを OpenTelemetry Collector で受け、GCP 経由で **BigQuery に着地させて SQL で分析する**までを構築します。普段 GA4×BigQuery でデータ基盤を触っている人間にとっては、慣れた道具でそのまま料理できる構成です。

:::message
本記事の設定ファイルは OpenTelemetry Collector v0.115.0（contrib ディストリビューション）で `validate` と疎通を確認済みです。Claude Code 側の環境変数・メトリクス名・属性名は公式ドキュメントの記載に準拠しています。
:::

---

## 自己紹介

普段は EC 事業者向けに GA4×BigQuery のデータ基盤構築と分析を請け負っています。Looker Studio でのダッシュボード化、dbt での 3 層設計、最近は Claude Code を使った SQL 生成・レポート自動化まわりが主戦場です。

つまり「BigQuery にデータを置いて SQL で殴る」のが手癖なので、今回もその型に持ち込みます。

---

## なぜ「AIエージェントの可視化」なのか

従来のオブザーバビリティは、リクエストを受けてレスポンスを返すサーバーが対象でした。AIエージェントはここに厄介な性質を持ち込みます。

- **1回の指示のコストが数十倍ブレる** — 同じ「バグを直して」でも、5秒で終わることも、20回ツールを叩いて数ドル溶かすこともある
- **失敗が可視化されにくい** — ツール実行が失敗してもエージェントがリトライして最終的に成功するので、内部の失敗率は表に出てこない
- **コストの内訳が入れ子** — サブエージェント、スキル、MCP サーバー呼び出しが階層的に発生する

「合計いくら」ではなく「**どのプロンプトが、どの経路で、いくら使ったか**」が見えないと改善のしようがありません。これはまさにトレースとメトリクスが解く問題です。

---

## 全体構成

```text
Claude Code (OTLP)
   │
   ├─ metrics ─┐
   ├─ logs ────┼─→ OpenTelemetry Collector
   └─ traces ──┘         │
                         ├─→ Cloud Monitoring （メトリクス：アラート・監視）
                         ├─→ Cloud Trace      （トレース：1プロンプトの内訳）
                         └─→ Cloud Logging    （イベント）
                                  │
                                  └─→ ログシンク → BigQuery → SQL 分析
```

ポイントは **イベント（ログ）を BigQuery に落とす**ことです。Claude Code の `claude_code.api_request` イベントにはトークン数とコストが属性として乗っているため、ここさえ BigQuery に入れば、あとは使い慣れた SQL で好きなだけ切り刻めます。

メトリクスは Cloud Monitoring に置いてアラート用に使い、BigQuery 側は分析用と役割分担させるのがすっきりします。

---

## Step 1：Claude Code のテレメトリを有効化する

環境変数だけで有効になります。

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1

# エクスポート先
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# ツールの詳細（Bash のコマンド内容や失敗メッセージ）まで記録する
export OTEL_LOG_TOOL_DETAILS=1

# 検証中は出力間隔を短くすると即座に確認できる
export OTEL_METRIC_EXPORT_INTERVAL=10000
export OTEL_LOGS_EXPORT_INTERVAL=2000
```

取得できる主なメトリクスは以下です。

| メトリクス | 内容 |
|---|---|
| `claude_code.cost.usage` | セッションのコスト（USD） |
| `claude_code.token.usage` | 消費トークン数 |
| `claude_code.lines_of_code.count` | 変更行数 |
| `claude_code.commit.count` | 作成したコミット数 |
| `claude_code.pull_request.count` | 作成した PR 数 |
| `claude_code.session.count` | セッション数 |
| `claude_code.active_time.total` | アクティブ時間（秒） |

そして今回の主役、イベント側です。

| イベント | 内容 |
|---|---|
| `claude_code.api_request` | API リクエスト1回ごとのコスト・トークン・レイテンシ |
| `claude_code.tool_result` | ツール実行の成否・所要時間・エラー種別 |
| `claude_code.api_error` | API 呼び出しの失敗 |
| `claude_code.tool_decision` | ツール実行許可の判断 |
| `claude_code.user_prompt` | ユーザーのプロンプト送信 |

:::message alert
`OTEL_LOG_TOOL_DETAILS=1` を有効にすると、Bash で実行したコマンド文字列やツールの引数まで記録されます。便利な反面、機密情報が混ざる可能性があります。共有のバックエンドに送る場合は、この設定を入れるかどうかを必ず検討してください。また既定でも `user.email` などが送信対象になり得ます。
:::

---

## Step 2：OpenTelemetry Collector を立てる

まずローカルで「ちゃんと届いているか」を目視できる構成から始めるのが確実です。いきなり GCP に繋ぐと、届かなかったときに Claude Code 側の問題なのか Collector なのか GCP 権限なのか切り分けられなくなります。

```yaml:local-test.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
      http:
        endpoint: 127.0.0.1:4318

processors:
  batch:
    timeout: 1s

exporters:
  debug:
    verbosity: detailed
  file:
    path: ./out.jsonl

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, file]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, file]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, file]
```

起動します。

```bash
# contrib 版が必要（googlecloud exporter は contrib にのみ含まれる）
curl -sSLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.115.1/otelcol-contrib_0.115.1_linux_amd64.tar.gz
tar xzf otelcol-contrib_0.115.1_linux_amd64.tar.gz

# 設定ファイルの妥当性を先に確認できる
./otelcol-contrib validate --config local-test.yaml

./otelcol-contrib --config local-test.yaml
```

この状態で別ターミナルから Claude Code を起動して何か作業させると、`out.jsonl` にテレメトリが流れ込みます。ここで `claude_code.cost.usage` や `claude_code.tool_result` が見えれば、Claude Code 側の設定は正しいと確定できます。

---

## Step 3：GCP に送る

疎通が取れたら送り先を差し替えます。`googlecloud` exporter はトレース・メトリクス・ログの 3 シグナルすべてに対応しており、それぞれ Cloud Trace / Cloud Monitoring / Cloud Logging に着地します。

```yaml:gcp.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 65
    spike_limit_percentage: 20
  resource:
    attributes:
      - key: service.name
        value: claude-code
        action: upsert
  batch:
    timeout: 10s

exporters:
  googlecloud:
    project: your-project
    log:
      default_log_name: claude-code-otel

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [googlecloud]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [googlecloud]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [googlecloud]
```

認証はサービスアカウント経由が確実です。

```bash
gcloud iam service-accounts create otel-collector --project=your-project

for role in roles/monitoring.metricWriter roles/logging.logWriter roles/cloudtrace.agent; do
  gcloud projects add-iam-policy-binding your-project \
    --member="serviceAccount:otel-collector@your-project.iam.gserviceaccount.com" \
    --role="$role"
done

gcloud iam service-accounts keys create ./otel-sa.json \
  --iam-account=otel-collector@your-project.iam.gserviceaccount.com

export GOOGLE_APPLICATION_CREDENTIALS=./otel-sa.json
./otelcol-contrib --config gcp.yaml
```

`memory_limiter` を入れておくのは実運用上わりと大事で、これが無いとバックエンド側が詰まったときに Collector がメモリを食い潰します。

---

## Step 4：Cloud Logging から BigQuery へシンクする

ここが BigQuery に持ち込む肝です。ログシンクを作ると、以後のログエントリが自動的に BigQuery のテーブルへ流れ込みます。

```bash
# 受け皿のデータセット
bq --location=asia-northeast1 mk --dataset your-project:claude_code_otel

# シンク作成
gcloud logging sinks create claude-code-to-bq \
  bigquery.googleapis.com/projects/your-project/datasets/claude_code_otel \
  --log-filter='logName:"claude-code-otel"' \
  --project=your-project
```

作成時に出力されるサービスアカウントに、データセットへの書き込み権限を付与します。

```bash
# 出力された writerIdentity を控えて付与する
gcloud projects add-iam-policy-binding your-project \
  --member="serviceAccount:<出力されたwriterIdentity>" \
  --role="roles/bigquery.dataEditor"
```

:::message
シンクは**作成後に発生したログ**にのみ適用されます。過去分は遡って入りません。先にシンクを作ってから Claude Code を回し始めるのが正解です。
:::

---

## Step 5：BigQuery で分析する

### まずテーブル構造を確認する

ログシンク経由のテーブルは、ログの中身に応じてスキーマが自動生成されます。属性が `jsonPayload` の下に入るのか `labels` に入るのかは、Collector のバージョンやログの形で変わります。**最初に必ず実物を1行見てください。**

```sql
SELECT *
FROM `your-project.claude_code_otel.claude_code_otel_*`
LIMIT 1;
```

```sql
-- カラム名を一覧で確認する
SELECT column_name, data_type
FROM `your-project.claude_code_otel.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'claude_code_otel_%'
ORDER BY ordinal_position;
```

以下の SQL は属性が `jsonPayload.attributes` 配下に入る前提で書いています。実際の構造に合わせてパスを読み替えてください。

### ① 日別・モデル別のコスト推移

```sql
SELECT
  DATE(timestamp, 'Asia/Tokyo') AS dt,
  JSON_VALUE(jsonPayload.attributes, '$.model') AS model,
  COUNT(*) AS requests,
  ROUND(SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.cost_usd') AS FLOAT64)), 4) AS cost_usd,
  SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.input_tokens')  AS INT64)) AS input_tokens,
  SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.output_tokens') AS INT64)) AS output_tokens
FROM `your-project.claude_code_otel.claude_code_otel_*`
WHERE JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'api_request'
  AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 30 DAY)
GROUP BY dt, model
ORDER BY dt DESC, cost_usd DESC;
```

### ② キャッシュがどれだけ効いているか

プロンプトキャッシュはコストに直結します。`cache_read_tokens` の比率が低いなら、セッションの回し方に改善余地があります。

```sql
SELECT
  DATE(timestamp, 'Asia/Tokyo') AS dt,
  SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.input_tokens') AS INT64))           AS input_tokens,
  SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.cache_read_tokens') AS INT64))     AS cache_read,
  SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.cache_creation_tokens') AS INT64)) AS cache_creation,
  ROUND(
    SAFE_DIVIDE(
      SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.cache_read_tokens') AS INT64)),
      SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.input_tokens') AS INT64))
    ) * 100, 1
  ) AS cache_hit_pct
FROM `your-project.claude_code_otel.claude_code_otel_*`
WHERE JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'api_request'
GROUP BY dt
ORDER BY dt DESC;
```

### ③ どのツールが失敗しているか

これが個人的に一番効きました。エージェントはツールが失敗しても勝手にリトライして最終的に成功させてしまうので、**失敗は表に出てきません**。しかし失敗はそのままトークンの浪費です。

```sql
SELECT
  JSON_VALUE(jsonPayload.attributes, '$.tool_name')  AS tool_name,
  JSON_VALUE(jsonPayload.attributes, '$.error_type') AS error_type,
  COUNT(*) AS n,
  ROUND(AVG(CAST(JSON_VALUE(jsonPayload.attributes, '$.duration_ms') AS INT64))) AS avg_ms
FROM `your-project.claude_code_otel.claude_code_otel_*`
WHERE JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'tool_result'
  AND JSON_VALUE(jsonPayload.attributes, '$.success') = 'false'
GROUP BY tool_name, error_type
ORDER BY n DESC
LIMIT 20;
```

ツール別の成功率も並べて見ておきます。

```sql
SELECT
  JSON_VALUE(jsonPayload.attributes, '$.tool_name') AS tool_name,
  COUNT(*) AS calls,
  COUNTIF(JSON_VALUE(jsonPayload.attributes, '$.success') = 'false') AS failures,
  ROUND(
    COUNTIF(JSON_VALUE(jsonPayload.attributes, '$.success') = 'false') / COUNT(*) * 100, 1
  ) AS failure_pct
FROM `your-project.claude_code_otel.claude_code_otel_*`
WHERE JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'tool_result'
GROUP BY tool_name
HAVING calls >= 10
ORDER BY failure_pct DESC;
```

### ④ 「高かったプロンプト」を特定する

`prompt.id` は、1つのユーザープロンプトから派生したすべてのイベントに付与される UUID です。これを使うと **「あの指示、結局いくらかかったの？」に答えられます**。

```sql
WITH per_prompt AS (
  SELECT
    JSON_VALUE(jsonPayload.attributes, '$."prompt.id"') AS prompt_id,
    MIN(timestamp) AS started_at,
    SUM(CASE WHEN JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'api_request'
             THEN CAST(JSON_VALUE(jsonPayload.attributes, '$.cost_usd') AS FLOAT64) END) AS cost_usd,
    COUNTIF(JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'api_request')  AS api_calls,
    COUNTIF(JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'tool_result')  AS tool_calls,
    COUNTIF(JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'tool_result'
            AND JSON_VALUE(jsonPayload.attributes, '$.success') = 'false')         AS tool_failures
  FROM `your-project.claude_code_otel.claude_code_otel_*`
  WHERE JSON_VALUE(jsonPayload.attributes, '$."prompt.id"') IS NOT NULL
  GROUP BY prompt_id
)
SELECT *
FROM per_prompt
ORDER BY cost_usd DESC
LIMIT 20;
```

コストの高い順に並べて `tool_failures` が多いものを見ると、「エージェントが同じところで空回りしていた」プロンプトが浮かび上がります。ここがプロンプト改善や `CLAUDE.md` 整備の投資先になります。

### ⑤ サブエージェント・スキル・MCP の内訳

`api_request` には `agent.name` / `skill.name` / `mcp_server.name` / `query_source` が乗るので、コストを構成要素に分解できます。

```sql
SELECT
  COALESCE(JSON_VALUE(jsonPayload.attributes, '$."agent.name"'), '(main)') AS agent,
  JSON_VALUE(jsonPayload.attributes, '$.query_source') AS query_source,
  COUNT(*) AS requests,
  ROUND(SUM(CAST(JSON_VALUE(jsonPayload.attributes, '$.cost_usd') AS FLOAT64)), 4) AS cost_usd
FROM `your-project.claude_code_otel.claude_code_otel_*`
WHERE JSON_VALUE(jsonPayload.attributes, '$."event.name"') = 'api_request'
GROUP BY agent, query_source
ORDER BY cost_usd DESC;
```

サブエージェントは並列で走らせると便利ですが、その分コストも積み上がります。「便利だから」で多用していたものが実際いくらだったのかが、ここで数字になります。

---

## 分散トレース（beta）で1プロンプトの中身を見る

SQL で「どのプロンプトが高いか」を特定したら、次はその中身をトレースで追います。

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1
export OTEL_TRACES_EXPORTER=otlp
```

これでプロンプトから API 呼び出し・ツール実行までが span として繋がります。

```text
claude_code.interaction     ← ユーザープロンプト1回
├── claude_code.llm_request ← モデル呼び出し
├── claude_code.tool        ← ツール実行
├── claude_code.llm_request
└── claude_code.tool
```

Cloud Trace のウォーターフォールで見ると、待ち時間がモデル推論なのかツール実行なのかが一目で分かります。「体感が遅い」の正体がテストの実行時間だった、というようなことが可視化されます。

:::message
beta 機能のため、仕様が変わる可能性があります。恒久的なダッシュボードを組むより、まずは調査用途で使うのが無難です。
:::

---

## ハマりどころ

**1. BigQuery にデータが来ない**
シンクは作成後のログにしか適用されません。また `--log-filter` が `default_log_name` と一致していないと何も流れません。まず Cloud Logging のコンソールで該当ログが見えているかを確認し、そこから下流を辿るのが早いです。

**2. Collector は contrib 版が必要**
`googlecloud` exporter はコアの Collector には入っていません。`otelcol` ではなく `otelcol-contrib` を使います。設定は `validate` サブコマンドで起動前に検査できます。

**3. スキーマが想定と違う**
ログシンクのテーブルは自動生成なので、属性の入り方が環境によって変わります。SQL を書く前に `INFORMATION_SCHEMA.COLUMNS` を見るのが確実です。日付シャードテーブルになるため、ワイルドカード `_*` での参照と `_TABLE_SUFFIX` での絞り込みを忘れるとスキャン量が膨らみます。

**4. テレメトリ自体のコスト**
Cloud Logging も BigQuery も従量課金です。エクスポート間隔を短くしたまま放置しないこと、シンクのフィルタを絞ることを意識してください。

---

## 実際に運用してみて

【要差し替え：実測値】
このセクションには、実際に自分の環境で1〜2週間回して得られた数字を入れてください。具体的には以下があると説得力が出ます。

- 期間中の総コストと、その内訳（モデル別 / サブエージェント別）
- キャッシュヒット率の実測値
- 最も失敗率が高かったツールと、そのエラー種別
- 最もコストが高かったプロンプトの正体と、そこから何を改善したか
- 改善前後でのコスト・失敗率の変化

【ここまで要差し替え】

---

## まとめ

- Claude Code は OpenTelemetry をネイティブサポートしており、環境変数だけでメトリクス・イベント・トレースを出せる
- `googlecloud` exporter で GCP に送り、Cloud Logging のシンク経由で BigQuery に着地させれば、使い慣れた SQL で分析できる
- `prompt.id` による相関が強力で、「1つの指示にいくらかかったか」を単位にできる
- ツールの失敗率は普段見えないが、そのままトークンの浪費になっている

AIエージェントは「便利だから使う」フェーズから「コストと品質を管理して使う」フェーズに移りつつあります。計測できないものは改善できないので、まずは可視化から始めるのが結局のところ近道でした。

データ基盤をやっている人間にとっては、送り先が BigQuery になった時点でいつもの仕事です。既存の SQL とダッシュボードの資産をそのまま流用できるのが、この構成の一番おいしいところだと思います。
