---
title: "BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする"
emoji: "🔗"
type: "tech"
topics: ["bigquery","googleanalytics","ec","sql","dataengineering"]
published: false
---

## はじめに

「GA4でコンバージョンは計測しているけれど、実際の受注データと一致しない」——そんな悩みを抱えているEC担当者の方は多いのではないでしょうか。GA4のコンバージョンはブラウザ上の計測であり、キャンセルや決済失敗まで含んでしまうことがあります。一方、社内の受注管理システムに入る「確定受注」は、それとは別のデータです。

たとえば、月次の売上レポートをGA4で見ると100万円のコンバージョンが記録されているのに、実際の受注システムでは80万円しか確定していない——こういったズレが生じると、広告の費用対効果の算出も、流入経路ごとの売上貢献度の評価も、正確に行えません。

そこで本記事では、BigQueryに蓄積されたGA4のイベントデータと、EC受注システムから連携した受注テーブルを結合し、「どの流入経路が、実際にいくらの売上をもたらしたか」を分析するSQLの実装方法を解説します。非エンジニアの方にも読んでいただけるよう、データの構造や考え方からていねいに説明していきます。

---

## なぜEC受注データとGA4を結合する必要があるのか

GA4単体でのコンバージョン計測にはいくつかの限界があります。

**計測のズレが発生しやすい**：決済完了ページへのアクセスをコンバージョンとしている場合、ページを二重に読み込んだケースや、決済処理がエラーになったにもかかわらず完了ページに到達したケースも計上されます。

**受注のステータスが反映されない**：GA4はあくまでWebブラウザ上の行動を計測するツールです。後からキャンセルになった注文や、審査で却下された受注はGA4の数値には反映されません。

**オフライン・電話注文が含まれない**：ECサイト経由の注文であっても、電話やメールで受けた注文は計測対象外です。

こうした課題を解決するために、受注管理システム（OMS）や基幹システムの受注テーブルをBigQueryにエクスポートし、GA4のセッションデータと結合することで、「実態に基づいた売上帰属分析」が実現できます。

---

## データ構造を理解する：GA4のBigQueryエクスポートとは

GA4のデータはBigQueryに日次でエクスポートできます。エクスポートされたテーブルは `events_YYYYMMDD` という名前で保存されており、ユーザーの1イベント（ページビュー、クリック、購入など）が1行に格納されています。

GA4のイベントテーブルには `event_params` という配列型のカラムがあり、イベントに紐づくパラメータはここにまとめて格納されています。そのため、セッションIDのような情報も `UNNEST` を使って展開してから取得する必要があります。

また、流入元（参照元／メディア）の情報は `collected_traffic_source` というカラムに格納されており、`manual_source`（参照元）と `manual_medium`（メディア）を参照します。これはUTMパラメータで付与した流入情報を取得する際に使用します。

以下にGA4テーブルからセッションIDと流入情報を取得するSQLの例を示します。

```sql
-- GA4イベントテーブルからセッション情報を取得する例
SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  -- 流入元はcollected_traffic_sourceから取得
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  event_timestamp,
  event_name
FROM
  `your_project.analytics_XXXXXXXXX.events_20260101`
WHERE
  event_name = 'session_start'
```

:::message
`ga_session_id` は `event_params` の中にネストされているため、`UNNEST(event_params)` を用いてサブクエリ形式で取得します。`event.ga_session_id` のように直接参照することはできません。
:::

---

## EC受注データをBigQueryに取り込む

GA4データと結合するには、受注テーブルもBigQueryに用意する必要があります。一般的なEC受注テーブルには以下のようなカラムが含まれます。

| カラム名 | 内容 |
|---|---|
| order_id | 受注ID（主キー） |
| user_pseudo_id | GA4のユーザーID（クッキーベース） |
| ga_session_id | GA4のセッションID |
| order_amount | 確定受注金額 |
| order_status | 受注ステータス（confirmed / cancelled など） |
| ordered_at | 受注日時 |

GA4との結合キーとして `user_pseudo_id` と `ga_session_id` の両方を使用します。`user_pseudo_id` だけでは同一ユーザーの複数セッションが区別できないため、セッションIDとの組み合わせが重要です。

受注システムにGA4のIDを保持するには、ECサイトのフロントエンドでGA4のクライアントIDとセッションIDを取得し、注文フォームの隠しフィールドなどで受注データに含める実装が必要です。以下はJavaScriptでGA4のセッションIDを取得する例です。

