---
title: "OpenTelemetryのトレースをBigQueryに流してGA4と突合する【離脱の「理由」を追う】"
emoji: "🔗"
type: "tech"
topics: ["opentelemetry", "bigquery", "googleanalytics", "observability", "dataanalytics"]
published: true
---

## はじめに

GA4を見ていると、**「どこで」ユーザーが離脱したか**はよく分かります。決済ページの直帰率が高い、特定の商品ページで滞在時間が短い——。でも、そこから先の**「なぜ」**は教えてくれません。

「決済ページで離脱が多い」と分かっても、それが UI の問題なのか、それとも**バックエンドの決済APIが遅かった/エラーを返していた**のかは、GA4だけでは切り分けられません。

一方、OpenTelemetry のトレースには「なぜ」が詰まっています。どのAPIが何ミリ秒かかったか、どこで例外が出たか。問題は、**この2つが別々の世界にある**ことです。

この記事では、**OpenTelemetry のトレースを BigQuery に蓄積し、GA4のエクスポートデータとJOINして「離脱したセッションのバックエンドで何が起きていたか」を一気通貫で分析する**方法を解説します。実例の少ない組み合わせですが、仕組みはシンプルです。

:::message
OpenTelemetry そのものの基礎（Span・計装・Collector）は、別記事「OpenTelemetry入門：分散トレーシングとメトリクスをPythonで実装する」で解説しています。本記事は計装済みである前提で、BigQuery連携にフォーカスします。
:::

---

## 全体のアーキテクチャ

やることは3つです。

1. **フロントの GA4 セッションIDをバックエンドのトレースに引き継ぐ**
2. **トレース（Span）を BigQuery のテーブルに書き込む**
3. **BigQuery 上で GA4 エクスポートと JOIN する**

```
[ブラウザ: GA4 client_id / session_id]
    │  Cookie (_ga, _ga_XXXX) を Ajax/SSR で送信
    ▼
[バックエンド: OTel SDK]
    │  ga_client_id / ga_session_id を Span 属性に付与
    ▼
[BigQuery: otel.spans テーブル]          [GA4 → BigQuery ネイティブエクスポート]
    │                                          │
    └──────────── JOIN (ga_client_id, ga_session_id) ────────────┘
```

ポイントは、**GA4と同じキー（client_id と session_id）をトレース側にも持たせる**ことです。これさえあれば、あとは BigQuery の JOIN で2つの世界がつながります。

---

## ステップ1：GA4のセッションIDをトレースに引き継ぐ

GA4 のエクスポートテーブルには `user_pseudo_id`（= GAクライアントID）と、`event_params` 内の `ga_session_id` が入っています。これらはブラウザの Cookie から取得できます。

- `_ga` Cookie … `GA1.1.1234567890.1699999999` のような形式で、後半が **client_id**
- `_ga_<measurement_id>` Cookie … セッション情報が含まれ、`GS1.1.<session_id>.…` の形式

バックエンドで受け取ったリクエストから、この2値を取り出して Span 属性に付与します。Flask を例にします。

```python
import re
from opentelemetry import trace

tracer = trace.get_tracer(__name__)


def parse_ga_cookies(cookies: dict) -> tuple[str | None, int | None]:
    """_ga / _ga_XXXX Cookie から client_id と session_id を取り出す"""
    client_id = None
    session_id = None

    ga = cookies.get("_ga")
    if ga:
        # 例: "GA1.1.1234567890.1699999999" → "1234567890.1699999999"
        m = re.match(r"GA\d+\.\d+\.(\d+\.\d+)", ga)
        if m:
            client_id = m.group(1)

    # _ga_ で始まる Cookie を探す（measurement_id 部分は環境ごとに異なる）
    for name, value in cookies.items():
        if name.startswith("_ga_"):
            # 例: "GS1.1.1699999999.3.1.1699999999.0.0.0"
            m = re.match(r"GS\d+\.\d+\.(\d+)\.", value)
            if m:
                session_id = int(m.group(1))
            break

    return client_id, session_id


def handle_checkout(request) -> None:
    client_id, session_id = parse_ga_cookies(request.cookies)

    with tracer.start_as_current_span("checkout") as span:
        # GA4 と同じキーを Span 属性として持たせるのが肝
        if client_id:
            span.set_attribute("ga.client_id", client_id)
        if session_id:
            span.set_attribute("ga.session_id", session_id)
        # 以降の決済処理（子 Span が紐づく）
        ...
```

:::message
`ga.client_id` / `ga.session_id` のような独自の属性キーは、OpenTelemetry の Semantic Conventions に沿って `ga.` という名前空間（プレフィックス）でまとめておくと、後から見て出所が明確になります。
:::

---

## ステップ2：SpanをBigQueryに書き込むカスタムExporter

OpenTelemetry の `SpanExporter` を自分で実装すれば、Span を任意の宛先に書き出せます。ここでは BigQuery クライアントの `insert_rows_json`（ストリーミング挿入）でテーブルに流し込みます。

