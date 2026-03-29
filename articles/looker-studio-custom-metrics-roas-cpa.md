---
title: "Looker Studioのカスタム指標でROAS・CPAを自動計算する設定"
emoji: "🧮"
type: "tech"
topics: ["lookerstudio","advertising","ec"]
published: false
---

## はじめに

「広告レポートを毎回手動でExcelに落として、ROAS・CPAを計算している」という作業を続けていないでしょうか。

Looker Studioの「計算フィールド」機能を使えば、ROAS（広告費用対効果）やCPA（顧客獲得単価）をダッシュボード上で自動計算できます。一度設定すれば、日付フィルタを変えるだけで任意の期間のROAS・CPAが即座に表示されます。

この記事では、Looker Studioでの計算フィールドの作成方法と、広告指標の設定パターンを実践的に解説します。

## 計算フィールドとは

計算フィールドは、Looker Studio上でデータソースのフィールドを組み合わせて新しい指標やディメンションを作る機能です。SQLを書かずに、関数と演算子で計算式を定義できます。

### 計算フィールドの作成場所

計算フィールドは2つの場所で作成できます。

| 作成場所 | スコープ | 用途 |
|---|---|---|
| データソースレベル | そのデータソースを使うすべてのレポートで利用可能 | 共通で使う指標（ROAS、CPAなど） |
| グラフレベル | そのグラフ内のみ | 特定のグラフでだけ使う一時的な計算 |

広告指標のようにレポート全体で使うものは、データソースレベルで作成するのが効率的です。

## ROAS（広告費用対効果）の計算フィールド

### ROASの定義

```
ROAS = 売上（収益） ÷ 広告費用
```

ROASが3.0であれば、広告費1円あたり3円の売上があるという意味です。

### Looker Studioでの設定手順

1. 「リソース」→「追加済みのデータソースの管理」
2. 対象データソースの「編集」をクリック
3. 「フィールドを追加」をクリック
4. 以下の内容を入力

```
フィールド名: ROAS
計算式: SUM(revenue) / SUM(ad_cost)
データ型: 数値
```

:::message
ゼロ除算を防ぐために、`CASE WHEN SUM(ad_cost) > 0 THEN SUM(revenue) / SUM(ad_cost) ELSE 0 END` とするのが安全です。もしくはBigQueryのビュー側で`SAFE_DIVIDE`を使う方法もあります。
:::

### BigQueryでROASを事前計算する方法

データソースがBigQueryの場合、SQL側で計算しておくこともできます。

```sql
SELECT
  date,
  campaign_name,
  SUM(revenue) AS revenue,
  SUM(ad_cost) AS ad_cost,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_cost)) AS roas
FROM
  `project.dataset.campaign_performance`
GROUP BY
  date, campaign_name
```

SQL側で計算する利点は、`SAFE_DIVIDE`によるゼロ除算対策が組み込める点と、集計ロジックをSQLに一元管理できる点です。

## CPA（顧客獲得単価）の計算フィールド

### CPAの定義

```
CPA = 広告費用 ÷ コンバージョン数
```

CPAが5,000円であれば、1件のコンバージョンを獲得するのに5,000円の広告費がかかっているという意味です。

### Looker Studioでの設定

```
フィールド名: CPA
計算式: CASE WHEN SUM(conversions) > 0 THEN SUM(ad_cost) / SUM(conversions) ELSE 0 END
データ型: 通貨（JPY）
```

## その他の広告指標の計算フィールド

### CTR（クリック率）

```
フィールド名: CTR
計算式: SUM(clicks) / SUM(impressions)
データ型: パーセント
```

### CVR（コンバージョン率）

```
フィールド名: CVR
計算式: SUM(conversions) / SUM(clicks)
データ型: パーセント
```

### CPC（クリック単価）

```
フィールド名: CPC
計算式: SUM(ad_cost) / SUM(clicks)
データ型: 通貨（JPY）
```

### CPM（インプレッション単価）

```
フィールド名: CPM
計算式: (SUM(ad_cost) / SUM(impressions)) * 1000
データ型: 通貨（JPY）
```

## 条件付き書式でアラートを設定する

