---
title: "ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する"
emoji: "🎁"
type: "idea"
topics: ["bigquery","googleanalytics","ec","sql","datanalysis"]
published: false
---

## はじめに

「毎年バレンタイン前後に急に在庫が切れる」「クリスマスギフトの需要が読めず、売れ残りを大量に抱えてしまった」——そうした経験をお持ちのECサイト運営者は少なくないのではないでしょうか。

ギフト需要には明確な季節性があります。母の日、父の日、敬老の日、クリスマス、バレンタイン、ホワイトデー……これらのイベントに合わせて購買行動が大きく変動することは直感的にわかっていても、「どのくらい前から需要が立ち上がり、ピークはいつで、どれくらいの規模になるか」を数値で把握できているケースは多くありません。

GA4とBigQueryを組み合わせることで、過去の購買データや行動データを詳細に分析し、ギフト需要の時系列パターンを可視化することができます。本記事では、GA4のBigQueryエクスポートデータを活用して、ギフト需要の季節性を分析し、在庫計画に役立てるための具体的な手順をご紹介します。SQLのコードも掲載しますが、非エンジニアの方でもクエリの意図を理解できるよう、丁寧に解説していきます。

## GA4×BigQueryでギフト需要分析を始める前の準備

### GA4とBigQueryの連携設定

まず前提として、GA4のデータをBigQueryにエクスポートする設定が必要です。GA4の管理画面から「BigQueryのリンク設定」を行うことで、毎日自動的にイベントデータがBigQueryへ書き出されるようになります。エクスポートが始まると、`events_YYYYMMDD` という形式のテーブルにデータが蓄積されていきます。

ギフト需要の季節性を分析するには、少なくとも過去1〜2年分のデータが必要です。連携を始めてすぐには十分なデータが溜まっていないため、できるだけ早めに設定しておくことを推奨します。

### ギフト購入を識別するためのイベント設計

GA4でギフト需要を正確に分析するには、「ギフト用購入」と「自分用購入」を区別できるデータが理想的です。たとえば、ギフトラッピング選択時にカスタムイベントを送信したり、注文フォームの「ギフトとして贈る」チェックボックスの選択状態をパラメータとして送信したりする設計が有効です。

ただし、そのようなデータがない場合でも、イベント時期に合わせた売上推移や、ギフト関連キーワードで検索して流入したユーザーの行動を分析することで、需要のパターンを把握することは十分可能です。

## 月別・週別の売上推移をBigQueryで時系列分析する

ギフト需要の季節性を把握するための最初のステップは、月別・週別の売上件数と売上金額を時系列で集計することです。以下のSQLクエリは、GA4のBigQueryエクスポートデータから`purchase`イベントを集計し、週単位の売上推移を取得します。

```sql
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  week_start
ORDER BY
  week_start
```

このクエリを実行すると、週ごとの注文件数と売上金額が得られます。`your_project.analytics_XXXXXXXXX` の部分はご自身のプロジェクトIDとプロパティIDに置き換えてください。

出力データをLooker Studio（旧データポータル）に接続すると、折れ線グラフで視覚的に確認できます。グラフを見れば、クリスマス前の11月下旬〜12月中旬にかけて売上が大きく跳ね上がるといった季節性のピークが一目瞭然になります。

## ギフトイベント前の「需要立ち上がり」タイミングを特定する

在庫計画において重要なのは「ピーク時の需要量」だけでなく、「いつから需要が増え始めるか」という立ち上がりのタイミングです。仕入れや製造には一定のリードタイムがかかるため、需要の立ち上がりを早期に把握することが計画の精度を高めます。

以下のクエリでは、特定のギフトイベント（例：クリスマス）に向けた需要の立ち上がりを、直近2年分のデータで比較します。

```sql
WITH daily_orders AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS order_date,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS order_year,
    FORMAT_DATE('%m-%d', PARSE_DATE('%Y%m%d', event_date)) AS month_day,
    COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20231101' AND '20241231'
    AND event_name = 'purchase'
  GROUP BY
    order_date, order_year, month_day
)
SELECT
  month_day,
  MAX(CASE WHEN order_year = 2023 THEN order_count END) AS orders_2023,
  MAX(CASE WHEN order_year = 2024 THEN order_count END) AS orders_2024
FROM
  daily_orders
WHERE
  month_day BETWEEN '11-01' AND '12-25'
ORDER BY
  month_day
```

このクエリで11月1日〜12月25日の日別注文数を年度比較できます。2年分のデータを重ねて見ることで、需要が例年どのタイミングから増加し始めるかのパターンが見えてきます。

