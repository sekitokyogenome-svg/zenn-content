---
title: "Claude Codeに競合サイトの施策をGA4データから推測させた話"
emoji: "🔍"
type: "tech"
topics: ["claudecode", "bigquery", "marketing"]
published: false
---

## はじめに

「競合がどんな施策を打っているのか知りたいけど、調べる方法がわからない」

ECサイトを運営していると、競合の動きが気になるものです。しかし、他社のGA4データを直接見ることはできません。一方で、**自社のGA4データのトレンド変化**には、競合の施策の影響が間接的に表れていることがあります。

この記事では、自社GA4データをBigQueryで分析し、そのトレンド変化からClaude Codeに競合施策の推測を行わせた方法を紹介します。

---

## なぜ自社データから競合を推測できるのか

ECの世界では、市場のパイが限られている領域があります。たとえば以下のような変化があった場合、競合の動きが影響している可能性があります。

- **特定キーワードからの流入が急減した** → 競合が同キーワードの広告出稿を強化した
- **ブランド検索流入が一時的に急増した** → 業界メディアで自社が言及された、または競合トラブルの受け皿になった
- **特定カテゴリの購入率が下がった** → 競合が同カテゴリでセールを実施した

こうした「自社データの異常値」を体系的に検出し、仮説を立てる作業をClaude Codeに支援させます。

---

## Step 1：トレンド変化を検出するSQLを用意する

まず、BigQueryで週次のチャネル別セッション数と購入率を抽出します。

```sql
-- 週次チャネル別パフォーマンス
WITH sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
weekly_metrics AS (
  SELECT
    week_start,
    CONCAT(IFNULL(source, '(direct)'), ' / ', IFNULL(medium, '(none)')) AS channel,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions
  FROM sessions
  GROUP BY week_start, channel
)
SELECT
  week_start,
  channel,
  sessions,
  LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start) AS prev_week_sessions,
  SAFE_DIVIDE(
    sessions - LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start),
    LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start)
  ) AS wow_change_rate
FROM weekly_metrics
ORDER BY week_start DESC, sessions DESC;
```

このSQLで「前週比で大きく変動したチャネル」を一覧化できます。

---

## Step 2：Claude Codeに異常値を検出させる

Claude Codeにデータを渡し、異常値の検出と仮説の生成を依頼します。

```text
以下はGA4のBigQueryデータから抽出した、
週次チャネル別セッション数と前週比変化率です。

[CSVデータをここに貼り付け]

以下の観点で分析してください：
1. 前週比で ±20% 以上変動したチャネルをリストアップ
2. 変動の考えられる要因を3パターン挙げる
   - 自社要因（施策変更、サイト更新など）
   - 市場要因（季節性、トレンドなど）
   - 競合要因（競合の施策推測）
3. 競合要因の仮説について、裏付けを取るための調査方法を提案
```

:::message
Claude Codeはターミナル上で動作するため、CSVファイルを直接読み込ませることもできます。`cat data.csv` のコマンドをClaude Codeに実行させれば、データの貼り付けは不要です。
:::

---

## Step 3：購入率の変動も加える

セッション数だけでなく、カテゴリ別の購入率変動も加えると、より精度の高い推測ができます。

```sql
-- 週次カテゴリ別CVR
WITH purchase_sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    event_name
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase')
)
SELECT
  week_start,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  END) AS purchase_sessions,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    END),
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    )
  ) AS cvr
FROM purchase_sessions
GROUP BY week_start
ORDER BY week_start DESC;
```

---

## Step 4：推測結果を構造化する

Claude Codeに出力フォーマットを指定すると、レポートとして使いやすい形にまとめてくれます。

```text
以下のフォーマットで競合施策の推測レポートを作成してください：

## 競合施策推測レポート（YYYY年MM月第N週）

### 検出された異常値
| チャネル | 変動率 | 影響度 |
|---------|--------|--------|

### 仮説
#### 仮説1: [タイトル]
- 根拠:
- 推測される競合施策:
- 確認方法:

### 推奨アクション
- 短期（今週中）:
- 中期（今月中）:
```

---

## 実際に得られた分析結果の例

某ECサイトで実施したところ、以下のような推測が得られました。

- **google / cpc の流入が前週比 -35%**: 競合が同カテゴリの広告入札を強化し、CPCが上昇した可能性。Google Ads管理画面でインプレッションシェアの推移を確認すべき
- **organic の流入が前週比 +18%**: 競合のサイトダウンや検索順位低下により、自社の相対順位が上昇した可能性。Search Consoleの掲載順位推移で裏付け可能

これらの推測は、あくまで仮説です。しかし「何を調べるべきか」が明確になるだけで、競合分析の効率は大きく変わります。

---

## 注意点

### 推測はあくまで仮説

Claude Codeが出す競合施策の推測は、自社データからの間接的な推論です。裏付けなしに意思決定に使うのは避けてください。

### 外部データとの組み合わせが有効

- Google Adsのオークション分析レポート
- Search Consoleの検索順位データ
- SimilarWeb等の競合分析ツール

これらと組み合わせることで、推測の精度を高められます。

### プロンプトの改善を繰り返す

最初から完璧な推測は出ません。出力を見てプロンプトを改善する「プロンプトの反復改善」が重要です。

---

## まとめ

自社GA4データのトレンド変化をBigQueryで抽出し、Claude Codeに分析させることで、競合施策の推測を効率化できます。

ポイントは以下の3つです。

1. 週次のチャネル別変動率をSQLで抽出する
2. Claude Codeに異常値の検出と仮説生成を依頼する
3. 外部データと組み合わせて仮説を検証する

「データはあるけど、分析する時間がない」という状況を、AIの力で打開する一つの方法として参考にしてみてください。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
