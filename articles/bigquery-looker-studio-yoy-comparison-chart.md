---
title: "BigQuery × Looker Studioで前年同期比グラフを作る方法"
emoji: "📊"
type: "tech"
topics: ["lookerstudio","bigquery","sql"]
published: false
---

## はじめに

「今月の売上は先月より上がっているけど、去年の同じ時期と比べてどうなのか」という質問に、すぐ答えられるでしょうか。

EC事業やWebマーケティングでは、季節変動の影響が大きいため、前月比だけでなく前年同期比（YoY）での分析が重要です。Looker Studio単体でも比較期間の設定はできますが、BigQueryでSQLを組むことでより柔軟な前年比グラフが作れます。

この記事では、BigQueryで前年同期比のデータを準備し、Looker Studioでわかりやすいグラフとして表示する方法を解説します。

## Looker Studio標準の比較機能の限界

Looker Studioには「比較期間」という標準機能があります。日付フィルタで「前の期間」や「前年」を選択できます。

### 標準機能でできること

- 指標の横に前年比の増減率を表示
- スコアカードに前年比の矢印アイコンを表示

### 標準機能の限界

- 時系列グラフで2つの線（今年と去年）を重ねて表示できない
- カスタムな比較ロジック（営業日ベースなど）が組めない
- 比較期間のデータと当期のデータを同じテーブルに横並びで表示しにくい

これらを実現するには、BigQuery側でデータを準備する必要があります。

## BigQueryで前年同期比データを作成するSQL

### 基本パターン: 日別の売上を今年・前年で横並びにする

```sql
WITH current_year AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM
    `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_TRUNC(CURRENT_DATE(), MONTH))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date
),

previous_year AS (
  SELECT
    DATE_ADD(PARSE_DATE('%Y%m%d', event_date), INTERVAL 1 YEAR) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue_ly,
    COUNTIF(event_name = 'purchase') AS purchases_ly,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions_ly
  FROM
    `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 YEAR))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
  GROUP BY date
)

SELECT
  c.date,
  c.revenue AS revenue_current,
  p.revenue_ly AS revenue_previous,
  c.sessions AS sessions_current,
  p.sessions_ly AS sessions_previous,
  SAFE_DIVIDE(c.revenue - p.revenue_ly, p.revenue_ly) * 100 AS revenue_yoy_pct,
  SAFE_DIVIDE(c.sessions - p.sessions_ly, p.sessions_ly) * 100 AS sessions_yoy_pct
FROM
  current_year c
LEFT JOIN
  previous_year p ON c.date = p.date
ORDER BY
  c.date
```

ポイントは `previous_year` CTEで `DATE_ADD(..., INTERVAL 1 YEAR)` を使い、前年の日付を今年の日付に変換していることです。これにより、同じ日付カラムでJOINできます。

### 月別集計パターン

```sql
WITH monthly_data AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month_num,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH))
  GROUP BY month, year, month_num
)

SELECT
  cy.month,
  cy.month_num,
  cy.revenue AS revenue_current_year,
  ly.revenue AS revenue_last_year,
  SAFE_DIVIDE(cy.revenue - ly.revenue, ly.revenue) * 100 AS yoy_change_pct
FROM
  monthly_data cy
LEFT JOIN
  monthly_data ly
  ON cy.month_num = ly.month_num
  AND cy.year = ly.year + 1
WHERE
  cy.year = EXTRACT(YEAR FROM CURRENT_DATE())
ORDER BY
  cy.month_num
```

## Looker Studioでの可視化

### パターン1: 2本の折れ線を重ねる

BigQueryのビューをLooker Studioに接続し、折れ線グラフを作成します。

1. ディメンション: `date`（日付）
2. 指標1: `revenue_current`（今年の売上）
3. 指標2: `revenue_previous`（前年の売上）

2つの指標が同じグラフに折れ線として描画されるため、今年と去年のトレンドを直感的に比較できます。

### パターン2: 棒グラフ＋折れ線の複合チャート

月別集計データを使って、以下の構成にすると見やすくなります。

- 棒グラフ: 今年の売上（左Y軸）
- 棒グラフ: 前年の売上（左Y軸、色を変える）
- 折れ線: 前年比変化率（右Y軸）

設定方法:

1. 「複合グラフ」を追加
2. ディメンション: `month_num`（月）
3. 指標（棒）: `revenue_current_year`, `revenue_last_year`
4. 指標（折れ線）: `yoy_change_pct`

### パターン3: スコアカードで前年比を大きく表示

経営者向けダッシュボードでは、KPIのスコアカードに前年比の増減を大きく表示すると効果的です。

BigQuery側で以下のような集計値を用意します。

```sql
SELECT
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END) AS revenue_ytd,
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END) AS revenue_ytd_ly,
  SAFE_DIVIDE(
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END)
    - SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END),
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END)
  ) * 100 AS ytd_yoy_pct
FROM monthly_data
WHERE month_num <= EXTRACT(MONTH FROM CURRENT_DATE())
```

Looker Studioのスコアカードで `ytd_yoy_pct` を表示し、条件付き書式で「プラスなら緑、マイナスなら赤」にすると一目で状況がわかります。

## 日付パラメータとの連携

Looker Studioの日付フィルタをBigQueryのクエリに反映させるには、カスタムクエリで日付パラメータを使います。

```sql
SELECT
  date,
  revenue_current,
  revenue_previous,
  revenue_yoy_pct
FROM
  `project.dataset.yoy_daily_view`
WHERE
  date BETWEEN @DS_START_DATE AND @DS_END_DATE
```

`@DS_START_DATE` と `@DS_END_DATE` は、Looker Studioの日付コントロールに連動するパラメータです。データソース設定で「日付パラメータを有効にする」にチェックを入れると使えます。

:::message
日付パラメータを使うと、BigQueryのスキャン範囲が日付フィルタに応じて動的に変わるため、コスト削減にもつながります。
:::

## 注意点

### うるう年の処理

2月29日が含まれる期間の比較では、前年にその日が存在しないためNULLになります。`COALESCE`で0埋めするか、週単位での比較に切り替えることで対処できます。

```sql
COALESCE(p.revenue_ly, 0) AS revenue_previous
```

### 事業開始初年度

前年データが存在しない期間は比較ができません。ダッシュボードに「前年データなし」と明示的に表示するか、前月比に切り替えるロジックを入れておくと親切です。

### 季節イベントのずれ

ブラックフライデーやお盆など、年によって日付がずれるイベントは単純な日付比較では正確に比較できません。「営業日ベース」や「イベント週ベース」での比較が必要になる場合は、SQLでカスタムカレンダーテーブルを用意して対応します。

## まとめ

前年同期比は、季節変動を排除して事業の成長を正しく評価するための基本指標です。

- **BigQuery側**: CTEとJOINで今年・前年のデータを横並びにする
- **Looker Studio側**: 複合チャートやスコアカードで視覚的に比較する
- **運用面**: 日付パラメータで期間を動的に変更できるようにする

一度ビューを作成してしまえば、毎月の定例レポートで前年比の確認が自動化されます。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
