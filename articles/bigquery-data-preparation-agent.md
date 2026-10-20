---
title: "Data Preparation Agentでデータクレンジングを任せる"
emoji: "🧹"
type: "tech"
topics: ["BigQuery", "DataEngineering", "AI", "GCP", "Agent"]
published: true
---

## BigQueryのデータ前処理で時間がかかる理由

BigQueryに取り込んだ生データをそのまま分析に使えることは少ない。実務では次のような前処理が必要になる。

- NULL値や空文字の扱いをカラムごとに検討する
- 日付や金額のフォーマットがソースによって異なる
- 重複レコードを特定して除外するロジックを考える
- 外れ値の閾値をデータ分布から決めてフラグを立てる
- カテゴリ名の表記ゆれを統一する（「東京都」「東京」「Tokyo」など）

これらをSQLで一から書くと時間がかかり、チェックの手間も大きい。BigQueryのData Preparation Agentを使うと、クレンジング作業を自然言語で指示しながら進められる。

本記事ではData Preparation Agentを使ったデータクレンジングの手順を解説する。

## Data Preparation Agentとは

Data Preparation AgentはBigQuery Studioに組み込まれたAIエージェント機能の一つで、データの品質改善・前処理を専門とする。自然言語でクレンジング方針を伝えると、対応するSQLを生成して実行し、結果テーブルを出力する。

他のエージェントとの役割分担は以下のとおりだ。

| エージェント | 主な用途 |
|---|---|
| Data Engineering Agent | パイプライン構築・改修・移行 |
| Data Science Agent | 特徴量エンジニアリング・モデル学習・評価 |
| Data Preparation Agent | データクレンジング・前処理・品質確認 |
| Conversational Analytics | 対話的な探索的分析 |

## 事前準備

### 必要な権限

Data Preparation Agentを利用するには以下のIAMロールが必要だ。

- `roles/bigquery.dataEditor`（データセットへの書き込み権限）
- `roles/bigquery.jobUser`（クエリ実行権限）
- `roles/bigquery.connectionUser`（Vertex AI接続の利用権限）
- `roles/aiplatform.user`（Vertex AIモデルの利用権限）

Vertex AI接続の設定はK-02「BigQueryでAI機能を使うためのIAM・Vertex AI接続セットアップ」を参照。

### Agentの起動

BigQuery Studioを開き、画面右上の「Agent」アイコンをクリックする。エージェントパネルが開いたら「Data Preparation」を選択する。

## ステップ1：データ品質の診断

クレンジングを始める前に、対象テーブルの品質状況をAgentに診断させる。ここではEC注文データを例に進める。

### Agentへの指示

```
テーブル「analytics.raw_ec_orders」のデータ品質を診断してください。
NULL値の割合、重複行の有無、各カラムの型と値の分布を確認してください。
```

Agentはテーブル全体を走査し、品質レポートを返す。

```
データ品質レポート: analytics.raw_ec_orders
総行数: 892,341行

カラム別NULL率:
- order_id: 0.0%
- user_id: 0.0%
- order_date: 0.1%（842行）
- amount: 0.8%（7,139行）
- prefecture: 3.2%（28,555行）
- product_category: 0.0%

重複行（order_id重複）: 1,203行
日付フォーマット混在: order_dateに "2026/01/15" と "2026-01-15" が混在
金額の異常値: amount < 0 が47行
都道府県名の表記ゆれ: "東京都"/"東京"/"TOKYO" など12パターン
```

この診断結果をもとに、クレンジング方針を決める。

## ステップ2：NULL値の処理

診断結果をもとに、NULL値の処理方針をAgentに伝える。

### Agentへの指示

```
以下の方針でNULL値を処理してください。
- order_date が NULL: レコードを除外
- amount が NULL: 0で埋める
- prefecture が NULL: "不明" で埋める
処理後のテーブルを「analytics.cleaned_ec_orders_v1」として保存してください。
```

Agentが生成するSQL：

