# ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート

## はじめに

「先月のセールは売上が上がったけど、本当にセールのおかげなのか分からない」——そんな疑問を感じたことはないでしょうか。クーポン配布やタイムセールを実施するたびに売上数字は動くものの、その変化がセール施策によるものなのか、季節要因なのか、広告費の増加によるものなのかを切り分けるのは、感覚値だけでは困難です。

多くのEC担当者が「なんとなく効果があった気がする」という感想で次の施策に進んでしまいます。この状態が続くと、効果の薄い施策に予算を投入し続けたり、逆に効果の高い施策を見落としたりするリスクがあります。

GA4とBigQueryを組み合わせることで、セール期間の前後を定量的に比較し、「施策によってどの指標がどれだけ変化したか」を明確に示す分析が可能になります。本記事では、中小ECでも導入しやすいSQLテンプレートと分析の考え方を解説します。

## GA4×BigQueryでbefore/after比較を行う理由

GA4の標準レポートでも期間比較は可能ですが、カスタムの切り口での集計や、複数セグメントの同時比較には限界があります。BigQueryにエクスポートされたGA4のイベントデータを直接クエリすることで、以下のような柔軟な分析が実現します。

- **セール前・期間中・セール後の3期間を一括比較**できる
- **流入元（メルマガ・SNS広告・自然検索など）別**に効果を分解できる
- **商品カテゴリや購入回数（新規/リピート）**で絞り込んだ分析が可能
- 分析結果をLookerStudioに接続してダッシュボード化できる

GA4のBigQueryエクスポートを有効にしていない場合は、GA4の管理画面から「BigQueryのリンク設定」を行い、Googleクラウドプロジェクトと接続してください。エクスポートが開始されると、`analytics_XXXXXXXXX.events_YYYYMMDD`形式のテーブルにイベントデータが蓄積されていきます。

<!-- ここから有料 -->

## 分析に必要なデータ構造の理解

GA4のBigQueryエクスポートテーブルは、1行1イベントのフラットな構造です。セッションIDや流入元などの情報は、イベントパラメータのネスト構造（RECORD型）として格納されているため、直接カラム名では参照できません。

**重要な取得パターン**を以下にまとめます。

```sql
-- ga_session_id の取得（UNNEST経由が必須）
SELECT
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS session_id

-- 流入元の取得（collected_traffic_source を使用）
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
```

`ga_session_id`は`event_params`をUNNESTして取得する必要があります。また、流入元の情報は`collected_traffic_source.manual_medium`および`collected_traffic_source.manual_source`カラムから取得します。これはGA4の仕様上、セッション単位の流入元情報が格納されている場所であるため、この形式を使うことをお勧めします。

> `collected_traffic_source`はGA4のBigQueryエクスポートで比較的新しく追加されたカラム群です。古いエクスポートデータが存在する場合、期間によってはNULLになることがあります。その場合は`traffic_source.medium`を代替として使用してください。

## SQLテンプレート：セール前後の主要KPIを比較する

以下のSQLは、セール前・セール中・セール後の3期間について、セッション数・購入件数・購入率・売上合計を比較するクエリです。日付の範囲は実際のセール日程に合わせて書き換えてください。

```sql
WITH
-- 期間ラベルを付与するベーステーブル
base AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250601' AND '20250614' THEN 'before'
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      WHEN event_date BETWEEN '20250622' AND '20250705' THEN 'after'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250705'
),

-- セッション単位に集約
sessions AS (
  SELECT
    period,
    session_id,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM base
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

-- 期間別KPIの集計
SELECT
  period,
  COUNT(DISTINCT session_id)                        AS sessions,
  SUM(purchase_count)                               AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS conversion_rate_pct,
  ROUND(SUM(revenue), 0)                            AS total_revenue
FROM sessions
GROUP BY period
ORDER BY
  CASE period WHEN 'before' THEN 1 WHEN 'during' THEN 2 WHEN 'after' THEN 3 END
;
```

このクエリを実行すると、期間ごとのセッション数・購入件数・CVR・売上が横並びで確認できます。セール期間中のCVRがbefore期と比較してどのように変化したかを数値で把握することが、次の施策判断の基礎となります。

> `your_project.analytics_XXXXXXXXX`の部分は、BigQueryのデータセット名に置き換えてください。GA4の管理画面の「BigQueryのリンク」設定画面でプロジェクトIDとデータセットIDを確認できます。

## 流入元別の効果測定：どのチャネルがセール集客に貢献したか

セール全体の効果を把握した後は、流入元別に分解して「どのチャネルが購入に最も貢献したか」を確認します。メルマガ経由の購入が多い場合と、SNS広告経由の購入が多い場合では、次回の施策の打ち手が変わってきます。

```sql
WITH
session_source AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250615' AND '20250621'
),

sessions_agg AS (
  SELECT
    period,
    session_id,
    -- セッション最初の流入元を使用（first_valueで代替も可）
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM session_source
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

SELECT
  COALESCE(medium, '(none)')  AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id)   AS sessions,
  SUM(purchase_count)          AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS cvr_pct,
  ROUND(SUM(revenue), 0)       AS revenue
FROM sessions_agg
GROUP BY medium, source
ORDER BY revenue DESC
LIMIT 20
;
```

このクエリの結果をもとに、たとえば「メルマガ（email/newsletter）のCVRが他チャネルと比べて高い」という事実が確認できれば、次回のセールではメルマガの配信タイミングや対象リストの拡充を優先する、といった判断ができます。

## LookerStudioでダッシュボード化して継続的に活用する

一度分析したクエリはBigQueryのビューとして保存しておくと、LookerStudioから毎回クエリを書かずにデータを参照できるようになります。

LookerStudioでの接続手順は以下の通りです。

```
1. LookerStudio（https://lookerstudio.google.com/）を開く
2. 「データを追加」→「BigQuery」を選択
3. プロジェクト・データセット・テーブル（またはビュー）を選択して接続
4. ディメンション（period、medium など）とメトリクス（sessions、revenue など）を設定
5. 棒グラフや表ウィジェットでbefore/after比較を可視化
```

特に有効なのは、`period`をディメンションとしてグループ棒グラフに設定し、CVRと売上を同時に表示するレイアウトです。視覚的にseasonalityとセール効果を分離して報告資料に使える形に仕上げられます。

> LookerStudioからBigQueryへのクエリは課金対象になります。大規模なデータを参照する場合はBigQueryのビューやマテリアライズドビューを活用し、クエリのスキャン量を抑えることをお勧めします。

## まとめ

ECのセール施策効果を客観的に評価するためのbefore/after分析について、GA4×BigQueryを使ったアプローチを解説しました。要点を整理します。

- **GA4の標準レポートでは難しい多軸比較**が、BigQueryのSQLで柔軟に実現できる
- `ga_session_id`は`UNNEST(event_params)`経由で取得し、流入元は`collected_traffic_source.manual_medium/manual_source`を参照する
- **3期間（before/during/after）の比較**により、セール効果と期間終了後の反動も把握できる
- 流入元別の分解により、**次回施策のチャネル配分判断**が数値ベースで行える
- BIgQueryビュー＋LookerStudioを組み合わせることで、**毎回のセール後に再利用できるテンプレート**として定着させられる

まず手元のデータで「1つ前のセール期間」を対象にクエリを実行してみることから始めてみてください。数字が揃うと、次のセール企画の解像度が上がります。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
