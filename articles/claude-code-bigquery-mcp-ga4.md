---
title: "Claude Codeから公式BigQuery MCPでGA4を読む手順【読み取り専用・費用ガード・日次レポート】"
emoji: "🤖"
type: "tech"
topics: ["claudecode", "bigquery", "googleanalytics", "mcp", "lookerstudio"]
published: true
---

:::message
2026-10-10 に、製品の仕様変更とコードの誤りを修正しました。変更点: (1) MCP の登録方法を `claude mcp add` に直し、Google 公式のリモート BigQuery MCP を主役にした (2) セッション/CVR の SQL をセッション単位の流入元で書き直した (3) 日次レポートの集計対象を前々日にし、読み取り専用・費用ガードの節を追加した
:::

## この記事でわかること

- Claude Code から Google 公式の BigQuery MCP に接続し、GA4 のエクスポートデータへ自然言語で問い合わせる手順
- セッション単位で正しく CVR を出す SQL と、日次レポートを `claude -p` で回すときの注意点
- 読み取り専用で運用し、スキャン量（費用）に上限をかける方法

## 前提

- GA4 の BigQuery エクスポート（日次）が設定済みで、`events_YYYYMMDD` テーブルがあること（[公式設定ガイド](https://support.google.com/analytics/answer/9358801)）
- Google Cloud プロジェクトと、Claude Code のインストール
- 付与できる IAM ロール（後述の3つ）
- 費用は BigQuery のクエリスキャン量に応じて発生します。仕組みは「費用ガード」の節を参照してください

この記事の SQL は、Claude が生成する例として載せています。自分で書けなくても動かせますが、出力された SQL は読んで内容を確認する運用をおすすめします。

---

## 結論: 公式のリモート MCP を使う

以前の版では、PyPI の第三者製パッケージ `bigquery-mcp-server` を使う手順を載せていました。現在は Google 公式のリモート MCP サーバーがあるため、そちらを主役にします。

| 項目 | 内容 |
|---|---|
| エンドポイント | `https://bigquery.googleapis.com/mcp` |
| トランスポート | Streamable HTTP |
| 有効化 | BigQuery API（`bigquery.googleapis.com`）を有効にする |
| OAuth スコープ | `https://www.googleapis.com/auth/bigquery` |
| 上限 | クエリ処理は既定で3分、結果は3,000行まで |

ツールは次の6つです。

| ツール | 用途 |
|---|---|
| `execute_sql_readonly` | 読み取り専用の SQL 実行（DML / DDL は不可） |
| `execute_sql` | 書き込みも可能な SQL 実行 |
| `list_dataset_ids` / `list_table_ids` | データセット・テーブルの一覧 |
| `get_dataset_info` / `get_table_info` | メタデータの取得 |

公式ページによると、読み取り専用でないツールは `execute_sql` だけで、deny ポリシーで遮断できます。出典: [Use the BigQuery remote MCP server](https://docs.cloud.google.com/bigquery/docs/use-bigquery-mcp)

---

## セットアップ

### 1. 必要な IAM ロールを付ける

対象プロジェクトで、接続に使う ID（Google 推奨は、エージェント専用の別 ID）に次を付与します。

| ロール | 役割 |
|---|---|
| `roles/mcp.toolUser` | MCP ツールの呼び出し |
| `roles/bigquery.jobUser` | クエリジョブの作成 |
| `roles/bigquery.dataViewer` | テーブルの読み取り |

タスクによっては追加の権限が必要になる場合があります。

### 2. Claude Code に登録する

Claude Code の MCP 登録は、設定ファイルを手で書くのではなく `claude mcp add` で行うのが基本です。公式が示す MCP の定義場所は `~/.claude.json` と `.mcp.json` です。

リモート（HTTP）サーバーの汎用構文は次のとおりです（[Claude Code の MCP ドキュメント](https://code.claude.com/docs/en/mcp)）。

```bash
# BigQuery 公式 MCP を Claude Code に登録する（user スコープ）
claude mcp add --transport http --scope user bigquery https://bigquery.googleapis.com/mcp
```

Google の公式ページには `claude mcp add` のコマンド自体は載っていません。上は Claude Code 側の汎用構文に、Google の公式 URL を当てはめたものです。認証（OAuth の扱い）の手順は、Google の公式ページの記載に従ってください。認証が必要なサーバーは、Claude Code では `claude mcp login <name>` でも OAuth を進められます。

登録先は `--scope` で変わります。

| スコープ | 読み込まれる範囲 | チーム共有 | 保存先 |
|---|---|---|---|
| `local`（既定） | 現在のプロジェクトのみ | しない | `~/.claude.json` |
| `project` | 現在のプロジェクトのみ | する（バージョン管理） | プロジェクト直下の `.mcp.json` |
| `user` | 自分の全プロジェクト | しない | `~/.claude.json` |

認証情報を含みうる設定を共有しないよう、まずは `local` か `user` で試すのが無難です。

### 3. 接続を確認する

```bash
# 登録済みサーバーと接続状態を一覧する
claude mcp list
```

`Connected` と表示されれば接続できています。`Needs authentication` の場合は認証が未完了です。Claude Code を起動して次のように話しかけます。

```
データセット analytics_XXXXXXXXX のテーブル一覧を出して、
最新の events_ テーブルの日付を教えてください。
```

---

## 使い分け: BigQuery MCP と GA4 MCP

GA4 側にも公式の MCP（[googleanalytics/google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp)、Experimental）があります。こちらは BigQuery を経由せず、GA4 の Data API を呼びます。

| | BigQuery MCP | GA4 MCP（Experimental） |
|---|---|---|
| データの出どころ | BigQuery のエクスポート（イベント単位の生データ） | GA4 Data API（集計済みレポート） |
| 得意なこと | 自由な SQL、独自定義の指標、他データとの結合 | 標準のレポート指標、リアルタイム |
| 前提 | エクスポート設定、BigQuery の課金設定 | Admin API / Data API の有効化 |
| 認証 | OAuth（Google の公式ページ参照） | ADC、スコープ `analytics.readonly` |
| 起動 | リモート URL に接続 | `pipx run analytics-mcp` |
| ツール | 6種（上記） | 7種（`run_report` `run_funnel_report` `run_realtime_report` など） |

「GA4 の画面にある数字を手早く見たい」なら GA4 MCP、「自社定義の集計や他のデータとの突合をしたい」なら BigQuery MCP、と分けると迷いません。GA4 MCP の Claude Code への登録コマンドは、リポジトリの README に次の形で載っています。

```bash
# GA4 公式 MCP を Claude Code に登録する（認証ファイルのパスとプロジェクトIDは自分の値に置き換える）
claude mcp add analytics-mcp \
  --scope user \
  -e "GOOGLE_APPLICATION_CREDENTIALS=PATH_TO_CREDENTIALS_JSON" \
  -e "GOOGLE_PROJECT_ID=YOUR_PROJECT_ID" \
  -- pipx run analytics-mcp
```

ADC の作り方は README の手順に従ってください。

---

## 読み取り専用で運用する

分析用途なら、書き込みができるツールは不要です。次の2つで守ります。

1. **ツール側**: `execute_sql_readonly` だけを使う。`execute_sql` は deny ポリシーで遮断できる（公式ページの記載）
2. **権限側**: 接続用の ID に `bigquery.dataViewer` と `bigquery.jobUser` までしか付けない（データの書き換え権限を付けない）

---

## 費用ガード: スキャン量に上限をかける

BigQuery のオンデマンド料金は、クエリが読み取ったバイト数に応じて課金されます。公式ページには、各プロジェクトに毎月 1 TB の無料枠があると書かれています。単価は変わるので、[公式の価格ページ](https://cloud.google.com/bigquery/pricing)で確認してください。

AI にクエリを書かせると、期間を絞らない SQL が出ることがあります。次の3つで備えます。

| 対策 | 内容 |
|---|---|
| 期間を絞る | `events_*` を読むときは `_TABLE_SUFFIX` で日付範囲を必ず指定する |
| 上限をかける | `maximum bytes billed`（API では `maximumBytesBilled`、bq CLI では `--maximum_bytes_billed`）を設定する。見積もりが上限を超えるクエリは、課金されずに失敗する |
| 事前に見る | ドライラン（dry run）でスキャン量を確認する |

`maximum bytes billed` は、クエリを実行する側の設定です。MCP 経由でどこまで固定できるかは、利用するクライアントと公式ドキュメントで確認してください。確実に守りたい場合は、プロジェクト単位の上限（BigQuery の割り当て）も検討します。

---

## 実際の使用例（EC事業者向け）

### ケース1: チャネル別のセッション数・購入セッション数・CVR

```
先月のチャネル別に、セッション数、購入があったセッション数、CVR、売上を集計してください。
セッションは user_pseudo_id と ga_session_id の組で数えてください。
```

以下は、Claude が生成する SQL の例です。ポイントは3つです。

- 流入元は、イベント単位の `collected_traffic_source` ではなく、セッション単位の `session_traffic_source_last_click` を使う（purchase 行と session_start 行で medium が別になり、CVR が崩れるのを避ける）
- 分母・分子ともに「セッション」で数える（購入があったセッション数 ÷ セッション数）
- 売上は `ecommerce.purchase_revenue`（プロパティの現地通貨）。USD で揃えたい場合は `purchase_revenue_in_usd` を使う

```sql
-- 先月のチャネル(medium)別に、セッション数・購入セッション数・CVR・売上を出す
WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    -- セッション単位の流入元（最後のクリック）。イベントごとの値の揺れを MAX で1つに畳む
    MAX(COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.medium,
      session_traffic_source_last_click.manual_campaign.medium
    )) AS medium,
    LOGICAL_OR(event_name = 'purchase') AS has_purchase,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS revenue
  FROM `project.analytics_XXXXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY user_pseudo_id, ga_session_id
  HAVING ga_session_id IS NOT NULL
)
SELECT
  IFNULL(medium, '(not set)') AS medium,
  COUNT(*) AS sessions,
  COUNTIF(has_purchase) AS purchase_sessions,
  ROUND(SAFE_DIVIDE(COUNTIF(has_purchase), COUNT(*)) * 100, 2) AS cvr_pct,
  SUM(revenue) AS revenue
FROM sessions
GROUP BY medium
ORDER BY sessions DESC
```

注意点です。

- 上の SQL は、スキーマの定義（[公式](https://support.google.com/analytics/answer/7029846)）に沿って組んだ例です。自分のデータで結果を確認してから使ってください。`medium` に何が入るかはプロパティによって違います
- Google 広告のセッションは `google_ads_campaign` 側に情報が入ります。広告別に分けたい場合は、そのレコードも見る必要があります
- 当日分の `events_intraday_` テーブルでは、流入元が欠けることがあります。流入元の分析は日次テーブルで行ってください（ストリーミングのエクスポートは、新規ユーザー・新規セッションの流入元を含みません。[GA4ヘルプ](https://support.google.com/analytics/answer/9358801)）

### ケース2・3: やりたいことの例（SQL は掲載しません）

次の2つは、「こういうことを聞ける」という例です。SQL は、データの持ち方（カート追加のイベント名、購入者の識別方法）で変わるため載せていません。

```
先週、商品詳細ページを見たあとカートに入れずに離脱したユーザーが
多かったページを教えてください。（イベント名は view_item / add_to_cart を前提にする）
```

```
初回購入から30日以内に2回目の購入をしたユーザーの割合を月別で出してください。
```

どちらも、Claude が生成した SQL を読んで、定義（誰を「ユーザー」と数えるか）が自分の意図と合っているかを必ず確認してください。

---

## 日次レポートを自動で作る

### 集計対象は「前々日」にする

GA4 の日次エクスポートは、プロパティのタイムゾーンの午後に出るのが目安で、朝8時には前日分のテーブルがまだ無いことがあります。さらに公式ページには、遅れて届いたイベントが日次テーブルを最大3日間更新するとあります。

そのため、次のどちらかにします。

- 集計対象を前々日にする（この記事の例）
- 実行時刻を、前日分のテーブルが出た後（夜など）にずらす

どちらの場合も、直近の数字は後から少し動く可能性があります。

### Python スクリプトの例

```python
# 前々日のECレポートを claude -p で生成して標準出力に出す
import subprocess
from datetime import date, timedelta

target = date.today() - timedelta(days=2)  # 前日分は未着の可能性があるため前々日

prompt = f"""
{target} のECサイトの状況を、BigQueryのデータセット analytics_XXXXXXXXX から集計してレポートしてください。
読み取り専用のツール(execute_sql_readonly)だけを使い、events_{target:%Y%m%d} のテーブルのみを読んでください。

1. セッション数・購入セッション数・CVR（セッションは user_pseudo_id と ga_session_id の組）
2. チャネル(medium)別のセッション数（上位5件）
3. 売上（ecommerce.purchase_revenue の合計）
4. 7日前の同じ曜日との比較
5. 気になる変化があれば指摘
"""

subprocess.run(
    [
        "claude", "-p", prompt,
        "--mcp-config", "./mcp.json",
        "--strict-mcp-config",
        "--allowedTools", "mcp__bigquery__execute_sql_readonly",
    ],
    check=True,
)
```

`mcp.json` には、使う MCP サーバーの定義を書きます。サーバー名は `bigquery` にしてください。ツール名は `mcp__<サーバー名>__<ツール名>` で決まるため、名前が違うと上の `--allowedTools` の `mcp__bigquery__execute_sql_readonly` と一致せず、許可されません。非対話実行（`-p`）には、次の注意があります。

| 項目 | 内容 |
|---|---|
| ツールの許可 | 対話できないので、使うツールを `--allowedTools` で事前に許可する必要がある。ツール名は `mcp__<サーバー名>__<ツール名>` の形（例は上記） |
| `--mcp-config` | JSON ファイルまたは文字列で MCP サーバーを渡す |
| `--strict-mcp-config` | `--mcp-config` で渡したサーバーだけを使い、他の MCP 設定を無視する。意図しないサーバーが混ざるのを防げる |
| 認証 | OAuth が必要なサーバーは、事前に `claude mcp login <name>` などで認証を済ませておく |

`--allowedTools` の指定形式は[CLI リファレンス](https://code.claude.com/docs/en/cli-reference)と[権限ルールの構文](https://code.claude.com/docs/en/settings-reference#permission-rule-syntax)で確認してください。動かないときは、まず `claude mcp list` で接続状態を見ます。

### 定期実行の登録（Windows の例）

```
タスク名: GA4_Daily_Report
トリガー: 毎日 （前日分のテーブルが出た後の時刻。前々日対象なら朝でも可）
操作: python C:\path\to\daily_report.py
```

---

## 3層設計との組み合わせ

MCP で扱うデータは、BigQuery 側で3層に整えておくと問い合わせが安定します。

```
raw層      analytics_XXXXXXXXX.events_YYYYMMDD（GA4生データ）
  ↓
staging層  フラット化・クレンジング済みのビュー
  ↓
mart層     ビジネス指標に変換済みのテーブル ← MCPはここに向ける
```

mart 層に向けると、Claude への指示が短くて済み、毎回 `UNNEST(event_params)` を書かせる必要もなくなります。スキャン量も減らせます。

:::message
3層設計の詳細は[「GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】」](/articles/ga4-bigquery-3layer-design)で解説しています。
:::

---

## まとめ

- BigQuery への接続は、Google 公式のリモート MCP（`https://bigquery.googleapis.com/mcp`）を `claude mcp add --transport http` で登録する
- 読み取り専用ツールで運用し、`_TABLE_SUFFIX` と `maximum bytes billed` でスキャン量に上限をかける
- 次にやること: まずケース1の SQL を自分のデータで実行して結果を確認し、そのあと日次レポートを前々日対象で試す

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → https://coconala.com/services/1791205
