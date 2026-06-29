---
title: "OpenTelemetry入門：分散トレーシングとメトリクスをPythonで実装する"
emoji: "🔭"
type: "tech"
topics: ["opentelemetry", "observability", "python", "monitoring", "trace"]
published: true
---

## はじめに

マイクロサービスやサーバーレスが当たり前になった今、「リクエストが遅い」という一報に対して、**どのサービスのどの処理がボトルネックなのか**を即座に特定できるかどうかが、運用の質を大きく左右します。

ところが、サービスごとに監視ツールがバラバラだったり、ログ・メトリクス・トレースが別々のフォーマットで散らばっていたりすると、調査に何時間もかかってしまいます。

この問題を解決するために生まれたのが **OpenTelemetry（OTel）** です。この記事では、

- OpenTelemetryとは何か、なぜ標準として支持されているのか
- Traces / Metrics / Logs という3つのシグナルの違い
- Pythonでの計装（instrumentation）の実装
- OpenTelemetry Collectorによるデータの集約・転送

を、実際に動くコードとともに解説します。

---

## OpenTelemetryとは

OpenTelemetry は、**テレメトリーデータ（トレース・メトリクス・ログ）を生成・収集・エクスポートするためのベンダー中立な標準仕様とSDK群**です。CNCF（Cloud Native Computing Foundation）のプロジェクトで、Kubernetes に次ぐ規模のアクティビティを持つ、いまや事実上の業界標準です。

最大のメリットは **計装コードとバックエンドが分離されている**ことです。アプリ側を OpenTelemetry で計装しておけば、データの送り先（Jaeger、Prometheus、Datadog、Grafana、各種クラウドのマネージドサービスなど）は設定だけで切り替えられます。

```
[アプリ + OTel SDK] → [OTLP] → [OTel Collector] → [任意のバックエンド]
```

「監視ツールを乗り換えるたびに計装をやり直す」というベンダーロックインから解放されるわけです。

---

## 3つのシグナル

OpenTelemetry が扱うテレメトリーは、大きく3種類に分類されます。

| シグナル | 何を表すか | 代表的な用途 |
| --- | --- | --- |
| **Traces** | 1リクエストが複数サービスを横断する処理の流れ | ボトルネック特定、依存関係の可視化 |
| **Metrics** | 数値の時系列データ（カウンタ・ゲージなど） | スループット、エラー率、リソース使用率 |
| **Logs** | 個々のイベントの記録 | 詳細な原因調査 |

トレースは **Span**（処理の1単位）が親子関係でつながった木構造で表現されます。たとえば「注文API」のトレースは、`HTTPリクエスト受信 → 在庫確認 → 決済処理 → DB書き込み` といった複数の Span から構成されます。

これら3つを **同じ TraceID で相関づけられる**のが OpenTelemetry の強みです。あるエラーログから、それが発生したトレース全体へ一気に飛べます。

---

## 環境準備

まずは必要なパッケージをインストールします。今回は手動計装（manual instrumentation）でトレースとメトリクスを実装します。

```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp
```

- `opentelemetry-api`: 計装コードが依存する API 層
- `opentelemetry-sdk`: 実際にデータを処理する実装
- `opentelemetry-exporter-otlp`: OTLP（OpenTelemetry Protocol）でデータを送信するエクスポーター

:::message
`opentelemetry-api` と `opentelemetry-sdk` が分離しているのは意図的な設計です。ライブラリ作者は API だけに依存して計装でき、アプリケーション側が SDK を選んで設定します。これにより、ライブラリが特定の実装を強制しない構造になっています。
:::

---

## トレースの実装

注文処理を模した例で、Span を生成してみます。

```python
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
    OTLPSpanExporter,
)

# サービスを識別するリソース情報
resource = Resource.create({"service.name": "checkout-service"})

# TracerProvider にエクスポーターを登録
provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(
    OTLPSpanExporter(endpoint="http://localhost:4317")
)
provider.add_span_processor(processor)

# グローバルに設定（以降 get_tracer で取得できる）
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)


def process_order(order_id: str, amount: int) -> None:
    with tracer.start_as_current_span("process_order") as span:
        # Span に属性を付与して検索・フィルタしやすくする
        span.set_attribute("order.id", order_id)
        span.set_attribute("order.amount", amount)

        check_inventory(order_id)
        charge_payment(order_id, amount)


def check_inventory(order_id: str) -> None:
    # 親 Span のコンテキスト内で呼ぶと自動的に子 Span になる
    with tracer.start_as_current_span("check_inventory"):
        # 在庫確認処理（ここでは省略）
        pass


def charge_payment(order_id: str, amount: int) -> None:
    with tracer.start_as_current_span("charge_payment") as span:
        span.set_attribute("payment.amount", amount)
        # 決済処理（ここでは省略）
        pass


if __name__ == "__main__":
    process_order("ORD-1001", 4980)
```

ポイントは `start_as_current_span` を `with` 文で使うことです。これにより、

- ブロックを抜けると Span が自動的に終了（end）する
- ブロック内で呼ばれた別の `start_as_current_span` は、自動的に**子 Span** として親子関係が組み立てられる

`BatchSpanProcessor` は Span をバッファリングしてまとめて送信するため、本番環境ではこちらを使います。デバッグ時に1件ずつ即送信したい場合は `SimpleSpanProcessor` を使います。

### エラーを記録する

