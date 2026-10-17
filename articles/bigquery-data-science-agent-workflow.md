---
title: "Data Science Agentで特徴量エンジニアリングからモデル評価まで回す"
emoji: "🔬"
type: "tech"
topics: ["BigQuery", "DataScience", "AI", "GCP", "Agent"]
published: true
---

## BigQueryで機械学習を回すときの課題

BigQueryのデータを使って機械学習モデルを構築しようとすると、次の壁にぶつかりやすい。

- 特徴量エンジニアリングのSQLが複雑になり、どこで何を変換しているか把握しにくい
- BigQuery MLの構文を都度調べながら書く必要があり、試行錯誤に時間がかかる
- モデルの評価指標をどう解釈すればよいか、次の改善策が見えにくい
- Python（scikit-learn等）との役割分担に迷い、BigQueryでどこまでやるべきか判断しにくい

BigQueryのData Science Agentを使うと、これらの作業を自然言語で指示しながら進められる。特徴量の作成からモデルの学習・評価まで、エージェントが提案と実行を担ってくれる。

本記事ではData Science Agentを使って特徴量エンジニアリングからモデル評価までを一通り回す手順を解説する。

## Data Science Agentとは

Data Science Agentは、BigQuery Studioに組み込まれたAIエージェント機能の一つだ。自然言語でデータ分析や機械学習の指示を出すと、SQLやML.関数・AI.*関数を組み合わせたクエリを自動生成し、実行・評価まで行う。

他のエージェントとの役割分担は以下のとおりだ。

| エージェント | 主な用途 |
|---|---|
| Data Engineering Agent | パイプライン構築・改修・移行 |
| Data Science Agent | 特徴量エンジニアリング・モデル学習・評価 |
| Data Preparation Agent | データクレンジング・前処理 |
| Conversational Analytics | 対話的な探索的分析 |

## 事前準備

### 必要な権限

Data Science Agentを利用するには以下のIAMロールが必要だ。

- `roles/bigquery.dataEditor`（データセットへの書き込み権限）
- `roles/bigquery.jobUser`（クエリ実行権限）
- `roles/bigquery.connectionUser`（Vertex AI接続の利用権限）
- `roles/aiplatform.user`（Vertex AIモデルの利用権限）

Vertex AI接続の設定はK-02「BigQueryでAI機能を使うためのIAM・Vertex AI接続セットアップ」を参照。

### Agentの起動

BigQuery Studioを開き、画面右上の「Agent」アイコンをクリックする。エージェントパネルが開いたら「Data Science」を選択する。

## ステップ1：データの概要把握

まずはデータセットの内容をAgentに把握させる。ここではEC購買データを例に進める。

### Agentへの指示

```
データセット「analytics.ec_orders」の概要を教えてください。
行数、カラム一覧、欠損値の状況、主要な統計量を確認してください。
```

Agentはデータセットを走査し、概要レポートを返す。

```
テーブル: analytics.ec_orders
行数: 1,234,567行
期間: 2023-01-01 〜 2026-09-30

カラム一覧:
- user_id (STRING): ユーザーID、欠損なし
- order_date (DATE): 注文日、欠損なし
- product_id (STRING): 商品ID、欠損なし
- amount (FLOAT64): 購入金額、欠損0.3%
- category (STRING): 商品カテゴリ、欠損なし
- is_repeat (BOOL): リピート購入フラグ、欠損なし

主要統計:
- amount平均: 4,823円、中央値: 3,200円、最大値: 98,000円
- リピート率: 34.2%
```

この出力をもとに、次の特徴量設計に進む。

## ステップ2：特徴量エンジニアリング

目的変数と特徴量の設計方針をAgentに伝える。ここでは「次回購入があるかどうか」を予測するモデルを構築する。

### 目的変数の定義

```
目的変数として「初回購入から90日以内に2回目の購入をするか（is_repeat_90d）」を
定義するSQLを書いてください。
ユーザー単位で集計し、モデル学習用テーブル「analytics.ml_features」に保存してください。
```

Agentが生成するSQL例：

