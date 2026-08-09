---
title: "Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法"
emoji: "🔍"
type: "tech"
topics: ["bigquery","advertising","googleads","sql","dataengineering"]
published: false
---

## はじめに

「Google広告はGoogle広告のレポート、Yahoo!広告はYahoo!広告の管理画面、それぞれ別々に確認している」という状況に心当たりはないでしょうか。複数の広告媒体を運用している場合、媒体ごとに管理画面を行き来しながら数字をエクセルにコピーして比較する、という作業が毎月の定番になっている担当者の方は少なくないかと思います。

この方法の問題は、作業コストが高いだけでなく、媒体を横断したトータルの費用対効果がつかみにくい点にあります。Google広告で獲得したユーザーとYahoo!広告で獲得したユーザーを同じ軸で比較できなければ、予算配分の意思決定も勘に頼らざるを得ません。

本記事では、Yahoo!広告のレポートデータをBigQueryに取り込み、Google広告データやGA4（Googleアナリティクス4）のデータと統合して分析する手順を解説します。エンジニアでなくても取り組めるよう、ツールの選定からSQLの実例まで順を追って説明します。

---

## Yahoo!広告データをBigQueryに取り込む3つの方法

Yahoo!広告はGoogle広告と異なり、BigQueryへの公式ネイティブ連携機能を提供していません。そのため、データを取り込むにはいくつかのアプローチから選ぶ必要があります。

**方法1: 手動CSVエクスポート＋BigQueryへのアップロード**

Yahoo!広告の管理画面からレポートをCSVでダウンロードし、BigQueryのコンソールからテーブルにアップロードする方法です。無料で始められ、操作も比較的シンプルです。ただし、毎日手動で実施する必要があるため、運用負荷が高く、自動化には向きません。検証や小規模な利用に適しています。

**方法2: Yahoo!広告APIを使ったカスタムスクリプト**

Yahoo!広告が公開しているReporting APIを使って、Pythonスクリプトでデータを定期取得しBigQueryに書き込む方法です。Google Cloud FunctionsやCloud Schedulerと組み合わせることで、完全な自動化が可能になります。開発コストはかかりますが、柔軟性が高く、中長期的には運用コストを抑えられます。

**方法3: ETLサービス（Fivetran・troccoなど）の活用**

Fivetranやtroccoといったデータ統合SaaSを使えば、ノーコードまたはローコードでYahoo!広告からBigQueryへのデータパイプラインを構築できます。troccoは日本語対応が充実しており、Yahoo!広告コネクタも用意されています。月額費用は発生しますが、エンジニアリソースが限られている場合の現実的な選択肢です。

:::message
どの方法を選ぶ場合も、Yahoo!広告の認証情報（クライアントID・シークレット）が必要です。APIを使う場合はYahoo!デベロッパーネットワークへのアプリ登録も事前に行っておきましょう。
:::

---

## BigQueryにおける統合テーブルの設計方針

Yahoo!広告とGoogle広告のデータをBigQueryに格納したあと、そのままでは2つのテーブルを横断した集計ができません。統合分析を行うには、媒体をまたいで比較できる「共通スキーマ」のテーブルを作成することが重要です。

以下のような統合ビュー（またはテーブル）を作成しておくと、あとの集計が格段に楽になります。

```sql
-- Google広告とYahoo!広告の統合ビュー例
CREATE OR REPLACE VIEW `your_project.ads_dataset.unified_ads_stats` AS

-- Google広告データ
SELECT
  'google' AS media_source,
  DATE(segments.date) AS report_date,
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 2) AS cost_jpy,
  metrics.conversions AS conversions
FROM
  `your_project.google_ads.p_ads_CampaignBasicStats_*`

UNION ALL

-- Yahoo!広告データ（取り込み済みのテーブルを参照）
SELECT
  'yahoo' AS media_source,
  report_date,
  campaign_name,
  impressions,
  clicks,
  cost AS cost_jpy,
  conversions
FROM
  `your_project.yahoo_ads.campaign_report`
;
```

このビューを用意することで、後述の集計クエリがシンプルに書けるようになります。カラム名は自社のテーブル構造に合わせて適宜調整してください。

