---
title: "Claude CodeでGA4のイベント設計書を自動生成する方法"
emoji: "📋"
type: "tech"
topics: ["claudecode","googleanalytics","documentation"]
published: false
---

## はじめに

「GA4のイベント、誰がいつ何を設定したのか分からなくなっている」

GA4の運用が長くなると、カスタムイベントやパラメータが増え、全体像を把握しづらくなります。担当者が変わったタイミングで「このイベントは何のために計測しているのか」が分からなくなるケースも少なくありません。

本記事では、BigQueryにエクスポートされたGA4の生データから既存イベントの一覧を抽出し、Claude Codeで設計書のMarkdownを自動生成する方法を紹介します。

## なぜイベント設計書が必要なのか

イベント設計書がない状態で運用を続けると、以下の問題が発生します。

- 不要なイベントが計測され続け、BigQueryのコストが増加する
- 分析時に「このイベントはどの画面で発火するのか」が分からず調査に時間がかかる
- GTMのタグ設定とGA4のイベント名が対応づけられない

設計書を一度作れば、新しいイベントの追加時に既存との重複や命名規則の逸脱をチェックできるようになります。

## Step 1: BigQueryから既存イベントの一覧を抽出する

### イベント名とパラメータの一覧を取得するSQL

```sql
-- イベント名一覧と発生件数
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_seen,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_seen
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

### イベントごとのパラメータ一覧を取得するSQL

```sql
-- 各イベントに含まれるパラメータとその型を抽出
SELECT
  event_name,
  ep.key AS param_key,
  CASE
    WHEN ep.value.string_value IS NOT NULL THEN 'string'
    WHEN ep.value.int_value IS NOT NULL THEN 'int'
    WHEN ep.value.float_value IS NOT NULL THEN 'float'
    WHEN ep.value.double_value IS NOT NULL THEN 'double'
    ELSE 'unknown'
  END AS param_type,
  COUNT(*) AS occurrence_count,
  -- サンプル値（string型の場合）
  APPROX_TOP_COUNT(ep.value.string_value, 3) AS sample_values_string
FROM
  `project.dataset.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name, param_key, param_type
ORDER BY
  event_name, occurrence_count DESC
```

:::message
`APPROX_TOP_COUNT` を使うことで、パラメータのサンプル値を効率的に取得できます。正確なカウントが不要な場面では `APPROX_` 系の関数がクエリコストの節約に有効です。
:::

## Step 2: ecommerce関連イベントの詳細を取得する

ECサイトの場合、ecommerce系のイベントは特に重要です。

```sql
-- ecommerceイベントの詳細
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS unique_sessions,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions
FROM
  `project.dataset.events_*`
WHERE
  event_name IN (
    'view_item', 'add_to_cart', 'begin_checkout',
    'add_payment_info', 'add_shipping_info', 'purchase'
  )
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

## Step 3: Pythonで中間データを整形する

BigQueryの結果をPythonで整形し、Claude Codeに渡す形式にします。

```python
"""
モジュール名: event_catalog_builder.py
目的: GA4イベント一覧をBigQueryから取得しカタログデータを構築する
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas
"""

from google.cloud import bigquery
import pandas as pd
import json