```sql
CREATE OR REPLACE TABLE `analytics.cleaned_ec_orders_v1` AS
SELECT
  order_id,
  user_id,
  order_date,
  COALESCE(amount, 0) AS amount,
  COALESCE(prefecture, '不明') AS prefecture,
  product_category
FROM `analytics.raw_ec_orders`
WHERE order_date IS NOT NULL
```

Agentはクエリ実行後に処理結果を報告する。

```
処理完了
入力行数: 892,341行
除外行数（order_date NULL）: 842行
amount を 0 で補完: 7,139行
prefecture を "不明" で補完: 28,555行
出力行数: 891,499行
```

## ステップ3：重複レコードの除去

次に重複行を除去する。ECデータでは同じorder_idが複数回取り込まれるケースがある。

### Agentへの指示

```
「analytics.cleaned_ec_orders_v1」の order_id 重複を除去してください。
同じ order_id が複数ある場合は、最新の取り込みレコード（行番号が大きいもの）を残してください。
結果を同テーブルに上書きしてください。
```

Agentが生成するSQL：

```sql
CREATE OR REPLACE TABLE `analytics.cleaned_ec_orders_v1` AS
SELECT * EXCEPT(row_num)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY _row_number DESC
    ) AS row_num
  FROM `analytics.cleaned_ec_orders_v1`
)
WHERE row_num = 1
```

実際のテーブルに`_row_number`列がない場合、Agentは代替案として取り込み日時カラムを使った重複除去クエリを提案する。

## ステップ4：日付フォーマットの統一

### Agentへの指示

```
「analytics.cleaned_ec_orders_v1」の order_date カラムに
"2026/01/15" 形式と "2026-01-15" 形式が混在しています。
すべて DATE 型の "YYYY-MM-DD" 形式に統一してください。
```

Agentが生成するSQL：

```sql
CREATE OR REPLACE TABLE `analytics.cleaned_ec_orders_v1` AS
SELECT
  * EXCEPT(order_date),
  CASE
    WHEN REGEXP_CONTAINS(CAST(order_date AS STRING), r'\d{4}/\d{2}/\d{2}')
    THEN PARSE_DATE('%Y/%m/%d', CAST(order_date AS STRING))
    ELSE order_date
  END AS order_date
FROM `analytics.cleaned_ec_orders_v1`
```

## ステップ5：外れ値の処理

金額の負値や明らかな異常値を除外・フラグ立てする。

### Agentへの指示

```
amount の分布を確認し、外れ値の処理をしてください。
- amount < 0 のレコードは除外
- amount が上位0.1%（99.9パーセンタイル）を超える場合は is_outlier = TRUE フラグを立てる
外れ値フラグ付きで「analytics.cleaned_ec_orders_v2」に保存してください。
```

Agentが生成するSQL：

```sql
CREATE OR REPLACE TABLE `analytics.cleaned_ec_orders_v2` AS
WITH stats AS (
  SELECT
    APPROX_QUANTILES(amount, 1000)[OFFSET(999)] AS p999
  FROM `analytics.cleaned_ec_orders_v1`
  WHERE amount >= 0
)
SELECT
  t.*,
  CASE WHEN t.amount > s.p999 THEN TRUE ELSE FALSE END AS is_outlier
FROM `analytics.cleaned_ec_orders_v1` t
CROSS JOIN stats s
WHERE t.amount >= 0
```

Agentは実行後に分布の変化を報告する。

```
処理完了
除外行数（amount < 0）: 47行
外れ値フラグ（is_outlier = TRUE）: 893行（全体の0.1%）
p999（閾値）: 89,800円
出力行数: 891,452行
```

## ステップ6：カテゴリ名の表記ゆれ統一

都道府県名など表記ゆれが多いカラムを正規化する。

### Agentへの指示

```
prefecture カラムの表記ゆれを確認して、統一案を提示してください。
"東京都"に統一すべきパターンをリストアップし、
REPLACE関数を使った正規化クエリを生成してください。
```

