---
title: "Claude Codeでクロスチャネルアトリビューション分析を自動化した"
emoji: "🔀"
type: "tech"
topics: ["claudecode", "bigquery", "attribution"]
published: true
---

:::message
2026-10-10 に、製品の仕様変更とコードの誤りを修正しました。変更点:
- GA4 のアトリビューションモデルの現状（2023年11月に first click・linear・time decay・position-based を廃止）を前提に書き直しました
- SQL の誤り（セッションの分割、channel が direct に化ける問題、線形・時間減衰の配分ミス）を直し、ラストクリックと接点ベースの SQL を追加しました
- 廃止済みのモデル名を `claude-sonnet-5-5` に差し替え、Claude Code と Claude API の役割を分けて書きました。サンプル数値も表と整合するよう作り直しました
- 売上を現地通貨の `purchase_revenue` に変更し、購入の `transaction_id` による重複除去を追加しました
:::

## はじめに

「広告の成果をラストクリックだけで判断していいのか、ずっと疑問だった」

ECサイトでは、ユーザーが複数のチャネルを経由して購入に至るケースが多くあります。ところが GA4 のレポートで選べるアトリビューションモデルは今は3つだけで、認知系チャネルの貢献を自分で見比べることができません。

そこでこの記事では、BigQuery の GA4 エクスポートデータを使って、**GA4 にはもう無いモデル（線形・時間減衰・接点ベースなど）を SQL で自作して比べる**方法を紹介します。

**この記事でわかること**

1. GA4 のアトリビューションモデルの現状と、BigQuery で自作する理由
2. ラストクリック・線形・時間減衰・接点ベースを SQL で実装する方法
3. Claude Code と Claude API をどう使い分けて分析を回すか

**前提**

- GA4 の BigQuery エクスポートが有効で、`events_*` テーブルにデータがあること
- BigQuery の実行権限と、クエリ課金（スキャン量に応じて発生）を理解していること
- 接触の追跡は `user_pseudo_id` 単位のため、端末をまたぐ接触は繋がりません
- Python 3 と、`google-cloud-bigquery`・`db-dtypes`・`anthropic`・`python-dotenv` が入っていること
- Claude API を使う場合は API キー（従量課金）が必要。Claude Code の利用枠とは別の課金です

---

## GA4のアトリビューションモデルの現状

