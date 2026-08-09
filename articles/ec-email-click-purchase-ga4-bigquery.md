---
title: "ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する"
emoji: "📧"
type: "tech"
topics: ["bigquery","googleanalytics","ec","sql","advertising"]
published: false
---

## はじめに

メールマガジンを定期的に配信しているECサイトで、「開封率は高いのに売上に結びついていない」「どのセグメントへの配信が効いているのかわからない」と感じたことはないでしょうか。メール配信ツールのレポート画面で確認できるのは、クリック数やCTRまでが大半です。そこから先――実際にサイトを訪問し、商品を購入したかどうか――はGA4や受注データと組み合わせなければ把握できません。

GA4には、BigQueryへのデータエクスポート機能があります。これを活用すると、メルマガ経由のセッションと購入イベントを紐づけ、顧客セグメントごとの購入率や購入金額を詳細に分析できるようになります。特定商品への訴求が有効なセグメント、配信頻度を上げると効果が下がる層など、施策の判断材料となる数値を取り出せます。

本記事では、GA4のBigQueryエクスポートデータを使って「メルマガクリック→セッション→購入」の一連の流れをSQLで追跡する方法を解説します。BigQueryの操作経験が浅い方でも理解しやすいよう、クエリの意図を丁寧に説明しながら進めます。

---

## GA4のBigQueryエクスポートデータ構造を理解する

分析を始める前に、GA4がBigQueryへ書き出すテーブル構造の基本を押さえておきましょう。

GA4のBigQueryエクスポートでは、1日1テーブル（`events_YYYYMMDD`）の形式でデータが蓄積されます。1行が1イベントに対応し、イベントのパラメータは `event_params` という繰り返しフィールド（RECORD型の配列）に格納されています。

よく参照する主要フィールドを以下に示します。

| フィールド名 | 内容 |
|---|---|
| `event_name` | イベント名（`page_view`, `purchase` など） |
| `event_params` | イベントパラメータの配列（UNNEST必須） |
| `user_pseudo_id` | ユーザーを識別する匿名ID |
| `collected_traffic_source.manual_medium` | URLパラメータのutm_medium |
| `collected_traffic_source.manual_source` | URLパラメータのutm_source |

:::message
`ga_session_id` はトップレベルのフィールドとして存在しません。`event_params` の中にキー名 `ga_session_id` で格納されているため、`UNNEST` を使って取り出す必要があります。後述のSQLでその方法を確認してください。
:::

---

## メルマガ経由セッションを抽出するSQL

まず、UTMパラメータを使ってメルマガ経由のセッションを特定します。メール配信ツールのリンクには、あらかじめ `utm_medium=email` などのパラメータを付与しておくことが前提です。

以下のクエリは、指定期間内のメルマガ経由セッションと、そのセッション内で発生した `purchase` イベントを紐づけます。

```sql
-- メルマガ経由セッションと購入イベントの紐づけ
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params をUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS utm_medium,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    event_timestamp
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

-- セッション単位で最初のイベントと購入有無を集計
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    MIN(event_timestamp) AS session_start_ts
  FROM email_sessions
  GROUP BY
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign
)

SELECT
  utm_campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS total_sessions,
  COUNTIF(purchase_count > 0) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(COUNTIF(purchase_count > 0), COUNT(*)) * 100, 2
  ) AS conversion_rate_pct
FROM session_summary
GROUP BY utm_campaign
ORDER BY conversion_rate_pct DESC;
```

`your_project.analytics_XXXXXXXX` の部分は、実際のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。`_TABLE_SUFFIX` で期間を絞ることでスキャン量を抑えられます。

---

## セグメント別の購入金額を集計するSQL

コンバージョン率だけでなく、購入金額（revenue）をセグメント別に把握することで、費用対効果の高い配信先が見えてきます。GA4の `purchase` イベントには `value`（購入金額）と `currency` パラメータが含まれています。

