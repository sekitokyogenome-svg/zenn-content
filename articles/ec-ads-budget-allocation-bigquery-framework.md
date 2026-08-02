---
title: "EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク"
emoji: "💰"
type: "idea"
topics: ["bigquery","advertising","ec","googleads","sql"]
published: false
---

## はじめに

「今月の広告予算、どのチャネルにどれだけ割り振ればいいのか…」——毎月この判断に頭を悩ませているEC事業者の方は多いのではないでしょうか。Google広告、Meta広告、LINEアフィリエイト、SEO経由のオーガニックと、流入チャネルが多様化した現代において、「なんとなく昨年並みで」「費用対効果が高そうだから」という感覚的な予算配分はリスクを高めます。

BigQueryにはGA4のイベントデータが蓄積されており、過去の流入チャネル別の購買行動データが眠っています。これを活用すれば、チャネルごとのコンバージョン率・セッション単価・平均注文額などを定量的に把握し、来期の予算配分に根拠を持たせることができます。

本記事では、非エンジニアの方でも理解しやすいよう、BigQueryを使った広告予算配分の最適化フレームワークをステップごとに解説します。SQLクエリのサンプルもあわせて掲載していますので、ご自身のデータで試してみてください。

---

## チャネル別のパフォーマンスをBigQueryで可視化する

まず取り組むべきは、過去データを使ったチャネル別パフォーマンスの可視化です。GA4のBigQueryエクスポートテーブルには、流入元情報がイベントごとに記録されています。`collected_traffic_source.manual_medium` と `collected_traffic_source.manual_source` を使うことで、UTMパラメータ付きのキャンペーン流入を正確に分類できます。

以下のクエリは、過去90日間の流入元別セッション数・購入イベント数・購入完了率を集計するものです。

```sql
WITH session_base AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    session_id,
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'session_start') AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM session_base
  GROUP BY session_id
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id) AS total_sessions,
  SUM(purchases) AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchases), COUNT(DISTINCT session_id)) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY medium, source
ORDER BY total_purchases DESC
LIMIT 20;
```

このクエリを実行すると、「cpc / google」「organic / google」「email / newsletter」など、チャネル別のCV数とCVRが一覧で確認できます。まずはこのデータをGoogleスプレッドシートやLooker Studioに貼り付けて、視覚的に把握するところから始めましょう。

---

## 売上貢献額ベースで予算配分の優先順位をつける

セッション数やCV数だけで予算判断を行うのは危険です。購入単価が低いチャネルへ投資を集中させても、売上全体は伸びにくいケースがあります。そこで重要になるのが「チャネルごとの売上貢献額」です。

以下のクエリでは、購入イベント（`purchase`）に紐づく収益額をチャネル別に集計します。

```sql
WITH purchase_events AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value') AS revenue
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'purchase'
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 0) AS total_revenue,
  ROUND(AVG(revenue), 0) AS avg_order_value
FROM purchase_events
GROUP BY medium, source
ORDER BY total_revenue DESC;
```

このクエリで得られる「チャネル別の売上合計・平均注文額」は、予算配分の優先順位づけに直結します。たとえばCVRが低くても平均注文額が高いチャネルは、丁寧に育てる価値があります。逆に、件数は多くても単価が低いチャネルへの過剰投資は見直しの対象になります。

:::message
平均注文額（AOV）が高いチャネルは、広告費が多少かさんでもROASが見合うケースがあります。チャネル評価は「件数」だけでなく「金額」もセットで見ることが大切です。
:::

---

## 月別トレンドから季節変動と広告効果の相関を読む

EC事業においては、季節変動が売上に大きく影響します。クリスマス商戦・母の日・年末年始など、時期によって有効なチャネルが変化することがあります。過去データの月別トレンドを確認することで、「この時期はどのチャネルに集中すべきか」という判断材料が得られます。

```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  COALESCE(collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(*) AS purchase_count,
  ROUND(
    SUM(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
    ), 0
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
GROUP BY month, medium
ORDER BY month ASC, total_revenue DESC;
```

このクエリを過去12カ月分で実行し、Looker Studioで折れ線グラフ化すると、「cpc（リスティング広告）は年末に売上貢献が高まる」「organic（SEO）は特定の月に安定して伸びる」といった傾向が視覚的に読み取れます。これを翌年の予算計画に反映させることで、時期に応じた柔軟な予算シフトが可能になります。

:::message
月別トレンドを見る際は、前年同月との比較も合わせて行うと、季節変動なのか広告施策の影響なのかを切り分けやすくなります。
:::

---

## 予算配分フレームワークの考え方：スコアリングで優先順位を数値化する

BigQueryで取得したデータをもとに、各チャネルをスコアリングして予算配分の優先順位を決めるフレームワークを紹介します。以下の4指標を使い、それぞれ5段階で評価します。

| 指標 | 内容 | 重み |
|------|------|------|
| CVR（購入率） | セッションあたりの購入割合 | 30% |
| AOV（平均注文額） | 1件あたりの購入金額 | 25% |
| 売上貢献額 | 期間中の総売上 | 30% |
| 季節安定性 | 月別変動の少なさ | 15% |

これらを組み合わせた総合スコア（100点満点）の高いチャネルから予算を厚くする、という考え方です。スコアリングの計算自体はスプレッドシートで十分対応できます。BigQueryからエクスポートしたCSVをもとに、各チャネルの相対値を0〜5点で評価し、重み付き合計を出すだけです。

この手法のメリットは、担当者や経営者が直感だけで判断することなく、データに基づいた合意形成を社内で行えることです。「なぜこのチャネルに多く投資するのか」を数字で説明できると、予算承認の場でも説得力が増します。

---

## まとめ

本記事では、BigQueryとGA4のエクスポートデータを活用して、EC広告予算の配分を最適化するフレームワークを紹介しました。要点を整理します。

- **チャネル別パフォーマンスの可視化**: セッション数・CV数・CVRをBigQueryで集計し、まず現状を把握する
- **売上貢献額での優先順位づけ**: 件数だけでなく売上金額・平均注文額も含めてチャネルを評価する
- **月別トレンドの活用**: 過去12カ月の推移から季節変動を読み取り、予算シフトのタイミングを計画する
- **スコアリングによる合意形成**: 複数指標を重み付けしてチャネルをスコア化し、客観的な根拠を持って予算配分を決定する

次のアクションとしては、まずBigQueryでチャネル別パフォーマンスを集計するクエリを実行し、現状のデータを可視化することから始めてみてください。データの全体像が見えてくると、どこに改善余地があるかが具体的に見えてきます。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
