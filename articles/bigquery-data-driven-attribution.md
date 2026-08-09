---
title: "BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する"
emoji: "🔀"
type: "tech"
topics: ["bigquery","googleads","googleanalytics","sql","advertising"]
published: false
---

## はじめに

「Google広告の費用対効果が本当に正しいのか、いまいち自信が持てない」と感じたことはないでしょうか。Google広告の管理画面では「ラストクリック」モデルが長らく標準でしたが、これは購入直前にクリックされた広告だけに全成果を帰属させる方法です。実際には、ユーザーが購入に至るまでにInstagramの投稿を見たり、自然検索で商品名を調べたり、リターゲティング広告をクリックしたりと、複数の接触があることがほとんどです。

そこで注目されるのが「データドリブンアトリビューション（DDA）」です。DDAは機械学習を用いて、コンバージョンに至ったユーザーとそうでないユーザーのタッチポイントの差異を分析し、各チャネルへ統計的な貢献度を割り当てます。Google Analytics 4（GA4）ではDDAがデフォルトのアトリビューションモデルとして採用されており、BigQueryへのエクスポートデータを活用することで、独自に貢献度を可視化・再計算することが可能です。

本記事では、GA4のBigQueryエクスポートデータを用いてコンバージョン経路を集計し、チャネルごとの貢献度をSQLで計算する方法を解説します。アトリビューション分析が初めての方でも概念から理解できるよう丁寧に説明しますので、ぜひ最後までお読みください。

---

## データドリブンアトリビューションとは

アトリビューション（Attribution）とは、「成果の帰属」を意味します。ECサイトで1件の購入が発生したとき、その貢献をどの広告・チャネルにどれだけ割り当てるかを決めるルールがアトリビューションモデルです。

代表的なモデルには以下のものがあります。

| モデル名 | 概要 |
|---|---|
| ラストクリック | 最後にクリックしたチャネルに100%帰属 |
| ファーストクリック | 最初にクリックしたチャネルに100%帰属 |
| 線形 | 全タッチポイントに均等に帰属 |
| データドリブン | 機械学習で統計的な貢献度を算出 |

データドリブンアトリビューションの最大の特徴は、「実際のコンバージョンデータから学習する」点にあります。コンバージョンしたユーザー群としなかったユーザー群のタッチポイントのパターンを比較し、どの経路の組み合わせがコンバージョンに貢献したかを確率的に推定します。

GA4では一定のコンバージョン数（おおよそ月間数百件以上）が溜まることでDDAが自動的に有効化されます。ただし、GA4の管理画面上ではモデルの詳細なロジックやデータは参照できません。BigQueryにエクスポートされた生データを使うことで、自社独自の視点で貢献度を再集計することができます。

---

## BigQueryでコンバージョン経路を抽出するSQL

GA4のBigQueryエクスポートでは、ユーザーの行動がイベント単位で記録されています。まずはセッションごとの流入元とコンバージョン（purchase）を紐づけて、コンバージョン経路を取得します。

以下のSQLでは、各ユーザーのセッションを時系列に並べ、そのセッションでの流入元チャネルを取得します。`ga_session_id` はイベントパラメータに格納されているため、`UNNEST(event_params)` 経由で取り出します。

```sql
-- コンバージョン経路の抽出（GA4 BigQueryエクスポート）
WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params から取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元は collected_traffic_source から参照
    collected_traffic_source.manual_source   AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

-- セッション単位に流入元を集約
session_source AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)  AS source,
    MAX(medium)  AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_base
  GROUP BY 1, 2
),

-- ユーザーごとにセッションを時系列で並べてコンバージョン経路を構築
conversion_path AS (
  SELECT
    user_pseudo_id,
    STRING_AGG(
      CONCAT(COALESCE(source, '(direct)'), ' / ', COALESCE(medium, '(none)')),
      ' > '
      ORDER BY session_ts
    ) AS path,
    MAX(is_converted) AS converted
  FROM session_source
  GROUP BY user_pseudo_id
)

SELECT
  path,
  COUNT(*)                                        AS total_users,
  SUM(converted)                                  AS conversions,
  ROUND(SUM(converted) / COUNT(*) * 100, 2)       AS conversion_rate_pct
FROM conversion_path
GROUP BY path
ORDER BY conversions DESC
LIMIT 30;
```

このクエリを実行すると、「google / cpc > (direct) / (none)」や「organic / google > email / newsletter」のような経路ごとのコンバージョン数が確認できます。どの経路がよく使われているかを把握することが、アトリビューション分析の第一歩です。

:::message
`your_project.analytics_XXXXXXX` の部分は、実際のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。BigQueryのデータセット名はGA4の管理画面「BigQueryのリンク」から確認できます。
:::