GA4 のレポートで選べるのは、データドリブン、有料とオーガニックのラストクリック、Google 有料チャネルのラストクリックの3つです。ファーストクリック・線形・時間減衰・接点ベース（position-based）は **2023年11月に廃止**されました（[公式ヘルプ](https://support.google.com/analytics/answer/10596866)）。

なお、レポートによって帰属の単位が違う点に注意してください。キーイベント（コンバージョン）の帰属はアトリビューション設定のモデルに従い、セッション単位のトラフィック獲得レポートはセッションの流入元を見ます。細かい既定値は変更されることがあるため、[公式ヘルプ](https://support.google.com/analytics/answer/10597962)で確認してください。

また、GA4 には振り返り期間（lookback window）があります。獲得系のキーイベント（`first_open` / `first_visit`）は 30 日（7 日に変更可）、その他のキーイベントは 90 日（30・60 日に変更可）です。**この記事の SQL は振り返り期間を考慮していません。** 指定した期間内の購入前のセッションを、すべてタッチポイントとして扱います。

以下は、この記事で実装するモデルの一覧です。

| モデル | 配分ルール | GA4 のレポートで選べるか |
|--------|------------|------------------------|
| ラストクリック | 最後のタッチポイントに100% | 選べる（有料とオーガニック、Google有料の2種類） |
| ファーストクリック | 最初のタッチポイントに100% | 選べない（この記事では実装しない） |
| 線形 | すべてのタッチポイントに均等配分 | 選べない |
| 時間減衰 | 購入に近いタッチポイントほど高く配分 | 選べない |
| 接点ベース | 最初と最後に40%ずつ、残りに20%を均等配分 | 選べない |

データドリブンは GA4 内で機械学習により算出されるため、BigQuery では再現できません。この記事の SQL は「GA4 の画面と同じ数字を出す」ものではなく、**ルールが明確なモデルで貢献の見え方を比べる**ためのものです。

---

## Claude Code と Claude API の役割分担

題名に Claude Code と付けていますが、この記事のコードの中で Claude が動く場所は2つあり、役割が違います。

| | Claude Code | Claude API（Messages API） |
|---|---|---|
| 何をするか | SQL やスクリプトを書く・実行する・エラーを直す | 比較結果を渡して、要約文や予算配分の案を書かせる |
| 使う場面 | 分析の仕組みを作る段階 | 仕組みができた後、毎回のレポート生成 |
| この記事では | Step 1〜3 の SQL と Step 5 のスクリプトの作成 | Step 5 の `analyze_with_claude` |

つまり、Claude Code に作業を任せて仕組みを作り、できあがった Python から Claude API を呼んで解釈文を出す、という流れです。

---

## Step 1：購入ごとのタッチポイント経路を作る

購入イベントごとに、その購入時刻より前のセッションを時系列に並べます。この WITH 句を `queries/attribution/touchpoints.sql` として保存し、Step 2 以降の各モデルの SELECT をこの後ろに連結して使います。

ポイントは3つです。

- セッションの開始時刻は、セッション内の最初のイベント時刻（`MIN`）。GROUP BY には含めない（含めると同一セッションが複数行に割れる）
- チャネルは、セッション単位で付く `session_traffic_source_last_click` から取る。イベント単位の `collected_traffic_source` は後続イベントで NULL になり、direct に化ける
- 売上は現地通貨の `purchase_revenue`（日本円のECを想定）。通貨が混在するショップでは合算しない（通貨ごとに分けて集計する）
- 購入は `user_pseudo_id` と `transaction_id` で重複を除き、`transaction_id` が無い購入は対象から外す（重複送信があると touch_count が倍になり、配分が歪む）

```sql
-- touchpoints.sql: 購入ごとに、購入前のセッションをタッチポイントとして並べる共通CTE
WITH sessions AS (
  -- セッション単位に1行。開始時刻は最初のイベント時刻
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
    COALESCE(MAX(channel_raw), '(direct) / (none)') AS channel
  FROM (
    SELECT
      user_pseudo_id,
      event_timestamp,
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS ga_session_id,
      COALESCE(
        CONCAT(session_traffic_source_last_click.manual_campaign.source,
               ' / ', session_traffic_source_last_click.manual_campaign.medium),
        CONCAT(session_traffic_source_last_click.cross_channel_campaign.source,
               ' / ', session_traffic_source_last_click.cross_channel_campaign.medium)
      ) AS channel_raw
    FROM `project.analytics_XXXXXX.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20260901' AND '20260930'  -- 分析期間に合わせる
  )
  WHERE ga_session_id IS NOT NULL
  GROUP BY user_pseudo_id, ga_session_id
),
purchases AS (
  -- 購入1件につき1行。同じ transaction_id の重複送信は最初の1件だけ残す
  SELECT
    user_pseudo_id,
    CONCAT(user_pseudo_id, '-', ecommerce.transaction_id) AS purchase_id,
    TIMESTAMP_MICROS(event_timestamp) AS purchase_ts,
    ecommerce.purchase_revenue AS revenue  -- 現地通貨。NULL の購入は SUM で無視される
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260901' AND '20260930'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND ecommerce.transaction_id != '(not set)'  -- transaction_id が無い購入は除外
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id, ecommerce.transaction_id
    ORDER BY event_timestamp
  ) = 1
),
touchpoints AS (
  -- 購入時刻以前に始まったセッションだけを、その購入のタッチポイントにする
  SELECT
    p.purchase_id,
    p.revenue,
    s.channel,
    ROW_NUMBER() OVER (PARTITION BY p.purchase_id ORDER BY s.session_start) AS touch_order,
    COUNT(*) OVER (PARTITION BY p.purchase_id) AS touch_count,
    TIMESTAMP_DIFF(p.purchase_ts, s.session_start, SECOND) / 86400.0 AS days_before_purchase
  FROM purchases p
  JOIN sessions s
    ON s.user_pseudo_id = p.user_pseudo_id
   AND s.session_start <= p.purchase_ts
)
```

`session_traffic_source_last_click` が入っていない期間は、全セッションが direct に化けます。分析期間の `events_*` にこのフィールドがあることを先に確認してください。

期間の冒頭より前のセッションは含まれません。購入までの期間が長い商材は、`_TABLE_SUFFIX` の開始日を購入日より前に広げてください。

---

## Step 2：ラストクリックと線形を実装する

以降の SQL は、Step 1 の WITH 句の直後に連結して実行します（`queries/attribution/last_click.sql` のように、SELECT 部分だけをファイルにします）。

最初に基準となるラストクリックです。購入ごとに、最後のタッチポイントへ売上の全額を配分します。

本 SQL のラストクリックは、direct を除外しない「最終セッション」です。GA4 の「有料とオーガニックのラストクリック」は direct を無視する別のモデルなので、数字は一致しません。

```sql
-- last_click.sql: 購入ごとに最後のタッチポイントへ売上の100%を配分する
SELECT
  channel,
  ROUND(SUM(revenue), 0) AS attributed_revenue