例外が発生したときに Span にエラーとして残しておくと、トレース画面で一目で異常を判別できます。

```python
from opentelemetry.trace import Status, StatusCode


def charge_payment(order_id: str, amount: int) -> None:
    with tracer.start_as_current_span("charge_payment") as span:
        try:
            # 決済処理（失敗すると例外を投げる想定）
            raise RuntimeError("payment gateway timeout")
        except Exception as exc:
            # 例外情報を Span のイベントとして記録
            span.record_exception(exc)
            # Span のステータスをエラーにする
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            raise
```

`record_exception` でスタックトレースを Span イベントとして残し、`set_status` で Span 全体をエラー扱いにします。この2つはセットで使うのが定石です。

---

## メトリクスの実装

次に、処理件数をカウントするメトリクスを追加します。

```python
from opentelemetry import metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import (
    OTLPMetricExporter,
)

resource = Resource.create({"service.name": "checkout-service"})

# 一定間隔でメトリクスをエクスポートする Reader
reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint="http://localhost:4317"),
    export_interval_millis=5000,
)
provider = MeterProvider(resource=resource, metric_readers=[reader])
metrics.set_meter_provider(provider)

meter = metrics.get_meter(__name__)

# 単調増加するカウンタ
order_counter = meter.create_counter(
    name="orders.processed",
    unit="1",
    description="処理した注文の件数",
)

# 任意の数値を記録するヒストグラム
latency_histogram = meter.create_histogram(
    name="order.latency",
    unit="ms",
    description="注文処理にかかった時間",
)


def record_order(status: str, latency_ms: float) -> None:
    # 属性（ラベル）で集計軸を分けられる
    order_counter.add(1, {"status": status})
    latency_histogram.record(latency_ms, {"status": status})
```

メトリクスには主に3種類の計器（instrument）があります。

- **Counter**: 増える一方の値（リクエスト数、エラー数など）
- **Histogram**: 値の分布を取りたいもの（レイテンシ、ペイロードサイズなど）
- **Gauge / UpDownCounter**: 増減する瞬間値（同時接続数、キュー長など）

:::message
`add()` や `record()` の第2引数に渡す属性（attributes）は、メトリクスの **集計の次元**になります。`status` で分ければ成功・失敗を別系列として観測できますが、`order_id` のように値の種類（カーディナリティ）が無限に近いものを属性に入れると、時系列の数が爆発してバックエンドを圧迫します。属性に高カーディナリティな値を入れないのは鉄則です。
:::

---

## OpenTelemetry Collector

ここまではアプリから直接バックエンドへ送る構成でしたが、本番では **OpenTelemetry Collector** を間に挟むのが推奨されます。

Collector を挟むメリットは次のとおりです。

- アプリ側は Collector に送るだけでよく、**バックエンドの切り替えが設定変更だけで済む**
- バッチ処理・リトライ・サンプリングを Collector に集約できる
- 複数のバックエンドへ同時にファンアウトできる

設定は `receivers`（受信）・`processors`（加工）・`exporters`（送信）・`service`（パイプライン定義）の4ブロックで構成します。

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s

exporters:
  # 標準出力に内容をダンプする（動作確認用）
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
```

:::message alert
以前の Collector には `logging` という確認用エクスポーターがありましたが、現在は **`debug`** エクスポーターに置き換えられています。古い記事の設定をそのままコピーすると起動に失敗するので注意してください。
:::

Docker で起動する場合は次のようにします。

```bash
docker run --rm \
  -p 4317:4317 \
  -p 4318:4318 \
  -v "$(pwd)/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml" \
  otel/opentelemetry-collector-contrib:latest
```

この状態で先ほどの Python スクリプトを実行すると、`endpoint="http://localhost:4317"`（gRPC）宛に送られた Span とメトリクスが、Collector の標準出力にダンプされます。動作確認できたら、`debug` エクスポーターを Jaeger や Prometheus、各種SaaSのエクスポーターに差し替えるだけで本番バックエンドへ流せます。

---

## 自動計装という選択肢

ここまでは手動でコードを書きましたが、Python では **既存のコードを変更せずに**主要ライブラリ（Flask、Django、requests、psycopg2 など）を計装する仕組みも用意されています。

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

`opentelemetry-bootstrap -a install` は、インストール済みのライブラリを検出して、対応する計装パッケージを自動でインストールしてくれます。あとはアプリの起動コマンドをラップするだけです。

```bash
opentelemetry-instrument \
  --traces_exporter otlp \
  --metrics_exporter otlp \
  --service_name checkout-service \
  --exporter_otlp_endpoint http://localhost:4317 \
  python app.py
```

まずは自動計装で全体像をつかみ、ビジネス上重要な処理にだけ手動で Span や属性を足していく、という併用が現実的です。

---

## まとめ

OpenTelemetry を導入することで、

- **ベンダー中立**な計装で、バックエンドをいつでも切り替えられる
- **Traces / Metrics / Logs** を同一の TraceID で相関づけられる
- **Collector** を挟むことで、収集・加工・転送をアプリから分離できる

という、観測可能性（Observability）の基盤が手に入ります。

最初から完璧な計装を目指す必要はありません。自動計装で全体を可視化し、調査でつまずいたポイントに手動 Span を足していく。この積み重ねが、障害対応のスピードを着実に変えていきます。

まずは Collector を `debug` エクスポーターで立ち上げて、自分のアプリの Span が流れてくるのを眺めるところから始めてみてください。
