---
title: "GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googleanalytics", "googleads"]
published: false
---

## はじめに

Google広告を運用していると「キーワード別のCVR（コンバージョン率）をもっと正確に見たい」という場面が出てきます。Google広告の管理画面でもCVRは確認できますが、GA4側のデータと突き合わせると数値が合わないことがあります。

自分の経験だと、広告管理画面のCVRとGA4のCVRで15〜20%程度のズレがあったケースもありました。これはアトリビューションモデルの違いやクリックとセッションのカウント方法の差異によるものです。

本記事では、GA4のBigQueryエクスポートデータとgclidを使って、キーワード単位でCVRを算出するSQLと、GA4標準UIとの違いについて解説します。

---

## GA4標準UIの限界

GA4の標準レポートでGoogle広告のパフォーマンスを見る場合、以下のような制約があります。

- **キーワード単位の深掘りが難しい**: 「Google / cpc」までは見えるが、キーワード別のCVR比較は探索レポートでの設定が必要
- **サンプリングの影響**: データ量が多い場合、探索レポートにサンプリングがかかり、正確な数値が出ない
- **セッションスコープとイベントスコープの混在**: ファネル分析の際にスコープが異なるデータを混ぜてしまいやすい

BigQueryに出力された生データであれば、サンプリングなし・フルデータでキーワード単位の分析ができます。

---

## gclidの仕組みと取得方法

gclid（Google Click Identifier）は、Google広告のクリックごとに付与される一意のIDです。GA4のBigQueryエクスポートデータでは、`page_location` パラメータのURLにgclidが含まれた状態で記録されます。

gclidをキーワード情報に紐づけるには、Google広告の管理画面またはGoogle Ads APIから「gclid × キーワード」のマッピングテーブルを作成する必要があります。

```sql
-- gclidマッピングテーブルの想定スキーマ
-- このテーブルはGoogle Ads APIまたはBigQueryデータ転送で取得する
CREATE TABLE IF NOT EXISTS `project.dataset.ads_click_keyword` (
  gclid STRING,
  campaign_name STRING,
  ad_group_name STRING,
  keyword STRING,
  match_type STRING,
  click_date DATE
);
```

:::message
Google Ads APIからgclidとキーワードの対応データを取得するには、Developer Tokenが必要です。BigQueryのデータ転送サービスを使ってGoogle広告データを自動連携する方法もあります。
:::

---

## GA4データからgclidを抽出するSQL

まず、GA4のBigQueryデータからgclidを抽出します。

```sql
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_date
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
gclid_extracted AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(page_location, r'gclid=([^&]+)') AS gclid,
    event_name,
    event_date
  FROM ga4_sessions
  WHERE medium = 'cpc'
    AND source = 'google'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  gclid,
  event_date
FROM gclid_extracted
WHERE gclid IS NOT NULL;
```

`REGEXP_EXTRACT` でURLパラメータからgclidを取り出しています。`collected_traffic_source.manual_medium` が `cpc` のセッションに絞ることで、Google広告経由のクリックだけを対象にしています。

---

## キーワード別CVRを算出するSQL

gclidを介して、GA4のセッションデータとGoogle広告のキーワードデータを結合し、キーワード別のCVRを算出します。

```sql
WITH ga4_gclid AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'gclid=([^&]+)'
    ) AS gclid,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'google'
),
sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id,
    gclid
  FROM ga4_gclid
  WHERE gclid IS NOT NULL
),
conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM ga4_gclid
  WHERE event_name = 'purchase'
),
keyword_sessions AS (
  SELECT
    ak.keyword,
    ak.match_type,
    ak.campaign_name,
    s.user_pseudo_id,
    s.ga_session_id,
    CASE WHEN c.ga_session_id IS NOT NULL THEN 1 ELSE 0 END AS is_cv
  FROM sessions s
  JOIN `project.dataset.ads_click_keyword` ak
    ON s.gclid = ak.gclid
  LEFT JOIN conversions c
    ON s.user_pseudo_id = c.user_pseudo_id
    AND s.ga_session_id = c.ga_session_id
)
SELECT
  keyword,
  match_type,
  campaign_name,
  COUNT(*) AS sessions,
  SUM(is_cv) AS conversions,
  ROUND(SUM(is_cv) / COUNT(*) * 100, 2) AS cvr
FROM keyword_sessions
GROUP BY keyword, match_type, campaign_name
HAVING sessions >= 5
ORDER BY sessions DESC;
```

---

## GA4 UIとBigQueryの数値比較

同じ期間・同じ条件で、GA4のUIとBigQueryの数値を比較した例です（某EC案件）。

| キーワード | GA4 UI CVR | BigQuery CVR | 差分 |
|-----------|-----------|-------------|------|
| ブランド名 完全一致 | 4.8% | 5.2% | +0.4pt |
| 商品カテゴリ 部分一致 | 1.2% | 0.9% | -0.3pt |
| 競合ブランド名 | 0.5% | 0.3% | -0.2pt |

差分が生じる主な理由は以下の3つです。

1. **アトリビューションモデルの違い**: Google広告のデフォルトはデータドリブン、GA4の標準レポートはクロスチャネルのデータドリブン
2. **コンバージョンの集計タイミング**: 広告管理画面はクリック日基準、GA4はコンバージョン発生日基準
3. **サンプリング**: GA4の探索レポートでは大量データにサンプリングがかかる場合がある

BigQueryを使えばサンプリングの問題は解消されるため、「GA4のどのセッションが実際にCVに至ったか」を正確に追えます。

---

## 実務での活用ポイント

### キーワードの入札調整に使う

CVRが高くCPCが低いキーワードは入札を引き上げ、CVRが低くCPCが高いキーワードは除外候補にする。当たり前のことですが、正確なCVRデータがないと判断を誤ります。

### マッチタイプ別の比較

同じキーワードでも、完全一致・フレーズ一致・部分一致でCVRは大きく変わります。BigQueryで集計すれば、マッチタイプごとの実績を並べて比較できます。

### 曜日・時間帯の掛け合わせ

キーワード×曜日×時間帯のCVRをBigQueryで算出し、入札スケジュールの調整に活用する方法もあります。GA4のUIでは難しい多次元の分析がBigQueryの強みです。

---

## まとめ

GA4×BigQueryでキーワード別CVRを分析する最大のメリットは、「サンプリングなし・生データベースの正確な数値が出せること」です。広告費の配分判断は、正確な数値があってはじめて精度が上がります。

自分としては、広告管理画面の数値だけで判断するのは少しリスクがあると感じています。GA4のBigQueryデータと突き合わせることで、より信頼性の高い意思決定ができるようになるはずです。

GA4×BigQueryでの広告分析、皆さんはどこまで踏み込めていますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