```sql
CREATE OR REPLACE TABLE `analytics.ml_features` AS
WITH first_purchase AS (
  SELECT
    user_id,
    MIN(order_date) AS first_order_date
  FROM `analytics.ec_orders`
  GROUP BY user_id
),
second_purchase AS (
  SELECT
    o.user_id,
    MIN(o.order_date) AS second_order_date
  FROM `analytics.ec_orders` o
  JOIN first_purchase fp ON o.user_id = fp.user_id
  WHERE o.order_date > fp.first_order_date
  GROUP BY o.user_id
)
SELECT
  fp.user_id,
  fp.first_order_date,
  CASE
    WHEN sp.second_order_date IS NOT NULL
      AND DATE_DIFF(sp.second_order_date, fp.first_order_date, DAY) <= 90
    THEN 1
    ELSE 0
  END AS is_repeat_90d
FROM first_purchase fp
LEFT JOIN second_purchase sp ON fp.user_id = sp.user_id
```

### 説明変数の作成

```
次の特徴量を追加してください。
- 初回購入金額
- 初回購入カテゴリ（ワンホットエンコーディング不要、カテゴリ列のまま）
- 初回購入の曜日（0=月曜、6=日曜）
- 直近90日の購入回数（初回購入日以前）
- 直近90日の平均購入金額（初回購入日以前）

「analytics.ml_features」テーブルに列を追加する形で更新してください。
```

Agentは特徴量計算のSQLを生成し、既存テーブルへの結合クエリを出力する。

```sql
CREATE OR REPLACE TABLE `analytics.ml_features` AS
WITH first_order_detail AS (
  SELECT
    o.user_id,
    o.amount AS first_order_amount,
    o.category AS first_order_category,
    EXTRACT(DAYOFWEEK FROM o.order_date) - 1 AS first_order_dayofweek
  FROM `analytics.ec_orders` o
  JOIN (
    SELECT user_id, MIN(order_date) AS first_order_date
    FROM `analytics.ec_orders`
    GROUP BY user_id
  ) fo ON o.user_id = fo.user_id AND o.order_date = fo.first_order_date
),
pre_purchase_stats AS (
  SELECT
    o.user_id,
    fo.first_order_date,
    COUNT(*) AS pre_order_count_90d,
    AVG(o.amount) AS pre_order_avg_amount_90d
  FROM `analytics.ec_orders` o
  JOIN (
    SELECT user_id, MIN(order_date) AS first_order_date
    FROM `analytics.ec_orders`
    GROUP BY user_id
  ) fo ON o.user_id = fo.user_id
  WHERE o.order_date < fo.first_order_date
    AND o.order_date >= DATE_SUB(fo.first_order_date, INTERVAL 90 DAY)
  GROUP BY o.user_id, fo.first_order_date
)
SELECT
  f.*,
  d.first_order_amount,
  d.first_order_category,
  d.first_order_dayofweek,
  COALESCE(ps.pre_order_count_90d, 0) AS pre_order_count_90d,
  COALESCE(ps.pre_order_avg_amount_90d, 0) AS pre_order_avg_amount_90d
FROM `analytics.ml_features` f
LEFT JOIN first_order_detail d ON f.user_id = d.user_id
LEFT JOIN pre_purchase_stats ps ON f.user_id = ps.user_id
```

## ステップ3：モデルの学習

特徴量テーブルが完成したら、モデルの学習をAgentに指示する。

### Agentへの指示

```
「analytics.ml_features」テーブルを使って、
is_repeat_90dを目的変数とする二値分類モデルを学習してください。
モデルの種類はROGISTIC_REGを使用し、
「analytics.models」データセットに「repeat_predictor_v1」として保存してください。
学習データは2026-01-01以前、評価データはそれ以降とします。
```

Agentが生成するSQL：

```sql
CREATE OR REPLACE MODEL `analytics.models.repeat_predictor_v1`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['is_repeat_90d'],
  data_split_method = 'CUSTOM',
  data_split_col = 'is_train'
) AS
SELECT
  * EXCEPT(user_id, first_order_date),
  CASE WHEN first_order_date < '2026-01-01' THEN TRUE ELSE FALSE END AS is_train
FROM `analytics.ml_features`
```

学習が完了するとAgentが完了通知を返す。

## ステップ4：モデルの評価

学習が終わったら、モデルの精度をAgentに評価させる。

### Agentへの指示

```
「analytics.models.repeat_predictor_v1」の評価指標を確認してください。
精度・再現率・AUCを確認し、実務で使えるレベルかどうか判断してください。
```

Agentの出力例：