---

## チャネルごとの貢献度を線形モデルで計算する

経路が取得できたら、次はチャネルごとに貢献度を割り当てます。線形モデル（経路上の全タッチポイントに均等配分）はシンプルかつ解釈しやすく、DDAへの入門として適しています。

以下のSQLでは、経路内のタッチポイント数でコンバージョンを等分し、チャネル別に合計します。

```sql
-- 線形アトリビューションでチャネルごとの貢献度を集計
WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

session_agg AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)        AS source,
    MAX(medium)        AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_source
  GROUP BY 1, 2
),

-- コンバージョンしたユーザーの経路のみ対象
converted_users AS (
  SELECT user_pseudo_id
  FROM session_agg
  GROUP BY 1
  HAVING MAX(is_converted) = 1
),

-- ユーザーあたりのタッチポイント数を算出
user_touch AS (
  SELECT
    s.user_pseudo_id,
    s.ga_session_id,
    CONCAT(COALESCE(s.source,'(direct)'), ' / ', COALESCE(s.medium,'(none)')) AS channel,
    COUNT(*) OVER (PARTITION BY s.user_pseudo_id) AS touch_count
  FROM session_agg s
  INNER JOIN converted_users c USING (user_pseudo_id)
)

-- チャネルごとに線形配分の合計を集計
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*)                          AS total_touchpoints
FROM user_touch
GROUP BY channel
ORDER BY linear_attribution_score DESC;
```

`linear_attribution_score` が高いチャネルほど、コンバージョンに関与していたタッチポイントを多く担っていたことを意味します。Google広告（cpc）だけでなく、オーガニック検索やメールマガジンなどがどれほど貢献しているかを客観的に把握できます。

:::message
線形モデルはあくまで簡易的な貢献度の参考値です。より精度の高い分析にはShapley値などの計算も有効ですが、まずはこのSQLで全体のチャネル貢献度の傾向をつかむことをお勧めします。
:::

---

## 分析結果をLooker Studioで可視化する

BigQueryで集計したアトリビューションスコアは、Looker Studio（旧データポータル）と接続することで、グラフやダッシュボードとして視覚化できます。非エンジニアのメンバーとも共有しやすくなるため、社内報告やクライアントへの説明にも役立ちます。

Looker Studioとの接続手順は以下のとおりです。

```bash
# 事前準備：BigQueryクエリ結果をテーブルとして保存
# BigQueryコンソールで「クエリ結果を保存」>「BigQueryテーブル」を選択
# または以下のようなDDL構文でビューとして保存
```

```sql
-- 分析用ビューの作成例
CREATE OR REPLACE VIEW `your_project.analytics_XXXXXXX.v_linear_attribution` AS
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*) AS total_touchpoints
FROM (
  -- ※上記SQLのuser_touchサブクエリをここに展開
  SELECT 'placeholder' AS channel, 1 AS touch_count  -- 実際はuser_touchの内容を展開
) t
GROUP BY channel;
```

Looker Studioでは「データソースを追加」からBigQueryを選択し、作成したビューまたはテーブルを指定するだけで棒グラフや表を作成できます。チャネル別のアトリビューションスコアを棒グラフで、コンバージョン経路ランキングを表で示すと、広告施策の意思決定に活用しやすいレポートになります。

---

## まとめ

本記事では、GA4のBigQueryエクスポートデータを用いたデータドリブンアトリビューションの基本的な考え方とSQL実装を紹介しました。要点を整理します。

- **アトリビューションモデル**とは、コンバージョンの成果をどのチャネルにどれだけ帰属させるかのルールです。GA4のデフォルトはデータドリブンモデルです。
- **GA4のBigQueryエクスポート**を活用すれば、生データを自社の視点で集計・再計算できます。
- **`ga_session_id` は `UNNEST(event_params)` 経由**で取得し、流入元は **`collected_traffic_source.manual_source / manual_medium`** を参照します。
- **線形モデルSQLによる貢献度スコア**は、チャネルの相対的な重要度を把握する第一歩として有効です。
- **Looker Studioとの連携**で、分析結果を視覚化して社内外に共有しやすくなります。

ラストクリックだけで広告予算を判断していた場合、実際には複数のチャネルが連携してコンバージョンを支えていることに気づくケースも少なくありません。まずはBigQueryでコンバージョン経路を可視化することから始めてみてください。

## 関連記事

- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)
- [BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）](https://zenn.dev/web_benriya/articles/ga4-bigquery-bounce-rate-calculation)
- [GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する](https://zenn.dev/web_benriya/articles/ga4-bigquery-cac-by-channel)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
