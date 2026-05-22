---
title: "BigQueryでGA4のサンプリングを回避して正確な数値を出す"
emoji: "🎯"
type: "tech"
topics: ["bigquery", "googleanalytics", "dataanalytics"]
published: true
---

## はじめに

GA4の探索レポートで分析していたら、レポート上部に「サンプリングされています」という警告が出たことはありませんか？

GA4のUIでは、一定のデータ量を超えると自動でサンプリングがかかります。つまり、全データではなく一部のデータから推計された数値が表示されます。これは意思決定の精度を下げる大きな要因です。

この記事では、GA4のサンプリング問題の実態と、BigQueryエクスポートを使って100%のデータで分析する方法を解説します。

---

## GA4 UIでサンプリングが発生する条件

GA4の探索レポート（Explorations）では、以下の条件でサンプリングが発生します。

- **対象期間のイベント数が1,000万件を超える場合**（無料版GA4）
- 複数ディメンション・セグメントを組み合わせた複雑なレポート
- カスタムファネルやパス分析など計算負荷の高いレポート

標準レポートはサンプリングされませんが、カスタマイズ性が低く詳細な分析には向きません。

:::message
GA4 360（有料版）ではサンプリングの閾値が引き上げられますが、完全にゼロにはなりません。BigQueryエクスポートが唯一の「サンプリングなし」の手段です。
:::

---

## サンプリングされた数値がどれだけズレるか

実際にサンプリングされた場合、どの程度のズレが生じるのでしょうか。

GA4 UIの探索レポートでは、サンプリング率に応じて数値が推計されます。たとえば50%サンプリングの場合、実際のセッション数が10,000でも、UIでは9,500〜10,500のような幅のある値が表示されます。

問題が深刻になるのは、セグメント別の分析です。

```text
-- サンプリングによるズレの例（架空データ）
チャネル          | GA4 UI（サンプリング有） | BigQuery（100%）
-----------------|------------------------|----------------
organic_search   | 4,200                  | 4,587
direct           | 3,100                  | 2,834
paid_search      | 1,800                  | 1,923
referral         |   900                  |   656
```

全体の合計は近くても、チャネル別に見るとズレが大きくなります。特にデータ量の少ないセグメントほど誤差が拡大します。

---

## BigQueryなら100%のデータで分析できる

GA4のBigQueryエクスポートを有効にすると、全イベントが `events_YYYYMMDD` テーブルに格納されます。ここにはサンプリングの概念がありません。

以下は、GA4 UIで同等のことをやるとサンプリングされがちな「日別×チャネル別セッション数」のクエリです。

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY event_date, medium
ORDER BY event_date, sessions DESC
```

このクエリはBigQuery上で全データをスキャンするため、結果にサンプリングの影響は一切ありません。

---

## GA4 UIとBigQueryの数値を比較してみる

GA4のBigQueryデータを分析し始めると、GA4 UIの数値と微妙に合わないことがあります。これはサンプリング以外にも原因があります。

| 差異の原因 | 説明 |
|-----------|------|
| サンプリング | UIで自動適用。BigQueryでは発生しない |
| データのしきい値 | UIではプライバシー保護のため少数データを非表示にする |
| セッションの定義差 | UIはGoogle独自のセッション処理。BigQueryでは自分で定義 |
| タイムゾーン | GA4 UIはプロパティのタイムゾーン。BigQueryはUTC |

タイムゾーンの補正はBigQuery側で行えます。

```sql
-- UTCからJSTに変換して日付を取得
SELECT
  FORMAT_DATE('%Y%m%d',
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
  ) AS event_date_jst,
  COUNT(*) AS event_count
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date_jst
ORDER BY event_date_jst
```

:::message
`event_date` カラムはGA4プロパティのタイムゾーンで記録されていますが、`event_timestamp` はUTCのマイクロ秒です。時間帯をまたぐ分析では `event_timestamp` をJSTに変換して使うのが安全です。
:::

---

## BigQueryでスキャン量を抑えるコツ

BigQueryは従量課金なので、100%データで分析できる一方、コストにも注意が必要です。

### _TABLE_SUFFIXで期間を絞る

```sql
-- 良い例：必要な期間だけスキャン
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'

-- 悪い例：全期間スキャン（コスト大）
FROM `beeracle.analytics_263425816.events_*`
```

### 必要なカラムだけSELECTする

```sql
-- 良い例：必要なカラムだけ取得
SELECT event_date, event_name, user_pseudo_id
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX = '20260330'

-- 悪い例：全カラム取得（コスト大）
SELECT *
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX = '20260330'
```

BigQueryはカラム指向ストレージのため、`SELECT *` にすると全カラム分の課金が発生します。

---

## 実務での使い分け

GA4 UIとBigQueryは、用途に応じて使い分けるのが現実的です。

| 用途 | 推奨 |
|------|------|
| 日々のPV・セッション数の確認 | GA4 UI標準レポート |
| 簡易的なファネル確認 | GA4 UI探索レポート |
| チャネル別×デバイス別の詳細分析 | BigQuery |
| コホート・LTV分析 | BigQuery |
| 広告データとの結合分析 | BigQuery |
| 社内レポート・ダッシュボード | BigQuery + Looker Studio |

GA4 UIは「ざっくり把握」、BigQueryは「正確に深掘り」と覚えておくとよいでしょう。

---

## まとめ

GA4のUIではデータ量が増えるとサンプリングが避けられず、セグメント別の分析で誤差が拡大します。BigQueryエクスポートを使えば100%のデータで分析でき、サンプリングの影響を受けません。正確なデータに基づいた意思決定のためには、BigQueryへの連携が有効な選択肢です。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
