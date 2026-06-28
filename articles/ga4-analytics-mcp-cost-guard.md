---
title: "Google公式BigQuery MCPが出た今、自前GA4分析MCPを作る価値 — 業務知識とコストガードをツール化する"
emoji: "📊"
type: "tech"
topics: ["mcp", "bigquery", "googleanalytics", "python", "claude"]
published: false
publish_queue: true
---

## 「BigQuery MCPなら公式が出たよね？」への答え

GA4 を BigQuery にエクスポートしている人向けに、**Claude から自然言語で GA4 を分析できる MCP サーバー**を自作した。「先週の人気ページは？」「エンゲージメント率は？」と聞くと、裏で BigQuery にクエリが飛んで実データで答える。

ただ、作る前に正直に立ち止まった。**Google公式のフルマネージドBigQuery MCPサーバーがすでにある**（[公式ドキュメント](https://docs.cloud.google.com/bigquery/docs/use-bigquery-mcp)）。OSSの MCP Toolbox for Databases でもBigQueryを公開できる。つまり「**自然言語 → SQL実行**」という土台はもうコモディティだ。ここを自作しても二番煎じになる。

では自前で作る価値はどこにあるか。結論は2つ。

1. **ドメイン分析のツール化**：公式がやるのは「生のSQL実行」まで。「どう分析するか」（ファネル、チャネル別売上、人気ページ…）という**業務知識**はツール化されていない。
2. **コストガード**：LLM に GA4 の `events_*` を自由に叩かせると、フルスキャンで**課金が膨らむ**。これを防ぐ層は自分で握りたい。

この2点に絞れば、自作にははっきり意味がある。以下、実装を紹介する。

## 全体像

- **言語/SDK**：Python ＋ FastMCP（MCP Python SDK）
- **データ**：自分のサイトの GA4 → BigQuery エクスポート（`<project>.<dataset>.events_*`）
- **公開ツール**：`top_pages` / `engagement_summary` / `new_vs_returning` / `channel_performance` / `purchase_funnel` ＋ `run_sql`（エスケープハッチ）
- **全クエリがコストガードを通る**

設計上のキモは、**「SQL生成」と「クエリ実行」を分離**したこと。SQL生成を BigQuery 非依存の純粋関数にすることで、**実DBなしで単体テストできる**。

## 主役：コストガード

GA4 の `events_*` は日付シャードの巨大テーブル。LLM が雑に `SELECT ... FROM events_*` をやると全期間フルスキャンになりうる。そこで全クエリを次の関門に通す。

```python
class BudgetExceeded(Exception):
    """推定スキャン量が上限を超えたため実行を拒否した。"""

def run_query(sql: str, params=None) -> dict:
    from google.cloud import bigquery
    limit = int(float(os.environ.get("MAX_SCAN_GB", "5")) * 1024**3)

    # 1. dry-run でスキャン予定バイト数を見積もる（課金されない）
    est = estimate_bytes(sql, params)
    if est > limit:
        raise BudgetExceeded(
            f"推定スキャン {est/1024**3:.2f}GB が上限を超えています。期間を狭めてください。")

    # 2. 実行時も maximum_bytes_billed で物理上限をかける
    client = _client()
    job = client.query(sql, job_config=bigquery.QueryJobConfig(
        maximum_bytes_billed=limit, query_parameters=_to_params(params)))
    rows = [dict(r) for r in job.result()]
    return {"rows": rows, "sql": sql,
            "scanned_gb": round((job.total_bytes_processed or 0) / 1024**3, 4)}
```

`estimate_bytes` は dry-run ジョブを投げるだけ。

```python
def estimate_bytes(sql: str, params=None) -> int:
    from google.cloud import bigquery
    job = _client().query(sql, job_config=bigquery.QueryJobConfig(
        dry_run=True, use_query_cache=False, query_parameters=_to_params(params)))
    return int(job.total_bytes_processed or 0)
```

ポイントは **「dry-runで見積もり → 上限超なら実行前に拒否」** の二段構え。`maximum_bytes_billed` だけだと「上限到達でエラー」になるが、dry-run を先に見れば**実行前に丁寧に「期間を狭めて」と返せる**。これは個人開発のLLMアプリで作った「予算ガード」と同じ思想だ。さらにツール側のSQLは必ず日付パーティション（`_TABLE_SUFFIX`）で絞るので、実測スキャンは数MB〜十数MBに収まる。

:::message
`run_sql`（任意SELECTのエスケープハッチ）には、`_TABLE_SUFFIX` を含まないクエリを拒否するガードを入れている。LLMが「全期間スキャン」を投げるのを防ぐため。
:::

## SQL生成は純粋関数に分けてテスト可能にする

各分析のSQLは、BigQueryに触らない純粋関数として書く。戻り値は `(sql, params)`。これで**実DBなしでロジックを検証**できる。

```python
def build_top_pages(table, start_date, end_date, limit=20):
    params = [("start", "STRING", _suffix(start_date)),
              ("end", "STRING", _suffix(end_date))]
    sql = f"""
WITH pv AS (
  SELECT
    user_pseudo_id,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key='page_location'),
      r'^https?://[^/]+([^?#]*)') AS page_path,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='page_title') AS page_title
  FROM {table}
  WHERE _TABLE_SUFFIX BETWEEN @start AND @end AND event_name = 'page_view'
)
SELECT page_path, ANY_VALUE(page_title) AS page_title,
       COUNT(*) AS views, COUNT(DISTINCT user_pseudo_id) AS users
FROM pv GROUP BY page_path ORDER BY views DESC LIMIT {min(int(limit), 1000)}
""".strip()
    return sql, params
```

テストは BigQuery 不要で回る。

```python
def test_top_pages_sql():
    sql, params = build_top_pages("`p.d.events_*`", "2026-06-01", "2026-06-28", limit=5)
    assert "_TABLE_SUFFIX BETWEEN @start AND @end" in sql   # スキャンを必ず絞る
    assert "event_name = 'page_view'" in sql
    assert ("start", "STRING", "20260601") in params        # YYYYMMDDに変換されている
```

GA4のSQLは `UNNEST(event_params)` だらけで間違えやすいので、**生成ロジックを純粋関数にしてテストで固める**のは効く。

## FastMCPでツールとして公開する

あとは生成→実行をつないで `@mcp.tool()` を付けるだけ。

```python
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("ga4-analytics")

@mcp.tool()
def top_pages(start_date: str | None = None, end_date: str | None = None,
              limit: int = 20) -> dict:
    """人気ページ（page_path別の views / users）を多い順に返す。未指定なら直近28日。"""
    start, end = _default_range(start_date, end_date)
    sql, params = build_top_pages(_table(), start, end, limit=limit)
    res = run_query(sql, params)
    return {"period": {"start": start, "end": end}, "pages": res["rows"],
            "scanned_gb": res["scanned_gb"]}

if __name__ == "__main__":
    mcp.run()
```

GA4スキーマの早見表は MCP の resource として公開しておくと、Claude が `event_params` の取り出し方を毎回探さずに済む。

## Claude に接続して使う

stdio で繋ぐ。Claude Code なら:

```bash
claude mcp add ga4 -- env BQ_PROJECT=your-proj GA4_DATASET=analytics_XXXXXXXXX \
  python /path/to/server.py
```

接続後はこう聞ける（検証は GA4 公開サンプル `bigquery-public-data.ga4_obfuscated_sample_ecommerce` でも可能）。

> 「直近7日の人気ページTOP5は？」
> → `top_pages` が呼ばれ、views/users付きで返る
>
> 「先月のエンゲージメント率と平均滞在時間は？」
> → `engagement_summary` が `engagement_rate` と `avg_engagement_time_sec` を返す

自分のコンテンツサイトのGA4で試したところ、エンゲージメント率・新規/リピート比・人気記事が自然言語一発で出た。`engagement_summary` と `new_vs_returning` が**同じ session 数を返す**ことも確認でき、ロジックの裏も取れた。

## ドメイン上の注意（ここが業務知識）

ツール化するときに効くのは、GA4 export 特有のクセを織り込むこと。

- **`traffic_source.source/medium` はユーザーの初回獲得（first-touch）**。セッション/ラストクリック帰属とは違う。`channel_performance` の戻り値には `"attribution": "first-touch"` を明示して誤読を防ぐ。
- **`session_engaged` は型が揺れる**（環境で string か int）。`COALESCE(value.string_value, CAST(value.int_value AS STRING))` で両対応にしておく。
- **セッションは `user_pseudo_id` × `ga_session_id`**。`event_params` から `ga_session_id` を取り出して数える。

こういう「現場で踏む地雷」を**ツールの中に閉じ込めておく**のが、汎用SQL実行にはない自作の価値だ。

## まとめ

- 汎用「自然言語→BigQuery SQL」は**公式MCPで解決済み**。自作するなら**ドメイン分析のツール化**と**コストガード**に振る
- コストガードは **dry-runで見積もり→上限超なら実行前に拒否**＋`maximum_bytes_billed`＋日付パーティション必須
- **SQL生成を純粋関数に分離**して実DBなしでテスト
- GA4特有のクセ（first-touch帰属・`session_engaged`の型揺れ・セッションの数え方）をツールに閉じ込める

公式が土台を用意してくれた今こそ、**自分の業務知識を薄いMCPレイヤーに乗せる**のが費用対効果が高い。GA4をBigQueryに入れている人の参考になれば。

:::message
この記事のコードは、自分の運用しているサイトのGA4エクスポートで検証済みです（数値・サイト情報は伏せています）。
:::