計算フィールドを作成したら、条件付き書式を使って基準値を下回った（上回った）場合に色でアラートを表示できます。

### スコアカードの条件付き書式

1. ROASのスコアカードを選択
2. 「スタイル」タブを開く
3. 「条件付き書式」→「追加」をクリック
4. ルールを設定

```
ルール1: 値 >= 3.0 → 背景色: 緑
ルール2: 値 >= 1.0 かつ < 3.0 → 背景色: 黄
ルール3: 値 < 1.0 → 背景色: 赤
```

ROASが1.0を下回ると赤字（広告費>売上）なので、赤で表示すると経営者が即座に気づけます。

### テーブルの条件付き書式

テーブル形式でキャンペーン別のROAS・CPAを表示する場合も、同様の条件付き書式が使えます。

1. テーブルのグラフを選択
2. 「スタイル」→ 指標の列で「条件付き書式」を開く
3. ヒートマップ形式またはルールベースで設定

## ダッシュボード構成例: 広告パフォーマンスレポート

以下の構成で広告パフォーマンスのダッシュボードを作ると、経営判断に直結する情報が一画面にまとまります。

### 上段: KPIスコアカード

| ROAS | CPA | 広告費 | 売上 | CVR |
|---|---|---|---|---|
| 条件付き書式で色分け | 目標値との比較 | 期間合計 | 期間合計 | 期間平均 |

### 中段: 時系列トレンド

- X軸: 日付
- 左Y軸: 広告費用（棒グラフ）、売上（棒グラフ）
- 右Y軸: ROAS（折れ線グラフ）

### 下段: キャンペーン別テーブル

| キャンペーン名 | 費用 | 売上 | ROAS | CPA | CTR | CVR |
|---|---|---|---|---|---|---|
| キャンペーンA | ¥100,000 | ¥350,000 | 3.5 | ¥2,500 | 2.1% | 3.5% |
| キャンペーンB | ¥80,000 | ¥120,000 | 1.5 | ¥8,000 | 1.2% | 1.0% |

ROASの列にはヒートマップ形式の条件付き書式を設定し、パフォーマンスの良し悪しを視覚化します。

## BigQueryで統合広告テーブルを作るSQL

Google広告とMeta広告など、複数の広告プラットフォームのデータを1つのテーブルにまとめると、横断的な分析が可能になります。

```sql
CREATE OR REPLACE VIEW `project.dataset.unified_ads_performance` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS ad_cost,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `project.dataset.p_CampaignStats_XXXXXXX`
GROUP BY date, campaign_name

UNION ALL

-- Meta Ads（別途BigQueryに連携済みの想定）
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS ad_cost,
  SUM(clicks) AS clicks,
  SUM(impressions) AS impressions,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `project.dataset.meta_ads_daily`
GROUP BY date, campaign_name
```

このビューをLooker Studioに接続し、`platform` ディメンションでフィルタすれば、プラットフォーム別・横断の両方の分析ができます。

## よくある問題と対処法

### 計算フィールドで「集計できません」エラーが出る

計算式の中で集計関数（SUM、COUNTなど）を使っていない場合に発生します。計算フィールドでは、指標同士の演算には明示的にSUMやCOUNTを使ってください。

### フィルタ適用時にROASがおかしな値になる

フィルタで期間を絞ったときに、ROASが異常に高い値や低い値になる場合は、分母（広告費）がゼロに近い期間が含まれている可能性があります。ゼロ除算対策のCASE文を入れてください。

### 通貨の表示形式がずれる

計算フィールドのデータ型を「通貨（JPY）」に設定しているか確認してください。また、グラフの「スタイル」タブで桁区切りや小数点以下の表示を調整できます。

## まとめ

Looker Studioの計算フィールドを活用すれば、ROAS・CPA・CTR・CVRといった広告指標を自動で計算・表示できます。

- **計算フィールド**: データソースレベルで作成し、レポート全体で再利用
- **条件付き書式**: 基準値を下回ったら赤表示で即座に気づける
- **BigQueryとの連携**: 複数プラットフォームのデータを統合し、横断分析を実現

手動レポート作成の工数を削減しつつ、リアルタイムで広告パフォーマンスを監視できる環境を構築してみてください。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
