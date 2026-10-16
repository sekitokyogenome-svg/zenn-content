---
title: "Data Engineering Agentで既存パイプラインを改修・移行する"
emoji: "🔧"
type: "tech"
topics: ["BigQuery", "DataEngineering", "AI", "GCP", "Agent"]
published: true
---

## 既存パイプラインの改修はなぜ難しいのか

BigQueryで運用を続けているデータパイプラインには、次のような課題が蓄積しやすい。

- スケジュールクエリが増えすぎて依存関係が把握できない
- 旧来のML.GENERATE_TEXTを使っているためAI.*関数へ移行したい
- 書いた担当者が離れ、意図が読めないSQLが残っている
- パーティション設計が古く、コストが増え続けている

こうした改修や移行作業は、影響範囲の調査から始めて手で書き直すと非常に時間がかかる。BigQueryのData Engineering Agentを使うと、自然言語で指示するだけで既存パイプラインの分析・修正・移行を進められる。

本記事ではData Engineering Agentを使って既存パイプラインを改修・移行する手順を、実務で使えるプロンプトとともに解説する。

## Data Engineering Agentとは

Data Engineering Agentは、BigQuery Studioのエージェント機能の一つだ。パイプラインの作成だけでなく、既存のクエリやスケジュール設定を読み取り、変更・改善を提案・実行する能力を持つ。

前記事「Data Engineering Agentで自然言語からパイプラインを作る」では新規作成を扱った。本記事では**改修と移行**に絞って解説する。

## 事前準備

### 必要な権限

Data Engineering Agentを利用するには以下のIAMロールが必要だ。

- `roles/bigquery.dataEditor`（データセットへの書き込み権限）
- `roles/bigquery.jobUser`（クエリ実行権限）
- `roles/bigquery.connectionUser`（Vertex AI接続の利用権限）

接続設定はK-02「BigQueryでAI機能を使うためのIAM・Vertex AI接続セットアップ」を参照。

### Agentの起動

BigQuery Studioを開き、画面右上の「Agent」アイコンをクリックする。エージェントパネルが開いたら「Data Engineering」を選択する。

## ユースケース1：ML.GENERATE_TEXTからAI.*関数への移行

2024年以降、BigQueryではML.GENERATE_TEXTよりもAI.*関数が推奨されるようになった。既存のMLモデル呼び出しをAI.*関数に移行するケースを見てみる。

### 対象クエリの例

```sql
-- 移行前（ML.GENERATE_TEXT使用）
SELECT
  product_id,
  ML.GENERATE_TEXT(
    MODEL `project.dataset.gemini_model`,
    STRUCT(description AS prompt),
    STRUCT(0.3 AS temperature, 500 AS max_output_tokens)
  ).predictions[0].content AS generated_text
FROM `project.dataset.products`
```

### Agentへの指示

エージェントパネルに以下のように入力する。

```
上記クエリをML.GENERATE_TEXTからAI.GENERATE関数に移行してください。
モデルはgemini-2.0-flash-001、max_output_tokensは500を維持してください。
```

Agentは差分を提示しつつ、修正後のクエリを出力する。

```sql
-- 移行後（AI.GENERATE使用）
SELECT
  product_id,
  AI.GENERATE(
    STRUCT(
      description AS prompt,
      'gemini-2.0-flash-001' AS model,
      STRUCT(0.3 AS temperature, 500 AS max_output_tokens) AS generate_options
    )
  ).text AS generated_text
FROM `project.dataset.products`
```

変更点はすぐ確認できる。Agentが生成した説明文も合わせて読んでおくと、移行の背景を理解しやすい。

## ユースケース2：スケジュールクエリの依存関係整理

複数のスケジュールクエリが積み重なると、どのクエリがどのテーブルに依存しているか把握しにくくなる。

### Agentへの指示

```
データセット「analytics_mart」内のすべてのビューとテーブルの依存関係を調べ、
実行順序をDAGとして整理してください。
問題があれば改善案も提示してください。
```

Agentはデータセット内のテーブル定義・ビュー定義を走査し、依存関係を整理したリストを返す。循環参照やデッドコード（参照されていないテーブル）も検出できる。

出力例：