```javascript
// GA4クライアントIDとセッションIDの取得例
gtag('get', 'G-XXXXXXXXXX', 'client_id', (clientId) => {
  document.getElementById('ga_client_id').value = clientId;
});

gtag('get', 'G-XXXXXXXXXX', 'session_id', (sessionId) => {
  document.getElementById('ga_session_id').value = sessionId;
});
```

取得したIDは注文データと一緒にDBに保存し、定期的にBigQueryへエクスポートします。

---

## GA4データと受注データを結合するSQL

両方のデータがBigQueryに揃ったら、いよいよ結合クエリを書きます。以下のSQLは、確定済み受注に対して、その受注を生んだセッションの流入元を紐付け、流入経路ごとの売上合計を集計するものです。

```sql
WITH
-- 受注が発生したセッションのGA4情報を取得
ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    MIN(event_timestamp) AS session_start_at
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND event_name = 'session_start'
  GROUP BY
    user_pseudo_id,
    ga_session_id,
    traffic_source,
    traffic_medium,
    campaign_name
),

-- 確定済み受注のみを対象にする
confirmed_orders AS (
  SELECT
    order_id,
    user_pseudo_id,
    ga_session_id,
    order_amount,
    ordered_at
  FROM
    `your_project.your_dataset.ec_orders`
  WHERE
    order_status = 'confirmed'
    AND DATE(ordered_at) BETWEEN '2026-01-01' AND '2026-01-31'
)

-- 受注と流入元を結合して集計
SELECT
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COALESCE(s.campaign_name, '(not set)')   AS campaign_name,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue,
  ROUND(AVG(o.order_amount), 0)            AS avg_order_value
FROM
  confirmed_orders AS o
LEFT JOIN
  ga4_sessions AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
GROUP BY
  traffic_source,
  traffic_medium,
  campaign_name
ORDER BY
  total_revenue DESC
```

:::message
`LEFT JOIN` を使用しているのは、GA4のIDが受注データに紐付いていないケース（電話注文など）も漏らさずカウントするためです。その場合、`traffic_source` は `(direct)` として集計されます。
:::

このクエリを実行すると、「Google / CPC（検索広告）からの受注が月間XX万円」「メールマガジンからの受注がXX万円」といった形で、流入経路ごとの実売上が把握できます。

---

## 分析結果をLooker Studioで可視化する

BigQueryのクエリ結果はLooker Studio（旧データポータル）と連携することで、グラフ・表形式のレポートとして共有できます。以下の手順でダッシュボードを作成できます。

1. Looker Studioを開き、新しいレポートを作成する
2. データソースとして「BigQuery」を選択する
3. 上記SQLをカスタムクエリとして登録する
4. 棒グラフや表を挿入し、流入元ごとの売上を可視化する

定期的に最新データを反映したい場合は、BigQueryのスケジュールドクエリを使って集計テーブルを自動更新する構成が便利です。

```sql
-- スケジュールドクエリで集計テーブルを毎日更新する例（テーブル書き込み設定で使用）
-- 宛先テーブル: your_project.your_dataset.revenue_by_channel

SELECT
  DATE(o.ordered_at)                       AS order_date,
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue
FROM
  `your_project.your_dataset.ec_orders` AS o
LEFT JOIN (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
) AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
WHERE
  o.order_status = 'confirmed'
  AND DATE(o.ordered_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY
  order_date,
  traffic_source,
  traffic_medium
```

---

## まとめ

本記事では、BigQueryを使ってEC受注データとGA4データを結合し、流入経路ごとの実売上を分析する方法を解説しました。要点を整理します。

- **GA4単体では確定受注の実態を把握しにくい**。キャンセルや計測ズレが含まれるため、受注システムのデータと照合することが重要です。
- **GA4のセッションIDは `UNNEST(event_params)` で取得する**。直接参照できないため、サブクエリ形式が必要です。
- **流入元の情報は `collected_traffic_source` を参照する**。`manual_source` と `manual_medium` でUTMパラメータ由来の流入元が取得できます。
- **受注データにGA4のIDを保持する仕組みが前提**。フロントエンドでのID取得と、受注フォームへの組み込みが必要です。
- **Looker Studioと連携することで、経営層にも共有しやすいレポートが作れる**。

次のアクションとして、まずは自社の受注テーブルにGA4の `user_pseudo_id` と `ga_session_id` を保存できているかを確認してみてください。このIDが揃っていれば、本記事のSQLをベースにした分析がすぐに始められます。

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