```
評価結果（テストデータ: 2026-01-01以降）

精度 (Precision): 0.71
再現率 (Recall): 0.68
AUC-ROC: 0.79
F1スコア: 0.69

判断:
AUC 0.79はベースラインのランダム予測（0.50）と比べて高く、
実務での活用に耐えうる水準です。
ただし再現率0.68は、リピート購入者の約32%を見逃すことを意味します。
リピート促進施策のターゲティングに使う場合は、
閾値を0.4〜0.5に下げることで再現率を高める調整を検討してください。
```

### 特徴量の重要度確認

```
各特徴量がモデルにどれだけ影響しているか確認してください。
```

Agentは`ML.GLOBAL_EXPLAIN`を呼び出し、特徴量重要度を返す。

```sql
SELECT
  feature,
  attribution
FROM
  ML.GLOBAL_EXPLAIN(MODEL `analytics.models.repeat_predictor_v1`)
ORDER BY attribution DESC
```

出力例：

```
feature                    | attribution
first_order_amount         | 0.31
pre_order_avg_amount_90d   | 0.24
pre_order_count_90d        | 0.19
first_order_category       | 0.15
first_order_dayofweek      | 0.11
```

初回購入金額と購入前の行動履歴が、リピート予測に最も効いていることがわかる。

## ステップ5：予測の実行

評価が完了したら、新規ユーザーへの予測を実行する。

### Agentへの指示

```
2026-09-01以降に初めて購入したユーザーに対して、
「analytics.models.repeat_predictor_v1」で90日以内リピート確率を予測し、
結果を「analytics.repeat_predictions_202609」に保存してください。
```

```sql
CREATE OR REPLACE TABLE `analytics.repeat_predictions_202609` AS
SELECT
  user_id,
  first_order_date,
  predicted_is_repeat_90d,
  predicted_is_repeat_90d_probs[OFFSET(1)].prob AS repeat_probability
FROM
  ML.PREDICT(
    MODEL `analytics.models.repeat_predictor_v1`,
    (
      SELECT * EXCEPT(is_repeat_90d)
      FROM `analytics.ml_features`
      WHERE first_order_date >= '2026-09-01'
    )
  )
ORDER BY repeat_probability DESC
```

## モデル改善のサイクル

Agentを使ったモデル改善は以下のサイクルで進めると効率的だ。

1. **特徴量の追加・変換**: Agentに「閲覧ページ数を追加したい」と伝えれば対応するSQLを生成する
2. **モデル種類の変更**: BOOSTED_TREEやDNN_CLASSIFIERへの変更も自然言語で指示できる
3. **ハイパーパラメータ調整**: 「正則化を強くしてオーバーフィットを抑えてほしい」と指示する

### Agentへの継続指示例

```
特徴量にGA4のセッション数（初回購入前30日間）を追加して、
モデルをv2として再学習してください。
v1との精度比較も出してください。
```

Agentは差分の特徴量追加SQLとモデル学習SQLを出力し、評価指標の比較表を返す。

## 注意点

### 学習データのリーク

Agentが生成するSQLに目的変数と関連する情報が特徴量に混入していないか確認する。例えば、「購入回数」の集計期間に目的変数の観測期間が含まれているとリークになる。

### 予測の解釈と閾値設定

Agentはデフォルト閾値0.5での評価を返すが、施策の目的に合わせて閾値を調整する。リピート促進メールを送る場合は閾値を下げて再現率を優先し、コスト効率重視なら閾値を上げて精度を高める。

### BigQuery MLのコスト

モデルの学習はデータ量に比例してコストがかかる。学習前に`--dry_run`相当の見積もりをAgentに依頼しておくとコスト管理しやすい。

## まとめ

Data Science Agentを活用すると、次の一連の作業を自然言語で進められる。

- データ概要の把握と特徴量設計
- 目的変数・説明変数の作成SQL生成
- BigQuery MLによるモデル学習
- 評価指標の確認と解釈
- 新規データへの予測実行

SQLの詳細な記述やML関数の構文を都度調べる手間が減り、特徴量設計やモデル解釈の判断に集中できるようになる。次のK-24では、Data Preparation Agentを使ったデータクレンジングを解説する。

---

BigQueryのデータ活用・AI機能の導入について、実務レベルのサポートを提供しています。ご相談はこちらからどうぞ。

https://coconala.com/services/3332133