:::message
Google広告のBigQueryエクスポートはGoogle Ads Data Transferで設定できます。まだ設定していない場合は、BigQueryのコンソール左メニュー「データ転送」から「Google広告」を選択して有効化してください。
:::

---

## 媒体横断の集計クエリ実例

統合ビューが完成したら、媒体ごとのパフォーマンス比較が1本のSQLで行えるようになります。以下はよく使われる集計パターンです。

**パターン1: 媒体別の月次コスト・CPA比較**

```sql
SELECT
  media_source,
  FORMAT_DATE('%Y-%m', report_date) AS year_month,
  SUM(cost_jpy) AS total_cost,
  SUM(conversions) AS total_conversions,
  ROUND(
    SAFE_DIVIDE(SUM(cost_jpy), SUM(conversions)),
    0
  ) AS cpa
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) AND CURRENT_DATE()
GROUP BY
  media_source, year_month
ORDER BY
  year_month, media_source
;
```

**パターン2: キャンペーン別のCTR・CVR比較**

```sql
SELECT
  media_source,
  campaign_name,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(conversions) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(conversions), SUM(clicks)) * 100, 2) AS cvr_pct
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  media_source, campaign_name
ORDER BY
  media_source, cvr_pct DESC
;
```

これらのクエリをLooker Studioのカスタムクエリとして登録しておくと、毎月自動でレポートが更新されるダッシュボードを作成できます。

---

## GA4データと組み合わせてユーザー行動を深掘りする

広告の費用対効果を正確に把握するには、広告管理画面のコンバージョン数だけでなく、サイト内の行動データと組み合わせることが有効です。GA4のBigQueryエクスポートを活用すると、広告経由のユーザーがサイト上でどのような行動をとったかを分析できます。

以下の例では、Yahoo!広告経由で流入したセッションの平均エンゲージメント時間を計算しています。

```sql
-- GA4データからYahoo!広告経由セッションを抽出する例
SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  ROUND(
    AVG(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'engagement_time_msec') / 1000.0
    ),
    1
  ) AS avg_engagement_sec
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source LIKE '%yahoo%'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date
;
```

`collected_traffic_source.manual_medium` と `collected_traffic_source.manual_source` を使うことで、UTMパラメータで付与した流入元を正確に絞り込めます。Yahoo!広告のURLには `utm_source=yahoo` `utm_medium=cpc` のようにパラメータを付与しておくことが前提です。

:::message
GA4のBigQueryエクスポートでは `ga_session_id` はイベントのトップレベルフィールドとして直接参照できません。`UNNEST(event_params)` 経由で取得する必要がある点に注意してください。
:::

広告管理画面のコンバージョンデータとGA4のエンゲージメントデータを組み合わせると、「コンバージョン数は多いが直帰率も高い媒体」「コンバージョンは少ないが回遊率が高く将来的な見込みがある媒体」といった、より立体的な媒体評価が可能になります。

---

## まとめ

本記事のポイントを整理します。

- **Yahoo!広告のBigQuery取り込み**には、手動CSV・APIスクリプト・ETLサービスの3つのアプローチがある。自動化と運用コストのバランスで選択する
- **統合ビューの作成**により、GoogleとYahooの2媒体を同じSQLで横断集計できるようになる
- **媒体横断の集計クエリ**でCPA・CTR・CVRを比較し、予算配分の判断材料にする
- **GA4のBigQueryエクスポート**と組み合わせることで、広告費だけでなくサイト内行動まで含めた総合的な効果測定が実現する

まず取り組みやすいのは、既存のGA4 BigQueryエクスポートと手動でアップロードしたYahoo!広告CSVを統合ビューで結合するところからです。小さくスタートして、慣れてきたら自動化を検討するという順序が現実的です。データが1か所に集まると、広告運用の判断スピードが変わります。ぜひ一歩踏み出してみてください。

## 関連記事

- [BigQueryでGA4データをdbtで管理する入門](https://zenn.dev/web_benriya/articles/bigquery-ga4-dbt-management-intro)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [BigQuery × Looker Studioで前年同期比グラフを作る方法](https://zenn.dev/web_benriya/articles/bigquery-looker-studio-yoy-comparison-chart)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
