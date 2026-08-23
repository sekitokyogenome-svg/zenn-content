---
title: "GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け"
emoji: "🔄"
type: "tech"
topics: ["bigquery","googleanalytics","googlecloud","sql","dataengineering"]
published: true
---

## はじめに

GA4のデータをBigQueryに連携しているものの、「ストリーミングエクスポート」と「日次エクスポート」のどちらを使えばよいのか迷っていませんか？

GA4とBigQueryを接続すると、デフォルトでは**日次エクスポート**が有効になります。一方、設定によって**ストリーミングエクスポート**を追加で有効化することも可能です。この2種類のエクスポートは、テーブル名・更新タイミング・コスト・利用シーンのいずれもが異なります。

「データは全部同じ場所に入っているのでは？」と思われる方も多いのですが、実態は大きく異なります。用途を混同してしまうと、クエリコストが膨らんだり、データの不整合が起きたりすることがあります。

本記事では、ストリーミングエクスポートと日次エクスポートの仕組みの違いを整理し、どのような場面でどちらを選ぶべきかを具体的なSQLを交えながら解説します。GA4やBigQueryをこれから活用したいEC事業者の方にも読みやすいよう、できるだけ平易な言葉でまとめました。

---

## ストリーミングエクスポートと日次エクスポートの基本的な違い

まず、両者の特性を整理します。

| 項目 | 日次エクスポート | ストリーミングエクスポート |
|------|-----------------|--------------------------|
| テーブル名 | `events_YYYYMMDD` | `events_intraday_YYYYMMDD` |
| 更新タイミング | 翌日以降（処理完了後） | リアルタイム（数分以内） |
| データ確定性 | 高い（後処理済み） | 低い（未確定データを含む） |
| BigQueryコスト | 通常のストレージ料金 | ストリーミング挿入の追加料金あり |
| 保持期間 | 無期限（設定による） | 当日のみ（翌日に削除） |

**日次エクスポート**は `events_YYYYMMDD` という形式のテーブルに保存されます。GA4側での後処理（アトリビューション計算や重複除去など）が完了した後にテーブルが確定するため、データの精度が高いという特徴があります。レポートや月次分析など、精度を重視する用途に向いています。

**ストリーミングエクスポート**は `events_intraday_YYYYMMDD` というテーブルに、ユーザーのアクションがほぼリアルタイムで書き込まれます。ただし、日次テーブルへの移行処理が完了すると翌日に削除されるため、長期保存には使えません。当日中にデータを確認したい場合に限定して使うものと理解しておくのがよいでしょう。

:::message
ストリーミングエクスポートはGA4のプロパティ設定から個別に有効化する必要があります。BigQueryリンク設定画面の「ストリーミング」オプションをオンにしてください。有効化するとBigQueryのストリーミング挿入コストが発生する点にご注意ください。
:::

---

## テーブル構造とSQLの書き方

日次テーブルとイントラデイテーブルは基本的に同じスキーマを持っています。ただし、クエリを書く際にはテーブルの指定方法に注意が必要です。

### 日次テーブルを対象にしたクエリ例

過去7日間のイベント数をページパスごとに集計するSQLです。

```sql
SELECT
  event_name,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name,
  page_location
ORDER BY
  event_count DESC
LIMIT 50;
```

`events_*` のワイルドカードを使い、`_TABLE_SUFFIX` で日付範囲を絞り込む方法が一般的です。これにより、複数日のテーブルをまとめてスキャンできます。

### ga_session_id の取得方法

GA4ではセッションIDは `event_params` の中にネストされているため、直接フィールドとして参照することはできません。以下のように `UNNEST` を使って取り出します。

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `your_project.analytics_XXXXXXXXX.events_20250801`
WHERE
  event_name = 'purchase'
LIMIT 100;
```

### 流入元の取得方法

参照元・メディアは `collected_traffic_source` フィールドから取得します。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(*) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
```

:::message
`collected_traffic_source` はGA4が収集したトラフィックソース情報を保持するフィールドです。Google広告との自動タグ付けが有効な場合は `google_ads_*` 系のフィールドも参照できます。
:::

---

## ストリーミングテーブルを使うべきシーン

ストリーミングエクスポート（`events_intraday_*`）は、リアルタイム性が求められる以下のようなケースに有効です。

**当日の売上・コンバージョンをモニタリングしたい場合**

ECサイトの当日購入数をリアルタイムで確認したい場合、日次テーブルは前日分までしか存在しないため、`events_intraday_*` を参照する必要があります。