まずは書き込み先テーブルのスキーマです。

```sql
CREATE TABLE `your_project.otel.spans` (
  trace_id        STRING    NOT NULL,
  span_id         STRING    NOT NULL,
  parent_span_id  STRING,
  name            STRING,
  start_time      TIMESTAMP,
  end_time        TIMESTAMP,
  duration_ms     FLOAT64,
  status_code     STRING,
  ga_client_id    STRING,
  ga_session_id   INT64,
  service_name    STRING,
  attributes      JSON
)
PARTITION BY DATE(start_time);
```

次に Exporter の実装です。

```python
import json
from datetime import datetime, timezone
from typing import Sequence

from opentelemetry.sdk.trace import ReadableSpan
from opentelemetry.sdk.trace.export import SpanExporter, SpanExportResult


def _ns_to_iso(ns: int | None) -> str | None:
    """ナノ秒のエポック時刻を BigQuery の TIMESTAMP 用 ISO 文字列に変換"""
    if ns is None:
        return None
    return datetime.fromtimestamp(ns / 1e9, tz=timezone.utc).isoformat()


class BigQuerySpanExporter(SpanExporter):
    def __init__(self, client, table_id: str):
        self._client = client          # google.cloud.bigquery.Client
        self._table_id = table_id      # "your_project.otel.spans"

    def export(self, spans: Sequence[ReadableSpan]) -> SpanExportResult:
        rows = [self._span_to_row(span) for span in spans]
        errors = self._client.insert_rows_json(self._table_id, rows)
        if errors:
            # 挿入エラーがあれば失敗を返す（BatchSpanProcessor がリトライ判断する）
            return SpanExportResult.FAILURE
        return SpanExportResult.SUCCESS

    def _span_to_row(self, span: ReadableSpan) -> dict:
        ctx = span.get_span_context()
        attributes = dict(span.attributes or {})

        start_ns = span.start_time
        end_ns = span.end_time
        duration_ms = None
        if start_ns is not None and end_ns is not None:
            duration_ms = (end_ns - start_ns) / 1e6

        return {
            "trace_id": format(ctx.trace_id, "032x"),
            "span_id": format(ctx.span_id, "016x"),
            "parent_span_id": (
                format(span.parent.span_id, "016x") if span.parent else None
            ),
            "name": span.name,
            "start_time": _ns_to_iso(start_ns),
            "end_time": _ns_to_iso(end_ns),
            "duration_ms": duration_ms,
            "status_code": span.status.status_code.name,  # "OK" / "ERROR" / "UNSET"
            "ga_client_id": attributes.get("ga.client_id"),
            "ga_session_id": attributes.get("ga.session_id"),
            "service_name": span.resource.attributes.get("service.name"),
            "attributes": json.dumps(attributes, ensure_ascii=False),
        }

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return True

    def shutdown(self) -> None:
        pass
```

登録は通常の Exporter と同じく `BatchSpanProcessor` 経由で行います。