```
1. raw_events（ソーステーブル）
2. stg_sessions（raw_eventsに依存）
3. mart_daily_revenue（stg_sessionsに依存）
4. mart_user_ltv（mart_daily_revenueに依存）

問題：view_old_ga（2023年以前）は現在どこからも参照されていません。
削除または非推奨化を検討してください。
```

この出力をもとに、不要なテーブルやビューを整理できる。

## ユースケース3：パーティション設計の改善

古いテーブルにパーティションが設定されていない場合、クエリのたびにフルスキャンが走りコストが膨らむ。

### 現状確認のプロンプト

```
テーブル「project.dataset.ga4_events_flat」のパーティション設定を確認し、
現在の月次コストを概算してください。
改善案があれば提示してください。
```

### Agentの回答例

```
現在: パーティションなし、全データフルスキャン（推定）
月次クエリコスト概算: 約12,000円（200GB/月のスキャンを想定）

改善案:
event_dateカラムでDAY単位のパーティションを設定することを推奨します。
パーティション刈り込みにより、スキャン量を日次クエリで約97%削減できます。

移行用SQLを生成しますか？
```

「はい」と返すと移行用のCREATE TABLE AS SELECT文を出力してくれる。

```sql
CREATE OR REPLACE TABLE `project.dataset.ga4_events_flat_v2`
PARTITION BY DATE(event_date)
CLUSTER BY event_name, user_pseudo_id
AS
SELECT * FROM `project.dataset.ga4_events_flat`;
```

## ユースケース4：GA4データの集計ロジック修正

GA4のBigQueryエクスポートを使う際、ga_session_idの取得方法が古いクエリでは誤っているケースがある。

### よくある誤ったパターン

```sql
-- NG: ga_session_idを直接参照しようとする誤ったアプローチ
SELECT
  user_pseudo_id,
  ga_session_id  -- このカラムは存在しない
FROM `project.dataset.events_*`
```

### Agentへの指示で修正

```
ga_session_idをevent_paramsからUNNESTで正しく取得するよう修正してください。
```

修正後：

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id
FROM `project.dataset.events_*`
```

AgentはGA4のスキーマ特性を理解しており、UNNEST経由での正しい取得方法を提案する。

## ユースケース5：collected_traffic_sourceを使ったトラフィック分析への移行

旧来のクエリでは`event_params`からトラフィック情報を取得していたが、`collected_traffic_source`を使うとよりシンプルに書ける。

### Agentへの指示

```
event_paramsからmediumとsourceを取得している箇所を、
collected_traffic_sourceを使う形に書き換えてください。
```

修正前：

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source
FROM `project.dataset.events_*`
WHERE event_name = 'session_start'
```

修正後：

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM `project.dataset.events_*`
WHERE event_name = 'session_start'
```

`collected_traffic_source.manual_medium`を使うことでコードが短くなり、可読性も上がる。

## 移行時の注意点

### 本番環境への反映前に検証する

Agentが提案する変更は、まずビューや別テーブルで動作を確認してから本番テーブルに適用する。特にパーティション変更はデータの再挿入が必要なため、元テーブルは削除せずに残しておく。

### スケジュールクエリの更新は手動確認を挟む

スケジュールクエリのSQL変更はAgentが提案するが、実際の更新はBigQuery Studioのスケジュール管理画面から行う。Agentが直接スケジュールを書き換えるわけではないため、提案内容を確認してから適用する。

### コスト見積もりはあくまで参考値

Agentが提示するコスト見積もりは実際のクエリパターンと異なる場合がある。改善前後でBigQueryの「このクエリを実行すると約XGBのデータが処理されます」の表示を比較するのが正確だ。

## まとめ

Data Engineering Agentを活用すると、次の改修・移行作業を自然言語で指示できる。

- ML.GENERATE_TEXTからAI.*関数への移行
- スケジュールクエリの依存関係整理とDAG可視化
- パーティション設計の改善と移行SQL生成
- GA4クエリの正しいUNNEST・collected_traffic_source活用への修正

既存パイプラインの技術的負債を解消したい場合、まず依存関係の整理から始め、影響範囲を把握してから個別の改修に入るとスムーズに進む。

---

BigQueryのデータパイプライン設計やAI活用について、実務レベルのサポートを提供しています。ご相談はこちらからどうぞ。

https://coconala.com/services/3332133
