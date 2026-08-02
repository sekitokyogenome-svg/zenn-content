---
title: "P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法"
emoji: "🎯"
type: "tech"
topics: ["bigquery","googleads","sql","advertising","ec"]
published: false
---

## はじめに

P-MAXキャンペーン（Performance Max）を運用していて、「どのアセットが成果に繋がっているのか」「どのチャネルに広告費が集中しているのか」が把握しにくいと感じていませんか？

Googleが提供する管理画面のレポートはシンプルでわかりやすい反面、自社ECの売上データと照合したり、特定の商品ページへの流入を詳細に掘り下げようとすると、どうしても情報量の壁にぶつかります。

そこで活用したいのが **BigQuery** です。GA4のデータをBigQueryにエクスポートすることで、SQLを使って柔軟な分析が可能になります。本記事では、P-MAXキャンペーンの配信実績をBigQueryで詳細に分析する方法を、サンプルクエリとあわせて解説します。専門的なエンジニアスキルがなくてもクエリをコピー＆カスタマイズして使えるよう、丁寧に説明していきます。

---

## P-MAXキャンペーンとBigQueryを組み合わせるメリット

Google広告の管理画面では、P-MAXキャンペーンの詳細なブレイクダウンが制限されています。たとえば、アセットグループがどのチャネル（YouTube・ディスプレイ・検索・Gmailなど）でどれだけ配信されたかを商品SKU単位で掘り下げることは、標準レポートだけでは容易ではありません。

BigQueryにGA4データをエクスポートすると、以下のような分析が可能になります。

- ランディングページ別のセッション数・CV数の把握
- P-MAX経由のユーザーとオーガニック流入ユーザーの行動比較
- 特定期間のキャンペーン別エンゲージメント率の推移
- 購入までのイベントパスの可視化

広告費の最適化は中小EC事業者にとって重要な課題です。BigQueryを活用することで、管理画面だけでは得られない粒度のインサイトを引き出すことができます。

---

## 事前準備：GA4とBigQueryの連携設定

BigQueryでGA4データを分析するためには、まずGA4プロパティとBigQueryを連携させる必要があります。

### 手順の概要

1. Google Cloud Projectを作成し、BigQuery APIを有効化する
2. GA4管理画面 → [管理] → [BigQueryのリンク設定] から連携を設定する
3. データのエクスポート頻度を「毎日」または「ストリーミング」に設定する
4. 連携後、BigQueryに `events_YYYYMMDD` 形式のテーブルが生成される

:::message
BigQueryには毎月10GBのストレージと1TBのクエリ処理が無料枠として用意されています。中小規模のECサイトであれば、この無料枠の範囲内に収まるケースも少なくありません。まずは費用を気にせず試してみることをお勧めします。
:::

連携が完了すると、`your_project.analytics_XXXXXXXXX.events_*` というテーブルにアクセスできるようになります。`XXXXXXXXX` はGA4のプロパティIDです。このテーブルを起点に、以降のSQLクエリを実行していきます。

---

## SQLでP-MAX流入のランディングページを分析する

P-MAXキャンペーンは、Googleの自動タグ設定（オートタグ）を経由して流入を記録します。GA4では `collected_traffic_source` フィールドにソース・メディア情報が格納されており、`manual_source` が `google`、`manual_medium` が `cpc` となっているデータがGoogle広告経由のセッションに該当します。

以下のクエリは、Google/CPC経由のセッションについて、ランディングページ別のセッション数とCV数を集計します。

```sql
SELECT
  event_date,
  collected_traffic_source.manual_source   AS source,
  collected_traffic_source.manual_medium   AS medium,
  (SELECT ep.value.string_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'page_location')         AS landing_page,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  )                                         AS sessions,
  COUNTIF(event_name = 'purchase')          AS conversions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  AND collected_traffic_source.manual_source = 'google'
  AND collected_traffic_source.manual_medium = 'cpc'
GROUP BY
  event_date, source, medium, landing_page
ORDER BY
  sessions DESC
LIMIT 50
```

:::message
`ga_session_id` はイベントパラメータの中に格納されているため、`UNNEST(event_params)` を経由して取り出す必要があります。`event_params.ga_session_id` のような直接参照はできないため、ご注意ください。
:::