```sql
SELECT
  FORMAT_TIMESTAMP('%H', TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS hour,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_intraday_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'purchase'
GROUP BY
  hour
ORDER BY
  hour;
```

**異常検知・アラート用途**

特定のエラーイベントやカート離脱の急増などをほぼリアルタイムで検知したい場合も、ストリーミングテーブルが役立ちます。Cloud Schedulerなどで定期的にクエリを実行し、閾値を超えた場合に通知を飛ばす仕組みと組み合わせると効果的です。

一方で、以下の点には注意が必要です。

- ストリーミングテーブルのデータは**確定前**のため、後から日次テーブルと突き合わせると数値が若干異なることがあります。
- 翌日には削除されるため、当日分のデータを保存したい場合は別途スナップショットを取る仕組みが必要です。
- BigQueryのストリーミング挿入はスキャンコストに加えて**挿入量に応じた課金**が発生します。

---

## 日次テーブルとイントラデイを組み合わせる方法

直近7日間のデータを常に最新の状態で見たい場合、日次テーブルとストリーミングテーブルを `UNION ALL` で結合するアプローチがよく使われます。

```sql
-- 過去6日分（確定済み）＋本日分（ストリーミング）を合わせて参照する
SELECT
  event_date,
  event_name,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM (
  -- 確定済みの日次テーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 6 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))

  UNION ALL

  -- 本日のストリーミングテーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `your_project.analytics_XXXXXXXXX.events_intraday_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
)
GROUP BY
  event_date,
  event_name
ORDER BY
  event_date DESC,
  users DESC;
```

このパターンはLooker Studioのデータソースとしてカスタムクエリで設定することもできます。ダッシュボードの「昨日まで」と「今日のリアルタイム」を1つのビューにまとめたい場合に便利です。

:::message
`events_intraday_*` が存在しない日（ストリーミングエクスポートが無効な日）にこのクエリを実行するとエラーになることがあります。本番運用では `IF EXISTS` チェックやエラーハンドリングを組み込むことをお勧めします。
:::

---

## コストと運用面での注意点

GA4とBigQueryの連携を長期的に運用する際には、コスト管理も重要です。

**ストレージコスト**

日次テーブルは日数分のパーティションとして蓄積されていきます。長期間運用すると相当量のストレージになるため、必要に応じてテーブルの有効期限（expiration）を設定しましょう。BigQueryのテーブル設定から、一定日数を超えたパーティションを自動削除することができます。

**クエリコスト**

BigQueryはスキャンしたデータ量に応じて課金されます（オンデマンド料金の場合）。`events_*` のワイルドカードで全期間を対象にすると、非常に多くのデータをスキャンしてしまうため、`_TABLE_SUFFIX` による日付絞り込みは徹底してください。

また、頻繁に使う集計はビューやマテリアライズドビューとして定義しておくと、都度の全スキャンを防ぐことができます。

**ストリーミング挿入コスト**

ストリーミングエクスポートを有効にすると、挿入されるデータ量に応じてBigQueryのストリーミング挿入料金が発生します。トラフィックの多いサイトでは無視できない金額になる場合もあるため、月次でコストを確認する習慣をつけることをお勧めします。

```bash
# BigQueryのコストを確認するbqコマンド（CLIから実行する場合）
bq query --use_legacy_sql=false \
  "SELECT SUM(total_bytes_processed) / POW(10,12) AS tb_processed
   FROM \`region-asia-northeast1\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
   WHERE creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
     AND CURRENT_TIMESTAMP()
     AND job_type = 'QUERY'
     AND state = 'DONE'"
```

---

## まとめ

GA4 BigQueryエクスポートのストリーミングと日次の違いをまとめます。

- **日次エクスポート（`events_YYYYMMDD`）**: データが確定しており精度が高い。月次レポートや広告効果分析など、正確な数値が求められる用途に適している。
- **ストリーミングエクスポート（`events_intraday_YYYYMMDD`）**: リアルタイム性が高いが未確定データを含む。当日のモニタリングや異常検知に活用できる。翌日には削除されるため、保存が必要な場合は別途対応が必要。
- **組み合わせて使う**: `UNION ALL` で両テーブルを結合することで、「直近7日間を常に最新状態で見る」ようなダッシュボードを構築できる。
- **コスト管理**: 日付絞り込みの徹底とストレージ有効期限の設定が運用コスト最適化の基本。

まずは日次テーブルだけで分析を始め、「当日のリアルタイムデータが必要」という具体的な要件が出てきた段階でストリーミングエクスポートの追加を検討するのが、コストと複雑性のバランスのとれた進め方です。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