:::message
需要の立ち上がりを特定できたら、そのタイミングの2〜3週間前を「仕入れ確定期限」として社内ルール化しておくと、在庫不足のリスクを大幅に低減できます。
:::

## 流入元別にギフト購入者の行動を分析する

ギフト需要を捉えるうえで、「どのチャネルからギフト購入者が来ているか」を把握することも重要です。SNS広告経由のユーザーはギフト需要に敏感な傾向があったり、自然検索からのユーザーは早めに情報収集を始めることが多かったりと、流入元によって購買行動のパターンが異なる場合があります。

以下のクエリでは、`collected_traffic_source` を用いて流入元（メディア・ソース）別の購入件数を集計します。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  medium,
  source,
  month
ORDER BY
  month,
  order_count DESC
```

このクエリを実行することで、「12月はinstagram/cpcからの購入が急増する」「11月はgoogle/organicからのギフト購入が多い」といった傾向が把握できます。

こうしたデータをもとに、ギフトシーズンに合わせた広告予算の配分や、SEOコンテンツの強化時期を検討することもできます。在庫計画と販促計画を連動させることで、需要の最大化と機会損失の防止が期待できます。

## 分析結果を在庫計画に落とし込むフレームワーク

時系列分析から得られたデータを在庫計画に活用するための実践的なフレームワークをご紹介します。

### ステップ1：ベースラインと季節指数の算出

平常月（1〜2月、6月など需要が安定している時期）の平均週次売上をベースラインとして設定します。次に、各イベント周辺の需要をベースラインで割ることで「季節指数」を算出します。

たとえば、平常月の平均週次売上が100件で、クリスマス前週が280件だった場合、季節指数は2.8となります。翌年の在庫計画では、ベースライン予測値に季節指数を掛けて需要予測を行います。

### ステップ2：安全在庫の設定

過去データから需要のばらつき（標準偏差）を計算し、安全在庫の水準を設定します。需要予測が外れることを前提に、一定のバッファを持った在庫計画が健全です。

```python
import pandas as pd
import numpy as np

# BigQueryから取得したデータをデータフレームに格納した想定
# df は week_start, order_count の列を持つ

christmas_weeks = df[df['week_start'].between('2023-11-27', '2023-12-25')]
mean_demand = christmas_weeks['order_count'].mean()
std_demand = christmas_weeks['order_count'].std()

# 95%信頼水準の安全在庫（正規分布を仮定）
safety_stock = 1.65 * std_demand
reorder_point = mean_demand + safety_stock

print(f"週平均需要: {mean_demand:.1f} 件")
print(f"安全在庫: {safety_stock:.1f} 件")
print(f"発注点: {reorder_point:.1f} 件")
```

### ステップ3：Looker StudioでダッシュボードとしてPDL化

分析結果はBigQueryのビューとして保存し、Looker Studioのダッシュボードで常時モニタリングできる状態にしておくと、運営チーム全体でデータを共有しやすくなります。特に「今年の需要立ち上がりが昨年比でどうか」をリアルタイムに確認できる体制を整えておくと、仕入れタイミングの判断材料として活用できます。

:::message
Looker StudioとBigQueryを接続する際は、クエリの実行頻度に注意が必要です。データの更新頻度に合わせてキャッシュ設定を適切に行うことで、BigQueryの課金コストを抑えることができます。
:::

## まとめ

本記事では、GA4×BigQueryを活用してECサイトのギフト需要を時系列分析し、在庫計画に反映するための手順を解説しました。要点を整理します。

- **週別・月別の売上推移をSQLで集計**することで、ギフトイベントの季節性パターンを数値で把握できる
- **年度比較のクエリ**により、需要の立ち上がりタイミングを特定し、仕入れスケジュールの基準となる
- **流入元別の分析**（`collected_traffic_source`の活用）により、どのチャネルがギフト購入に貢献しているかを把握できる
- **季節指数と安全在庫の算出**により、勘と経験に頼らないデータドリブンな在庫計画が実現できる

次のアクションとして、まずはGA4とBigQueryの連携が完了しているかを確認してみてください。まだ連携していない場合は、今すぐ設定を始めることで来シーズンの分析に間に合わせることができます。連携済みの方は、本記事のSQLクエリをそのまま試してみることで、自社の季節性パターンを把握する第一歩を踏み出せます。

データ分析に慣れていない方でも、一度ダッシュボードを整備してしまえば、毎年のギフトシーズン前に振り返るだけで在庫計画の精度を高められます。ぜひ本記事を参考に、データ活用の取り組みを進めてみてください。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