このクエリを実行することで、「どのランディングページにP-MAX経由のセッションが集中しているか」「そのページでのCVがどの程度発生しているか」を一覧で把握できます。CVが少ないページにセッションが集まっている場合は、ページの内容やオファーの見直しを検討する材料になります。

---

## エンゲージメント率でセッション品質を評価する

セッション数が多くても、ユーザーがすぐに離脱してしまっていては広告費が有効に使われているとは言えません。次のクエリでは、エンゲージドセッションの割合を計算し、P-MAX流入のセッション品質を評価します。

GA4では `session_engaged` パラメータが `1` の場合に「エンゲージドセッション」として定義されます。

```sql
WITH session_data AS (
  SELECT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')       AS session_id,
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'session_engaged')     AS engaged,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
)

SELECT
  source,
  medium,
  COUNT(DISTINCT session_id)                                        AS total_sessions,
  COUNTIF(engaged = '1')                                            AS engaged_sessions,
  ROUND(
    COUNTIF(engaged = '1') / COUNT(DISTINCT session_id) * 100, 1
  )                                                                 AS engagement_rate_pct
FROM session_data
GROUP BY source, medium
ORDER BY total_sessions DESC
```

エンゲージメント率が著しく低い場合は、配信しているアセット（テキスト・画像・動画）とランディングページの内容にミスマッチが生じている可能性があります。アセットグループごとの改善施策を検討するきっかけになるでしょう。

---

## Google広告データとの掛け合わせでCPAを算出する

より踏み込んだ費用対効果の分析をする際には、Google広告のデータをBigQueryに取り込むことも有効です。「BigQuery Data Transfer Service」を利用することで、キャンペーン・アセットグループ単位のインプレッション数・クリック数・費用データをBigQueryに転送できます。

GA4のセッションデータとGoogle広告の費用データを結合することで、自前のCPA（獲得単価）計算が可能になります。

```sql
-- Google広告データとGA4データを日付・キャンペーンで結合するイメージ
-- ※ Data Transfer のテーブル名・スキーマは環境によって異なります
SELECT
  ads.campaign_name,
  ROUND(ads.cost_micros / 1000000, 0)              AS cost_jpy,
  ga.conversions,
  ROUND(
    (ads.cost_micros / 1000000) / NULLIF(ga.conversions, 0), 0
  )                                                AS cpa_jpy
FROM (
  SELECT
    campaign_name,
    SUM(cost_micros) AS cost_micros
  FROM `your_project.google_ads_transfer.p_Campaign_XXXXXXXXX`
  WHERE _PARTITIONDATE = '2024-07-31'
  GROUP BY campaign_name
) AS ads
LEFT JOIN (
  SELECT
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS conversions
  FROM `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX = '20240731'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY source
) AS ga
ON TRUE  -- キャンペーン名でのJOINはUTM設定が必要
```

:::message
Google広告のData Transfer Serviceの設定はGoogle Cloud ConsoleのBigQueryメニューから行います。P-MAXキャンペーンを他のキャンペーンと区別するには、キャンペーン名にわかりやすい識別子を含めておくか、UTMパラメータを適切に設定しておくことが分析精度の向上に繋がります。
:::

---

## まとめ

P-MAXキャンペーンは強力な自動最適化機能を備えている一方、管理画面だけでは詳細な分析が難しい面もあります。BigQueryとGA4データを組み合わせることで、次のようなインサイトを引き出せます。

| 分析テーマ | 主要な確認指標 |
|---|---|
| ランディングページ別パフォーマンス | セッション数・CV数 |
| セッション品質の評価 | エンゲージメント率 |
| 費用対効果の計算 | CPA・ROAS |

**次のアクション**として、以下のステップから始めることをお勧めします。

1. GA4とBigQueryの連携が未設定の場合は、まず設定を完了させる
2. 本記事のサンプルクエリをコピーし、プロジェクトID・プロパティIDを差し替えて実行してみる
3. 分析結果をLooker Studioのダッシュボードに可視化し、チームで定期的に共有できる仕組みを作る

一度データパイプラインを整えてしまえば、毎週・毎月のレポーティングも大幅に効率化できます。P-MAXの「ブラックボックス」感を少しずつ解消しながら、費用対効果の高い広告運用に役立てていただけますと幸いです。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