FROM touchpoints
WHERE touch_order = touch_count
GROUP BY channel
ORDER BY attributed_revenue DESC;
```

線形は、購入ごとに売上をタッチ数で割って均等に配分します。**購入単位で配分する**のがポイントで、同じユーザーが複数回購入しても、それぞれの購入が自分のタッチポイントにだけ配分されます。

```sql
-- linear.sql: 購入ごとに売上をタッチ数で均等割りして配分する
SELECT
  channel,
  ROUND(SUM(revenue / touch_count), 0) AS attributed_revenue
FROM touchpoints
GROUP BY channel
ORDER BY attributed_revenue DESC;
```

---

## Step 3：時間減衰と接点ベースを実装する

時間減衰は、購入時刻を基準に、古いセッションほど重みを小さくします。Step 1 で購入後のセッションは除外済みです。重みは `EXP(-LN(2) * 日数差 / 7.0)` で、**半減期7日**（7日前のセッションの重みが、当日の半分）です。

```sql
-- time_decay.sql: 購入に近いセッションほど重くする（半減期7日）
SELECT
  channel,
  ROUND(SUM(revenue * share), 0) AS attributed_revenue
FROM (
  SELECT
    channel,
    revenue,
    weight / SUM(weight) OVER (PARTITION BY purchase_id) AS share
  FROM (
    SELECT
      purchase_id,
      channel,
      revenue,
      -- 古いほど重みが小さくなる（0日前=1.0、7日前=0.5、14日前=0.25）
      EXP(-LN(2) * days_before_purchase / 7.0) AS weight
    FROM touchpoints
  )
)
GROUP BY channel
ORDER BY attributed_revenue DESC;
```

:::message
半減期の7日は、購買サイクルに合わせて調整する値です。購入までの日数の分布を自分のデータで確認し、それに近い値を選んでください。
:::

接点ベースは、1件の場合は100%、2件の場合は50%ずつ、3件以上は最初と最後に40%ずつ、残りの20%を中間で均等割りします。

```sql
-- position_based.sql: 最初と最後に40%、残り20%を中間に均等配分する
SELECT
  channel,
  ROUND(SUM(revenue * share), 0) AS attributed_revenue
FROM (
  SELECT
    channel,
    revenue,
    CASE
      WHEN touch_count = 1 THEN 1.0
      WHEN touch_count = 2 THEN 0.5
      WHEN touch_order = 1 OR touch_order = touch_count THEN 0.4
      ELSE 0.2 / (touch_count - 2)
    END AS share
  FROM touchpoints
)
GROUP BY channel
ORDER BY attributed_revenue DESC;
```

---

## Step 4：比較結果を LLM に解釈させる

3つのモデルの結果を並べ、解釈を LLM に任せます。次の表は、**架空のサンプルデータによる例です**。実在の店舗や案件の結果ではありません。どのモデルも売上の合計は同じ ¥1,500,000 で、チャネルごとの配分だけが変わります（スペースの都合で接点ベースは省略しています）。

| チャネル | ラストクリック | 線形 | 時間減衰 |
|---------|---------------:|-----:|---------:|
| google / cpc | ¥825,000（55%） | ¥600,000（40%） | ¥720,000（48%） |
| (direct) / (none) | ¥420,000（28%） | ¥330,000（22%） | ¥375,000（25%） |
| yahoo / organic | ¥180,000（12%） | ¥300,000（20%） | ¥225,000（15%） |
| instagram / social | ¥75,000（5%） | ¥270,000（18%） | ¥180,000（12%） |
| 合計 | ¥1,500,000 | ¥1,500,000 | ¥1,500,000 |

LLM には、この表と一緒に次のように依頼します。

```text
以下は4つのアトリビューションモデルによるチャネル別売上配分です（合計はいずれも同額）。
（表を貼る）