```python
from google.cloud import bigquery
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider(
    resource=Resource.create({"service.name": "checkout-service"})
)
exporter = BigQuerySpanExporter(
    client=bigquery.Client(),
    table_id="your_project.otel.spans",
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

:::message
`trace_id` は128bit、`span_id` は64bitの整数です。BigQueryで扱いやすいよう、それぞれゼロ埋め16進文字列（32桁・16桁）に変換しています。これは Jaeger など他ツールのID表記とも揃うので、突合の際に便利です。
:::

### 本番では Collector 経由も検討する

アプリから直接 BigQuery に書く構成はシンプルですが、トラフィックが増えると挿入回数とコストが気になります。本番では **OTel Collector に集約し、`googlecloudpubsub` エクスポーターで Pub/Sub に送り、Pub/Sub の BigQuery サブスクリプションでテーブルに書き込む**構成にすると、アプリ側を軽く保てます。考え方（GA4キーをSpan属性に乗せてJOINする）は変わりません。

---

## ステップ3：BigQueryでGA4とJOINする

ここからが本題です。**「離脱したセッション」と「コンバージョンしたセッション」で、バックエンドのレイテンシやエラーに差があるか**を見てみます。

まず、トレース側をセッション単位に集約します。

```sql
-- backend: セッション単位のバックエンド指標
WITH backend AS (
  SELECT
    ga_client_id,
    ga_session_id,
    COUNT(*) AS span_count,
    SUM(IF(status_code = 'ERROR', 1, 0)) AS error_spans,
    MAX(duration_ms) AS max_span_ms,
    APPROX_QUANTILES(duration_ms, 100)[OFFSET(95)] AS p95_span_ms
  FROM `your_project.otel.spans`
  WHERE
    DATE(start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND ga_session_id IS NOT NULL
  GROUP BY ga_client_id, ga_session_id
),
```

次に、GA4 エクスポートをセッション単位に集約し、コンバージョン有無のフラグを付けます。

```sql
-- ga4: セッション単位のフロント指標
ga4 AS (
  SELECT
    user_pseudo_id AS ga_client_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS ga_session_id,
    MAX(IF(event_name = 'purchase', 1, 0)) AS converted,
    COUNTIF(event_name = 'page_view') AS pageviews
  FROM `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  GROUP BY ga_client_id, ga_session_id
)
```

最後に、この2つを **client_id と session_id の両方** でJOINして比較します。

```sql
SELECT
  IF(ga4.converted = 1, 'converted', 'not_converted') AS segment,
  COUNT(*) AS sessions,
  ROUND(AVG(backend.p95_span_ms), 1) AS avg_p95_backend_ms,
  ROUND(AVG(backend.error_spans), 2) AS avg_error_spans_per_session,
  ROUND(AVG(backend.max_span_ms), 1) AS avg_max_span_ms
FROM backend
JOIN ga4
  USING (ga_client_id, ga_session_id)
GROUP BY segment
ORDER BY segment;
```

:::message
`ga_session_id` は単独ではユーザーをまたいで衝突しうる値（生成時刻ベース）なので、必ず `ga_client_id` とのペアでJOINします。`USING (ga_client_id, ga_session_id)` がその指定です。
:::

このクエリで、たとえば次のような結果が得られます。

| segment | sessions | avg_p95_backend_ms | avg_error_spans_per_session |
| --- | --- | --- | --- |
| converted | 4,210 | 180.3 | 0.02 |
| not_converted | 12,880 | 642.7 | 0.31 |

非コンバージョンのセッションは、**バックエンドの p95 レイテンシが3倍以上、エラーSpanも15倍**——つまり「離脱の一因はUIではなくバックエンドの遅延・エラーだった」という仮説が、データで裏づけられるわけです。GA4単体でもトレース単体でも、この結論には辿り着けません。

---

## 一歩踏み込む：離脱直前に遅かったエンドポイントを特定する

セグメント比較で当たりをつけたら、**離脱セッションで具体的にどのSpan（エンドポイント）が遅かったか**まで掘れます。

```sql
WITH slow_sessions AS (
  SELECT
    user_pseudo_id AS ga_client_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS ga_session_id
  FROM `your_project.analytics_XXXXXXXXX.events_*`
  WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  GROUP BY ga_client_id, ga_session_id
  HAVING MAX(IF(event_name = 'purchase', 1, 0)) = 0   -- 非コンバージョンのみ
)

SELECT
  s.name AS endpoint,
  COUNT(*) AS span_count,
  ROUND(APPROX_QUANTILES(s.duration_ms, 100)[OFFSET(95)], 1) AS p95_ms,
  SUM(IF(s.status_code = 'ERROR', 1, 0)) AS error_count
FROM `your_project.otel.spans` AS s
JOIN slow_sessions
  USING (ga_client_id, ga_session_id)
WHERE DATE(s.start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY endpoint
ORDER BY p95_ms DESC
LIMIT 10;
```

「離脱セッションでは `POST /api/payment` の p95 が 1,200ms に達していた」といった、**改善対象を名指しできる粒度**まで一気に下りられます。

---

## 運用上の注意点

- **サンプリング**：全Spanを保存するとコストが膨らみます。OTel SDK の `TraceIdRatioBased` サンプラーで一定割合に絞るか、エラー・低速トレースだけ残すテールサンプリングを Collector で行うのが定石です。
- **個人情報**：`ga.client_id` は擬似ID（個人を直接特定しない）ですが、Span 属性にメールアドレスやトークンを含めないよう、`attributes` に入れる値は精査してください。
- **パーティション必須**：`spans` テーブルは `DATE(start_time)` でパーティション分割し、JOIN側のGA4も `_TABLE_SUFFIX` で期間を絞る。両側を絞らないとスキャン量＝課金が跳ねます。
- **キーの欠損**：Cookie同意前のリクエストなどでは `ga.session_id` が取れません。`IS NOT NULL` で明示的に除外し、JOIN対象を把握しておきます。

---

## まとめ

GA4とOpenTelemetryは、これまで別々のダッシュボードで眺めるものでした。しかし、

- **GA4の `client_id` / `session_id` をトレースのSpan属性に引き継ぎ**
- **Spanを BigQuery に蓄積し**
- **GA4エクスポートと同じキーでJOINする**

という3ステップを踏むだけで、「**ユーザー行動（GA4）とシステム挙動（トレース）を1つのSQLで結ぶ**」という、まだ事例の少ない分析が手に入ります。

「離脱が多い」で止まっていた会話を、「離脱セッションの決済APIが遅かった。まずそこを直そう」という**打ち手の会話**に変えられる。これが、2つの世界をBigQueryでつなぐ最大の価値です。

まずは `ga.session_id` をひとつのSpanに乗せて、BigQueryに1行流してみるところから始めてみてください。