```sql
-- セグメント別の購入金額集計
WITH email_purchase_events AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'currency'
    ) AS currency
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  utm_campaign,
  currency,
  COUNT(*) AS purchase_count,
  ROUND(SUM(purchase_value), 0) AS total_revenue,
  ROUND(AVG(purchase_value), 0) AS avg_order_value
FROM email_purchase_events
WHERE purchase_value IS NOT NULL
GROUP BY utm_campaign, currency
ORDER BY total_revenue DESC;
```

`avg_order_value`（平均注文金額）をキャンペーン間で比較することで、単価の高い顧客を動かしたキャンペーンが特定できます。クーポン訴求と新商品告知では平均注文金額に差が出ることが多く、施策の方向性を考える参考になります。

---

## リピーター・新規ユーザー別に効果を分ける

同じメルマガを送っても、新規ユーザーとリピーターでは反応が異なります。GA4の `user_first_touch_timestamp` を使うと、そのユーザーが初回接触したタイミングを判定できるため、既存顧客か否かの簡易的な識別が可能です。

```sql
-- 新規・リピート別のメルマガ効果比較
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    -- user_first_touch_timestamp はマイクロ秒単位
    TIMESTAMP_MICROS(user_first_touch_timestamp) AS first_touch_ts,
    TIMESTAMP_MICROS(event_timestamp) AS event_ts
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

session_agg AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_campaign,
    MIN(first_touch_ts) AS first_touch_ts,
    MIN(event_ts)        AS session_start_ts,
    COUNTIF(event_name = 'purchase') AS purchased
  FROM email_sessions
  GROUP BY user_pseudo_id, session_id, utm_campaign
)

SELECT
  utm_campaign,
  CASE
    WHEN TIMESTAMP_DIFF(session_start_ts, first_touch_ts, DAY) < 30
      THEN '新規（初回接触30日以内）'
    ELSE 'リピーター'
  END AS user_segment,
  COUNT(*) AS sessions,
  COUNTIF(purchased > 0) AS conversions,
  ROUND(SAFE_DIVIDE(COUNTIF(purchased > 0), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_agg
GROUP BY utm_campaign, user_segment
ORDER BY utm_campaign, user_segment;
```

:::message
`user_first_touch_timestamp` はユーザーが初めてサイトを訪れた日時をマイクロ秒で表します。`TIMESTAMP_MICROS()` で変換してから差分を計算してください。30日という閾値はビジネスの特性に合わせて調整してください。
:::

---

## Looker Studioで定期モニタリングする

SQLによる集計が完成したら、BigQueryのビュー（VIEW）として保存しておくとLooker Studioからの接続が楽になります。以下の手順で定期レポートを整備できます。

1. BigQueryコンソールで集計クエリを「ビューとして保存」する
2. Looker StudioでBigQueryデータソースとして接続する
3. キャンペーン名・セグメント・CVRの折れ線グラフ・表を配置する
4. 配信日ごとのフィルタを設定し、施策タイミングと数値の関係を把握する

Looker Studioを使えばノーコードでグラフを作成でき、チームへの共有も容易です。配信担当者がSQLを書けなくても、定点観測できる環境を用意することが継続的な改善につながります。

---

## まとめ

本記事では、GA4のBigQueryエクスポートデータを使ってメルマガ経由の購入を追跡し、セグメント別に効果を測定するSQLを紹介しました。要点を整理します。

- `ga_session_id` は `UNNEST(event_params)` 経由で取得する
- 流入元の判定は `collected_traffic_source.manual_medium` / `manual_source` を使う
- キャンペーン名・購入金額・新規リピーター別の集計で多角的に評価できる
- BigQueryビューとLooker Studioを組み合わせることでチーム共有しやすいレポートになる

次のアクションとして、まずは直近1〜2ヶ月分のデータでキャンペーン別CVRを比較してみてください。数値を見ることで、どのセグメントへの配信を強化すべきかの仮説が立てやすくなります。

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
