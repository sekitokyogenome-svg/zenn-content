---
title: "Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する"
emoji: "🛍️"
type: "tech"
topics: ["bigquery","googleanalytics","ec","advertising","sql"]
published: false
---

## はじめに

自社ECサイトとAmazonの両方で商品を販売している場合、「どのチャネルに広告費を集中させるべきか」という判断に迷った経験はないでしょうか。Amazonの管理画面では広告のROASやクリック数は確認できますが、自社サイト側のGA4データと横断して比較することが難しく、全体像が把握しにくいという課題があります。

GA4では標準のレポートで流入チャネルごとのセッション数や購入数を確認できますが、Amazon広告のデータは別のプラットフォームに分断されています。その結果、「今月はAmazonに広告費を多く使ったが、自社ECへの流入が減ったのかどうか」「どのチャネルが本当にROIが高いのか」といった問いに、数字でもって答えることができない状態になりがちです。

この記事では、Amazon広告レポートとGA4のBigQueryエクスポートデータを統合し、チャネルミックスを俯瞰できるようにするための具体的な手順とSQLをご紹介します。エンジニア出身でなくても理解できるよう、考え方とコードの両面から丁寧に解説しますので、ぜひ参考にしてみてください。

## Amazon広告レポートをBigQueryに取り込む

Amazon広告のデータは、Amazonの広告コンソールからCSVレポートとしてダウンロードするか、Amazon Ads APIを通じて取得できます。手軽に始めたい場合は、スポンサープロダクト広告やスポンサーブランド広告のキャンペーンレポートをCSVでダウンロードし、BigQueryにアップロードする方法が現実的です。

BigQueryへのCSVアップロードは、GCPコンソールから「データセットを作成」→「テーブルを作成」→「アップロード」の順に進めるだけで完了します。テーブル名はわかりやすく `amazon_ads_campaign_report` などとしておくとよいでしょう。

定期的に取り込む場合は、Google Cloud StorageにCSVを置いてスケジュールされたクエリで読み込む方法や、Cloud Functionsで自動化する方法も選択肢に入ります。ただし、まずは手動アップロードで検証してから自動化に進むことをお勧めします。

:::message
Amazon広告のCSVレポートには日付・キャンペーン名・インプレッション数・クリック数・広告費・売上などが含まれています。BigQueryにアップロードする際は、列のデータ型（特に日付と数値）に注意して設定してください。
:::

## GA4のBigQueryエクスポートデータでチャネル別売上を集計する

GA4はBigQueryエクスポートを有効にすることで、イベント単位の詳細なデータをBigQueryに蓄積できます。以下のSQLは、GA4エクスポートデータから流入チャネル別の購入件数と売上を集計する例です。

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (
        SELECT value.double_value
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'value'
      )
      ELSE 0
    END
  ) AS revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date,
  medium,
  source
ORDER BY
  event_date,
  revenue DESC
```

このクエリのポイントは `collected_traffic_source.manual_medium` および `manual_source` を使って流入元を判定している点です。UTMパラメータが正しく設定されていれば、`cpc`（有料検索）、`email`、`organic` など、チャネルごとに分類されたデータが取得できます。

また、`ga_session_id` はイベントパラメータにネストされているため、`UNNEST(event_params)` を経由して取得する必要があります。直接 `ga_session_id` と書いても参照できないことに注意してください。

## Amazon広告データとGA4データをBigQueryで結合する

次に、Amazon広告レポートとGA4データを日付で結合し、チャネルミックスを一覧で比較できるテーブルを作成します。Amazon側は広告費と売上（Amazon内）、GA4側は自社EC売上を並べることで、全体の投資対効果が見えてきます。

```sql
WITH amazon_summary AS (
  SELECT
    report_date,
    SUM(spend) AS amazon_spend,
    SUM(sales_14d) AS amazon_revenue,
    SUM(clicks) AS amazon_clicks,
    SUM(impressions) AS amazon_impressions
  FROM
    `your_project.your_dataset.amazon_ads_campaign_report`
  GROUP BY
    report_date
),

ga4_paid AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    SUM(
      CASE
        WHEN event_name = 'purchase'
        THEN (
          SELECT value.double_value
          FROM UNNEST(event_params) AS ep
          WHERE ep.key = 'value'
        )
        ELSE 0
      END
    ) AS own_ec_revenue,
    COUNTIF(event_name = 'purchase') AS own_ec_purchases
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND collected_traffic_source.manual_medium IN ('cpc', 'paid', 'ppc')
  GROUP BY
    event_date
)

