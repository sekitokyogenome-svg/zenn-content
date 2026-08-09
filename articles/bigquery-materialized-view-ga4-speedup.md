---
title: "BigQueryのマテリアライズドビューでGA4集計クエリを高速化した"
emoji: "⚡"
type: "tech"
topics: ["bigquery","sql","googleanalytics","googlecloud","cost"]
published: false
---

## はじめに

GA4のデータをBigQueryにエクスポートして分析している方の中には、「クエリを実行するたびに数十秒〜数分待たされる」「毎朝のレポート更新が遅くて業務の流れが止まる」といった経験をされている方も多いのではないでしょうか。

特に、1日あたりのイベント数が数十万件を超えてくると、過去1ヶ月分のセッション集計や流入元別のCV数集計は、生テーブルに対してクエリを走らせるたびに相当な時間とコストがかかります。Looker StudioからBigQueryに接続している場合、ダッシュボードを開くたびにクエリが走るため、チーム全体の待ち時間も無視できません。

この記事では、BigQueryの**マテリアライズドビュー（Materialized View）**という機能を使って、GA4の集計クエリを高速化した実例をご紹介します。エンジニアでなくても概念が理解できるよう、設定の背景と手順を丁寧に解説します。

---

## マテリアライズドビューとは何か

通常のビュー（View）は「クエリの定義だけを保存したもの」です。ビューを参照するたびに、その背後にある生テーブルへのクエリが毎回実行されます。

一方、**マテリアライズドビュー**は「クエリ結果そのものをキャッシュとして保存したもの」です。元テーブルにデータが追加されると、BigQueryが差分を自動的に反映してくれます。参照時には事前に計算済みの結果を返すため、クエリ時間とスキャン量が大幅に削減されます。

:::message
マテリアライズドビューは、BigQueryがバックグラウンドで定期的に更新します。ストレージコストはかかりますが、クエリのスキャン量（＝課金対象バイト数）が減るため、アクセス頻度の高いレポートほどコスト削減効果が出やすくなります。
:::

---

## GA4のBigQueryエクスポートテーブル構造を理解する

マテリアライズドビューを設計する前に、GA4のエクスポートテーブルの特徴を把握しておく必要があります。

GA4のBigQueryエクスポートでは、`events_YYYYMMDD` という日付別パーティションテーブルが生成されます。1行が1イベントに対応しており、セッションIDやトラフィックソースはネストされた構造（RECORD型）で格納されています。

たとえば、セッションIDを取得するには `event_params` 配列をUNNESTして取り出す必要があります。

```sql
-- ga_session_id の取得方法（UNNEST経由）
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
```

流入元については、`collected_traffic_source` フィールドの `manual_medium` と `manual_source` を使用します。

```sql
-- 流入元の取得方法
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= '20250601'
  AND event_name = 'session_start'
```

このような構造に対してそのままクエリを走らせると、毎回フルスキャンが発生します。ここにマテリアライズドビューを活用する余地があります。

---

## マテリアライズドビューの作成手順

以下は、セッションごとの流入元を日次で集計するマテリアライズドビューの例です。Looker StudioやスプレッドシートでCV数・セッション数を参照する際のベーステーブルとして活用できます。

```sql
CREATE MATERIALIZED VIEW `your_project.your_dataset.mv_ga4_session_summary`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 60
)
AS
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNTIF(event_name = 'purchase') AS purchase_count,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'value')
      ELSE 0
    END
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date,
  source,
  medium,
  user_pseudo_id,
  ga_session_id
```

:::message
`refresh_interval_minutes` は更新頻度の設定です。リアルタイム性が不要なレポートであれば、`360`（6時間）や `1440`（1日1回）に設定するとストレージ更新コストを抑えられます。
:::

作成したマテリアライズドビューは通常のテーブルと同様にクエリできます。

```sql
-- マテリアライズドビューへのクエリ例
SELECT
  event_date,
  source,
  medium,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(purchase_count) AS purchases,
  SUM(total_revenue) AS revenue
FROM
  `your_project.your_dataset.mv_ga4_session_summary`
WHERE
  event_date BETWEEN '2025-06-01' AND '2025-06-30'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date DESC
```

---

## 実際の効果：クエリ時間とスキャン量の変化

実際に導入した際の比較です（中小ECサイト・月間イベント数約300万件の場合）。

| 項目 | 生テーブルへの直接クエリ | マテリアライズドビュー経由 |
|---|---|---|
| クエリ実行時間 | 約45〜90秒 | 約3〜8秒 |
| スキャンデータ量 | 約8GB / クエリ | 約200MB / クエリ |
| 月間クエリコスト（目安） | 約$8〜$15 | 約$0.5〜$1 |

クエリ時間の短縮はもちろんですが、スキャン量の削減によるコストメリットも見逃せません。Looker Studioのダッシュボードは複数のユーザーがアクセスするため、1日に何十回もクエリが走る環境ではその差が積み重なっていきます。

:::message
マテリアライズドビューには「集計関数の種類」や「JOINの使用」など一部制限があります。複雑なロジックはビュー側ではなく、マテリアライズドビューを参照するクエリ側で処理するのが現実的な設計です。
:::

---

## 運用上の注意点

マテリアライズドビューを導入する際に気をつけたい点を整理します。

**1. ワイルドカードテーブルとの相性**

GA4のエクスポートは `events_*` 形式のワイルドカードテーブルです。マテリアライズドビューはワイルドカード参照に一部制限があるため、`_TABLE_SUFFIX` フィルターを使った固定期間（過去90日など）での定義が安定して動作します。

**2. スキーマ変更への対応**

GA4のエクスポートスキーマはGoogleのアップデートで変更されることがあります。マテリアライズドビューの定義に影響する変更があった場合は、ビューを再作成する必要があります。定期的に動作確認することをお勧めします。

**3. ストレージコストの試算**

マテリアライズドビュー自体のストレージコストは、BigQueryの通常テーブルと同じ単価です（東京リージョンで約$0.023/GB/月）。集計後のデータ量は生テーブルより大幅に小さいため、多くのケースでトータルコストは下がります。

---

## まとめ

BigQueryのマテリアライズドビューは、GA4のような大規模イベントデータを扱うレポート環境において、クエリ速度とコストの両面で有効な手段です。

この記事でご紹介したポイントを整理します。

- `event_params` 内のフィールド（`ga_session_id` など）はUNNESTを経由して取得する
- 流入元の分析には `collected_traffic_source.manual_medium / manual_source` を使用する
- マテリアライズドビューは事前集計済みの結果を保存するため、参照時のスキャン量を大幅に削減できる
- `refresh_interval_minutes` でリフレッシュ頻度を調整し、コストとリアルタイム性のバランスを取る
- ワイルドカードテーブルを使う際は集計対象期間を固定する設計が安定する

次のステップとしては、作成したマテリアライズドビューをLooker Studioのデータソースとして設定し、ダッシュボードの表示速度を実際に比較してみることをお勧めします。体感できる変化として現れやすい改善のひとつです。

## 関連記事

- [BigQueryでGA4データのコスト管理・クエリ最適化入門](https://zenn.dev/web_benriya/articles/bigquery-ga4-cost-query-optimization)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