def fetch_event_summary(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """イベントのサマリー情報を取得する"""
    query = f"""
    SELECT
      event_name,
      COUNT(*) AS event_count,
      COUNT(DISTINCT user_pseudo_id) AS unique_users,
      MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_seen,
      MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_seen
    FROM
      `{project_id}.{dataset}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY event_name
    ORDER BY event_count DESC
    """
    return client.query(query).to_dataframe()

def fetch_event_params(client: bigquery.Client, project_id: str, dataset: str) -> pd.DataFrame:
    """イベントパラメータの詳細を取得する"""
    query = f"""
    SELECT
      event_name,
      ep.key AS param_key,
      CASE
        WHEN ep.value.string_value IS NOT NULL THEN 'string'
        WHEN ep.value.int_value IS NOT NULL THEN 'int'
        WHEN ep.value.float_value IS NOT NULL THEN 'float'
        ELSE 'unknown'
      END AS param_type,
      COUNT(*) AS occurrence_count
    FROM
      `{project_id}.{dataset}.events_*`,
      UNNEST(event_params) AS ep
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    GROUP BY event_name, param_key, param_type
    ORDER BY event_name, occurrence_count DESC
    """
    return client.query(query).to_dataframe()

def build_event_catalog(summary_df: pd.DataFrame, params_df: pd.DataFrame) -> list[dict]:
    """イベントカタログのデータ構造を構築する"""
    catalog = []
    for _, row in summary_df.iterrows():
        event_name = row['event_name']
        event_params = params_df[params_df['event_name'] == event_name]

        params_list = []
        for _, p in event_params.iterrows():
            params_list.append({
                'key': p['param_key'],
                'type': p['param_type'],
                'count': int(p['occurrence_count'])
            })

        catalog.append({
            'event_name': event_name,
            'event_count': int(row['event_count']),
            'unique_users': int(row['unique_users']),
            'first_seen': str(row['first_seen']),
            'last_seen': str(row['last_seen']),
            'category': classify_event(event_name),
            'params': params_list
        })

    return catalog

def classify_event(event_name: str) -> str:
    """イベントをカテゴリに分類する"""
    auto_events = [
        'first_visit', 'session_start', 'user_engagement',
        'page_view', 'scroll', 'click', 'file_download',
        'video_start', 'video_progress', 'video_complete',
        'view_search_results'
    ]
    ecommerce_events = [
        'view_item', 'view_item_list', 'select_item',
        'add_to_cart', 'remove_from_cart', 'view_cart',
        'begin_checkout', 'add_payment_info', 'add_shipping_info',
        'purchase', 'refund'
    ]

    if event_name in auto_events:
        return '自動収集イベント'
    elif event_name in ecommerce_events:
        return 'ecommerceイベント'
    elif event_name.startswith('gtm'):
        return 'GTM自動イベント'
    else:
        return 'カスタムイベント'
```

## Step 4: Claude Codeで設計書Markdownを生成する

構築したカタログデータをClaude Codeに渡して設計書を生成します。

```bash
claude "data/processed/event_catalog.json を読み込んで、
GA4イベント設計書をMarkdownで生成してください。

構成:
1. イベント一覧表（カテゴリ別）
2. 各イベントの詳細（パラメータ一覧、型、用途推定）
3. 命名規則の整理
4. 改善提案（不要なイベント、欠落しているイベントの指摘）

出力先: docs/ga4_event_design.md"
```

### 生成される設計書の構造

```markdown
# GA4 イベント設計書

更新日: 2026-03-30
対象プロパティ: GA4 Property XXX

## イベント一覧

### 自動収集イベント（8件）

| イベント名 | 直近90日件数 | ユニークユーザー | 初回検出日 |
|-----------|-------------|----------------|-----------|
| page_view | 125,000 | 15,200 | 2025-01-01 |
| session_start | 42,000 | 15,200 | 2025-01-01 |
| ...

### ecommerceイベント（6件）

| イベント名 | 直近90日件数 | ユニークユーザー | 初回検出日 |
|-----------|-------------|----------------|-----------|
| view_item | 35,000 | 12,100 | 2025-01-15 |
| add_to_cart | 4,200 | 3,800 | 2025-01-15 |
| ...

### カスタムイベント（12件）

| イベント名 | 直近90日件数 | ユニークユーザー | 初回検出日 |
|-----------|-------------|----------------|-----------|
| ab_test_impression | 8,500 | 4,200 | 2026-02-01 |
| ...
```

## Step 5: 設計書の自動更新を仕組み化する

設計書は一度作って終わりではなく、新しいイベントが追加されたタイミングで更新する必要があります。

```python
def detect_new_events(current_catalog: list[dict], previous_catalog_path: str) -> list[dict]:
    """前回のカタログと比較して新規イベントを検出する"""
    try:
        with open(previous_catalog_path, 'r') as f:
            previous = json.load(f)
        prev_names = {e['event_name'] for e in previous}
    except FileNotFoundError:
        prev_names = set()

    new_events = [e for e in current_catalog if e['event_name'] not in prev_names]

    if new_events:
        print(f"新規イベントを {len(new_events)} 件検出しました:")
        for e in new_events:
            print(f"  - {e['event_name']}（カテゴリ: {e['category']}）")

    return new_events
```

週次で自動実行し、新規イベントが検出された場合に通知する運用が効果的です。

:::message
GA4の管理画面（DebugView）でリアルタイムのイベント発火を確認できますが、BigQueryには1日程度の遅延があります。新規イベントの検出はBigQueryベースで日次または週次で行う設計が現実的です。
:::

## Pythonで設計書Markdownを直接生成するコード

Claude Codeを使わずにPythonだけで設計書を生成することも可能です。

```python
def generate_design_doc(catalog: list[dict]) -> str:
    """イベントカタログからMarkdown設計書を生成する"""
    md = "# GA4 イベント設計書\n\n"
    md += f"更新日: {pd.Timestamp.now().strftime('%Y-%m-%d')}\n\n"

    # カテゴリ別にグループ化
    categories = {}
    for event in catalog:
        cat = event['category']
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(event)

    for cat_name, events in categories.items():
        md += f"## {cat_name}（{len(events)}件）\n\n"
        md += "| イベント名 | 件数 | UU | 初回検出 | 最終検出 |\n"
        md += "|-----------|------|-----|---------|--------|\n"

        for e in events:
            md += (
                f"| `{e['event_name']}` "
                f"| {e['event_count']:,} "
                f"| {e['unique_users']:,} "
                f"| {e['first_seen']} "
                f"| {e['last_seen']} |\n"
            )

        md += "\n"

        # 各イベントのパラメータ詳細
        for e in events:
            if e['params']:
                md += f"### `{e['event_name']}` のパラメータ\n\n"
                md += "| パラメータ | 型 | 出現回数 |\n"
                md += "|-----------|-----|--------|\n"
                for p in e['params'][:10]:  # 上位10件
                    md += f"| `{p['key']}` | {p['type']} | {p['count']:,} |\n"
                md += "\n"

    return md
```

## 活用のポイント

### 1. GTMの設定と対応づける

生成した設計書をもとに、GTMのタグ一覧と照らし合わせます。BigQueryに存在するがGTMに設定がないイベントがあれば、GA4の自動収集イベントか、直接実装されたイベントのいずれかです。

### 2. 不要なイベントの棚卸し

`last_seen` が数ヶ月前のイベントは、計測対象のページやフローが削除された可能性があります。GTMのタグをアーカイブすることでBigQueryの取り込みデータ量を削減できます。

### 3. 命名規則の標準化

カスタムイベントの命名規則がバラバラになっている場合は、設計書をもとに統一ルールを策定します。推奨は `動詞_名詞` 形式（例: `click_cta`, `submit_form`, `view_promotion`）です。

## まとめ

GA4のイベント設計書を自動生成する手順は以下のとおりです。

1. BigQueryからイベント名・パラメータの一覧を抽出する
2. Pythonでカテゴリ分類とカタログ構造を構築する
3. Claude CodeまたはPythonでMarkdown設計書を生成する
4. 週次の自動更新で新規イベントを検出する

イベント設計書を整備することで、チーム内のGA4運用の属人化を防ぎ、分析の効率を向上させることができます。

---
:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