以下を分析してください：
1. モデル間で評価が大きく変わるチャネルとその理由
2. 認知系チャネル（SNS、ディスプレイ）の過小評価リスク
3. 予算配分の見直し提案（ただし、このデータだけでは言えないことも明記する）
```

サンプルの表から読み取れるのは次の点です。

- **instagram / social**: ラストクリックでは5%、線形では18%。購入の手前よりも早い段階で接触が起きるチャネルは、ラストクリックだと小さく見える
- **google / cpc**: ラストクリックでは55%、線形では40%。刈り取りに近い位置に偏っている
- **yahoo / organic**: ラストクリック12%に対して、線形では20%。途中の接触での貢献が見える

ただし、アトリビューションの配分は「貢献度の正解」ではありません。モデルの前提を変えた場合の見え方の違いです。予算を動かす判断は、小さく試して結果を見ながら進めるのが安全です。

---

## Step 5：Python でワンコマンド実行にする

Step 1〜3 の SQL を実行し、結果を Claude API に渡して要約させるスクリプトです。このコードは Claude Code に書かせて、手元で実行・修正できます。ファイル構成は次のとおりです。

```text
queries/attribution/touchpoints.sql    # Step 1 の WITH 句
queries/attribution/last_click.sql     # Step 2 の SELECT
queries/attribution/linear.sql
queries/attribution/time_decay.sql     # Step 3 の SELECT
queries/attribution/position_based.sql
```

```python
"""
attribution_analysis.py
目的: 4つのアトリビューションSQLをBigQueryで実行し、結果をClaude APIで要約する
依存: google-cloud-bigquery, db-dtypes, anthropic, python-dotenv
環境変数: ANTHROPIC_API_KEY（.env から読み込む）
"""

import json
from pathlib import Path

import anthropic
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

QUERY_DIR = Path("queries/attribution")
MODEL_NAME = "claude-sonnet-5-5"  # 現行モデルのID。最新は公式のモデル一覧で確認する


def run_attribution_query(model: str) -> list:
    """共通のWITH句に、モデル別のSELECTを連結して実行する"""
    base = (QUERY_DIR / "touchpoints.sql").read_text(encoding="utf-8")
    body = (QUERY_DIR / f"{model}.sql").read_text(encoding="utf-8")
    client = bigquery.Client()
    df = client.query(base + "\n" + body).to_dataframe()
    return df.to_dict(orient="records")


def analyze_with_claude(results: dict) -> str:
    """Claude APIで比較結果を要約し、予算配分の見直し案を作る"""
    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY を環境変数から読む

    # Timestamp や Decimal が含まれても落ちないよう default=str を指定する
    payload = json.dumps(results, ensure_ascii=False, indent=2, default=str)

    message = client.messages.create(
        model=MODEL_NAME,
        max_tokens=4096,
        messages=[{
            "role": "user",
            "content": (
                "以下のアトリビューション分析結果を比較し、"
                "チャネル別の予算配分見直し提案を作成してください。"
                "このデータだけでは言えないことも明記してください。\n\n"
                + payload
            ),
        }],
    )
    # 応答には text 以外のブロックが含まれることがあるため、text だけを連結する
    return "".join(b.text for b in message.content if b.type == "text")


def main():
    models = ["last_click", "linear", "time_decay", "position_based"]
    results = {}
    for model in models:
        print(f"{model}モデルを実行中...")
        results[model] = run_attribution_query(model)

    print("Claude APIで分析中...")
    analysis = analyze_with_claude(results)

    output_path = Path("reports/attribution_analysis.md")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(analysis, encoding="utf-8")
    print(f"分析結果を保存しました: {output_path}")


if __name__ == "__main__":
    main()
```

以前のバージョンでは `claude-sonnet-4-20250514` を指定していましたが、このモデルは 2026-06-15 に廃止され、現在は呼び出せません。公式の[廃止モデル一覧](https://platform.claude.com/docs/en/about-claude/model-deprecations)の推奨移行先は `claude-sonnet-5-5` です。モデルIDは入れ替わるため、実行前に公式の[モデル一覧](https://platform.claude.com/docs/en/about-claude/models/overview)を確認してください。

---

## まとめ

- GA4 では線形・時間減衰・接点ベースが 2023年11月に廃止されたため、比べたい場合は BigQuery で自作する
- SQL は「購入ごとに、購入前のセッションを並べる」共通CTEを作り、モデルごとの SELECT を足す形にすると崩れにくい
- 次にやること: 自社の 1 か月分で 4 モデルを回し、ラストクリックと線形で順位が入れ替わるチャネルがないかを見る

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
[データ分析スポットプラン](https://coconala.com/services/554778)
:::

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::
