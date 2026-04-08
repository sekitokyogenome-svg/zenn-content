---
title: "チャネル別ROASをBigQueryで集計してLooker Studioに可視化する"
emoji: "💰"
type: "tech"
topics: ["bigquery", "lookerstudio", "ec"]
published: true
---

## はじめに

「Google広告・Meta広告・LINE広告と複数チャネルに出稿しているが、結局どのチャネルが一番利益に貢献しているのかわからない」――EC運営で広告費を使っている方なら、一度はぶつかる壁ではないでしょうか。

GA4の管理画面でもチャネル別の売上は確認できますが、**広告費用との突合ができない**ため、ROAS（広告費用対効果）の正確な比較には限界があります。各媒体の管理画面を個別に見ても、アトリビューションの基準が異なるため横並びの比較になりません。

本記事では、GA4のBigQueryエクスポートデータと広告費データをSQLで結合し、チャネル別ROASを算出してLooker Studioで可視化する方法を解説します。

## ROASとは何か

ROAS（Return On Ad Spend）は、広告費用に対してどれだけの売上を得られたかを示す指標です。

```text
ROAS = 売上（Revenue） ÷ 広告費（Ad Spend） × 100（%）
```

例えば、10万円の広告費で50万円の売上が発生した場合、ROAS は 500% です。一般的に、ROAS 300%以上が損益分岐の目安とされますが、粗利率によって判断基準は変わります。

:::message
GA4の管理画面ではチャネル別の売上は確認できますが、広告費データは各媒体から別途取得する必要があります。そのため、GA4単体ではROASの算出ができません。BigQueryを使うことで、売上と広告費を同じテーブルに集約し、統一基準で比較できるようになります。
:::

## 前提：GA4のBigQueryエクスポート設定

この記事では、GA4のBigQueryエクスポートが有効になっていることを前提とします。まだ設定していない場合は、GA4管理画面の「BigQueryのリンク設定」から数クリックで連携できます。

エクスポートされたデータは `analytics_XXXXXXXXX.events_*` というテーブルに格納され、流入元の情報は `collected_traffic_source` フィールドに含まれています。

## Step 1：チャネル別売上をBigQueryで集計する

GA4のBigQueryエクスポートデータから、`collected_traffic_source` を使ってチャネル別の売上を集計します。`collected_traffic_source.manual_medium` と `manual_source` には、UTMパラメータで付与した流入元情報が格納されています。

```sql
-- チャネル別の売上集計
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
  ) AS revenue
FROM
  `project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND collected_traffic_source.manual_medium IS NOT NULL
GROUP BY
  month, medium, source
ORDER BY
  month, revenue DESC
```

:::message alert
`collected_traffic_source` はユーザーの初回流入時に記録された値です。セッション単位の流入元を使いたい場合は `session_traffic_source_last_click` を検討してください（GA4のBQスキーマバージョンによって利用可能かどうかが異なります）。
:::

## Step 2：広告費データを用意する

ROAS算出のためには、チャネルごとの広告費データが必要です。広告費データの取得方法はいくつかあります。

| 方法 | 難易度 | 説明 |
|------|--------|------|
| 手動CSV取込 | 低 | 各媒体の管理画面からCSVをダウンロードしてBQにロード |
| Google広告API連携 | 中 | Google Ads Data TransferでBQに自動連携 |
| 統合ツール利用 | 中 | Fivetran/Airbyte等で各媒体のデータを自動取得 |
| スプレッドシート連携 | 低 | Googleスプレッドシートに手入力 → BQ外部テーブル化 |

まずは手動CSVまたはスプレッドシート連携で始めるのが現実的です。以下のスキーマで広告費テーブルを作成します。

```sql
-- 広告費テーブルの作成
CREATE TABLE IF NOT EXISTS `project.dataset.ad_spend` (
  month STRING,        -- '2025-01' 形式
  medium STRING,       -- 'cpc', 'display', 'social' など
  source STRING,       -- 'google', 'meta', 'line' など
  spend INT64          -- 広告費（円）
);
```

Googleスプレッドシートを外部テーブルとして参照する場合は、BigQueryの「外部テーブルの作成」からスプレッドシートのURLを指定するだけで設定できます。

## Step 3：ROASをSQLで算出する

売上データと広告費データを結合し、チャネル別ROASを算出します。

```sql
-- チャネル別ROAS算出
WITH channel_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(
      IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
    ) AS revenue
  FROM
    `project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    month, medium, source
),

channel_spend AS (
  SELECT
    month,
    medium,
    source,
    spend
  FROM
    `project.dataset.ad_spend`
)

SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  s.spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source
ORDER BY
  r.month, roas_pct DESC
```