SELECT
  COALESCE(a.report_date, g.event_date) AS date,
  COALESCE(a.amazon_spend, 0) AS amazon_spend,
  COALESCE(a.amazon_revenue, 0) AS amazon_revenue,
  COALESCE(g.own_ec_revenue, 0) AS own_ec_revenue,
  COALESCE(a.amazon_revenue, 0) + COALESCE(g.own_ec_revenue, 0) AS total_revenue
FROM
  amazon_summary a
FULL OUTER JOIN
  ga4_paid g
ON
  a.report_date = g.event_date
ORDER BY
  date
```

このSQLを実行すると、日別にAmazonと自社ECの売上と広告費が並んだテーブルが生成されます。FULL OUTER JOINを使うことで、どちらかのデータしかない日も漏れなく表示できます。

## Looker StudioでチャネルミックスダッシュボードをBigQueryと接続する

BigQueryで集計したデータをLooker Studio（旧データポータル）と接続すると、視覚的なダッシュボードを無料で作成できます。手順は以下のとおりです。

1. Looker Studioを開き、「データを追加」からBigQueryコネクタを選択する
2. 先ほど作成したクエリ結果をビューとして保存し、そのビューを参照する
3. 折れ線グラフで日別の `total_revenue`、棒グラフで `amazon_spend` などを配置する
4. フィルタで期間を絞り込めるようにスライダーを追加する

ダッシュボードができあがると、「今月前半はAmazonの広告費が高い割に自社ECへの流入が伸びていない」「特定の週に自社ECのCPC流入からの売上が跳ね上がっている」といったパターンが視覚的に掴めるようになります。定性的な感覚で判断していた部分を、数字で裏付けられる状態が整います。

:::message
Looker StudioからBigQueryへのアクセスには、GCPプロジェクトのBigQuery閲覧権限が必要です。個人アカウントで運用している場合は、IAMロールとして「BigQuery データ閲覧者」を付与してください。
:::

## チャネルミックスを最適化するための判断軸

データが揃ったら、次は判断軸を設定します。チャネルミックスの最適化では「どのチャネルが費用対効果が高いか」を定期的に評価することが重要です。以下の指標を参考にしてください。

- **ROAS（広告費用対効果）**: `revenue ÷ spend` で算出。Amazonと自社ECそれぞれで計算し比較する
- **CPA（顧客獲得単価）**: `spend ÷ purchases` で算出。新規顧客と既存顧客で分けて見るとさらに精度が上がる
- **チャネル別の月次トレンド**: 前月比で増減率を可視化し、施策との相関を確認する

重要なのは、単月の数字だけで判断せず、3か月程度のトレンドで見ることです。Amazonの広告は季節性の影響を受けやすく、特定月だけを見ると誤った結論に至る場合があります。また、Amazonでブランドを知った顧客が後日自社ECで購入するという「チャネル横断の購買行動」は今のデータ構造では捉えきれないため、補助的な情報として顧客インタビューやアンケートも活用すると判断精度が上がります。

## まとめ

今回の記事では、Amazon広告レポートとGA4のBigQueryエクスポートデータを統合し、チャネルミックスを俯瞰するための方法を解説しました。要点を整理すると以下のとおりです。

- Amazon広告のCSVレポートをBigQueryにアップロードすることでSQLで扱えるようになる
- GA4の流入元は `collected_traffic_source.manual_medium` と `manual_source` で取得する
- `ga_session_id` は `UNNEST(event_params)` 経由で取得する
- FULL OUTER JOINでAmazonと自社ECのデータを日付結合すると全体像が把握できる
- Looker Studioと接続することでダッシュボード化でき、意思決定に使いやすくなる

次のアクションとしては、まずGA4のBigQueryエクスポートが有効になっているか確認することをお勧めします。有効でない場合はGA4の管理画面から設定できます。その後、Amazon広告レポートを1か月分ダウンロードしてBigQueryにアップロードし、本記事のSQLを試してみてください。小さく始めて、データが揃ったら徐々にダッシュボードを拡充していく進め方が現実的です。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