Agentの出力例：

```
検出した表記ゆれ（東京都関連）:
- "東京" → "東京都"（12,341件）
- "TOKYO" → "東京都"（234件）
- "tokyo" → "東京都"（89件）
- "東 京都" → "東京都"（3件）

正規化クエリ:
```

```sql
CREATE OR REPLACE TABLE `analytics.cleaned_ec_orders_v2` AS
SELECT
  * EXCEPT(prefecture),
  CASE
    WHEN REGEXP_CONTAINS(LOWER(TRIM(prefecture)), r'^tokyo$|^東京$') THEN '東京都'
    WHEN REGEXP_CONTAINS(LOWER(TRIM(prefecture)), r'^osaka$|^大阪$') THEN '大阪府'
    WHEN REGEXP_CONTAINS(LOWER(TRIM(prefecture)), r'^kyoto$|^京都$') THEN '京都府'
    ELSE TRIM(prefecture)
  END AS prefecture
FROM `analytics.cleaned_ec_orders_v2`
```

## クレンジング結果の検証

一連のクレンジングが完了したら、Agentに検証を依頼する。

### Agentへの指示

```
「analytics.cleaned_ec_orders_v2」のデータ品質を再診断してください。
元テーブルと比較して、改善された項目を一覧にしてください。
```

Agentは差分レポートを返す。

```
データ品質比較レポート

| 指標 | クレンジング前 | クレンジング後 |
|---|---|---|
| 総行数 | 892,341 | 891,452 |
| order_date NULL率 | 0.1% | 0.0% |
| amount NULL率 | 0.8% | 0.0% |
| prefecture NULL率 | 3.2% | 0.0% |
| 重複order_id | 1,203件 | 0件 |
| amount < 0 | 47件 | 0件 |
| 日付フォーマット混在 | あり | なし |
| 都道府県表記ゆれ | 12パターン | 1パターン |
```

## 処理をパイプライン化する

一度確認したクレンジングロジックは、スケジュールクエリや Cloud Composer のDAGとして定期実行できる。

### Agentへの指示

```
今回のクレンジング手順をまとめた一つのSQLクエリとして出力してください。
「analytics.raw_ec_orders」を入力として「analytics.cleaned_ec_orders」に出力する形にしてください。
```

Agentは各ステップを統合したSQLを生成する。これをBigQueryのスケジュールクエリに設定すれば、毎朝の自動実行が可能になる。

## 注意点

### クレンジック方針の確認

Agentが提案する処理内容（NULLの補完値、外れ値の閾値など）は、ビジネスの文脈に合わせて都度確認する。例えば「amount = 0」が正常注文なのかキャンセルなのかは、業務知識がないと判断できない。

### 元テーブルは保持する

Agentが生成するSQLは既存テーブルを上書きする場合がある。作業前に元テーブルのスナップショットを取るか、新しいテーブル名で保存する運用を徹底する。

### 大量データへの適用

テーブルが数十億行規模の場合、クレンジング処理のコストが大きくなる。Agentに「処理対象を直近1ヶ月に絞ってまず確認したい」と伝えることで、検証段階のコストを抑えられる。

## まとめ

Data Preparation Agentを使うと、以下のクレンジング作業を自然言語で進められる。

- データ品質の診断（NULL率・重複・フォーマット混在の確認）
- NULL値の補完・除外
- 重複レコードの除去
- 日付・文字列フォーマットの統一
- 外れ値の除外・フラグ立て
- カテゴリ名の表記ゆれ統一

SQLを一から書く手間が減り、クレンジング方針の検討とレビューに集中できる。次のK-25ではBigQuery MCPサーバーを使ってエージェントからBigQueryを操作する方法を解説する。

---

BigQueryのデータ活用・AI機能の導入について、実務レベルのサポートを提供しています。ご相談はこちらからどうぞ。

https://coconala.com/services/3332133