`SAFE_DIVIDE` を使うことで、広告費がゼロ（オーガニック流入など）の場合にゼロ除算エラーを回避しています。CPA（顧客獲得単価）もあわせて算出しておくと、後の分析で役立ちます。

## Step 4：マートテーブルに保存する

Looker Studioから参照するために、上記のクエリ結果をマートテーブルとして保存します。ビューまたはスケジュールドクエリで定期更新する構成がおすすめです。

```sql
-- マートビューとして作成
CREATE OR REPLACE VIEW `project.dataset_mart.mart_channel_roas` AS
WITH channel_revenue AS (
  -- （上記のchannel_revenue CTEと同じ内容）
  ...
),
channel_spend AS (
  SELECT month, medium, source, spend
  FROM `project.dataset.ad_spend`
)
SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  COALESCE(s.spend, 0) AS spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source;
```

:::message
Looker Studioからは生データのeventsテーブルを直接参照しないでください。データ量が多いためクエリコストが跳ね上がります。マートビューを挟むことで、コストを抑えつつ高速に表示できます。
:::

## Step 5：Looker Studioで可視化する

### データソースの接続

1. Looker Studio（https://lookerstudio.google.com）を開く
2. 「データソースを追加」→「BigQuery」を選択
3. プロジェクト → データセット → `mart_channel_roas` を選択
4. 「接続」をクリック

### ダッシュボード構成

ROASダッシュボードでは、以下のチャートを配置すると意思決定に使いやすくなります。

| チャート | 用途 | ディメンション | 指標 |
|----------|------|----------------|------|
| スコアカード | 全体ROAS・全体売上の概要 | なし | revenue, spend, roas_pct |
| 棒グラフ | チャネル別ROAS比較 | source | roas_pct |
| 積み上げ棒グラフ | チャネル別売上構成比 | month × source | revenue |
| 折れ線グラフ | ROAS推移の時系列変化 | month | roas_pct（sourceで分割） |
| テーブル | チャネル別詳細一覧 | medium, source | users, purchases, revenue, spend, roas_pct, cpa |

フィルタとして `month`（期間選択）と `medium`（チャネル種別の絞り込み）を追加しておくと、分析の柔軟性が上がります。

### 可視化のポイント

- ROAS 300%のラインを棒グラフに**参照線**として追加すると、損益分岐が一目でわかる
- CPAはスコアカードよりもテーブルに入れたほうが比較しやすい
- 月次推移の折れ線は、予算変更タイミングにアノテーションを入れると因果が見やすい

## Step 6：結果の読み方と予算判断

ROASダッシュボードが完成したら、以下の観点で分析を進めます。

**チャネル間の比較**
ROASが高いチャネルに予算を寄せるのが基本ですが、ボリューム（売上の絶対額）も重要です。ROAS 800%でも月1万円しか売上がないチャネルに予算を集中しても、事業インパクトは限定的です。

**時系列の変化**
ROASが急落したタイミングがあれば、クリエイティブの疲弊・競合の参入・季節要因などを疑います。逆にROASが改善したタイミングでは、その施策を他チャネルに横展開できないか検討します。

**CPAとの併用**
ROASだけでなくCPA（顧客獲得単価）もセットで見ることで、新規獲得効率とLTVのバランスを判断できます。

:::message
ROASは万能な指標ではありません。アトリビューションモデル（ラストクリック vs ファーストクリック等）によって数値が大きく変わることがあります。BigQueryであれば、アトリビューションの重み付けを自分でカスタマイズすることも可能です。
:::

## まとめ

本記事では、GA4のBigQueryエクスポートデータと広告費データを結合し、チャネル別ROASを算出してLooker Studioで可視化する方法を解説しました。

- `collected_traffic_source.manual_medium / manual_source` で流入チャネルを特定
- 広告費テーブルとJOINしてROAS・CPAを算出
- マートビューを経由してLooker Studioに接続
- ダッシュボードでチャネル間比較・時系列推移を可視化

GA4の管理画面だけでは見えなかった「どのチャネルに予算を寄せるべきか」という判断が、データに基づいてできるようになります。

---

「GA4×BigQueryの基盤構築からLooker Studioでの可視化まで、一括で対応してほしい」という方はお気軽にご相談ください。

https://coconala.com/services/419062
