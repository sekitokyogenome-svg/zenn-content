---
title: "【第5部 品質と復旧】BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み"
---

## はじめに

「BigQueryのデータマートを整備したものの、数字が正しいかどうか不安で使いきれていない」――そのようなお悩みを抱えていませんか。

分析基盤を構築した当初は問題なく動いていたSQLも、GA4のイベント仕様変更やデータパイプラインの改修が重なると、気づかないうちに集計値がずれていることがあります。レポートの数字を見て「なんとなく違和感がある」と感じながらも、どこから確認すれば良いのか分からず、結局そのまま意思決定に使ってしまう――これはデータ活用において非常に大きなリスクです。

SQLテスト（データテスト）とは、こうした「データの品質崩壊」を早期に検知するための仕組みです。エンジニアが書くコードのユニットテストと同じ発想で、「このSQLが返すべき結果の条件」を事前に定義し、定期的に自動チェックすることでデータマートの信頼性を維持します。

本章では、BigQueryとGA4エクスポートデータを例に取り、実務で使えるSQLテストの考え方と具体的な書き方を解説します。

---

## SQLテストとは何か――品質チェックの基本的な考え方

SQLテストとは、一言でいえば「このデータはこうあるべき」という期待値を定義して、実際のデータが期待通りかどうかを検証するクエリのことです。

ソフトウェア開発では、コードの動作を担保するためにユニットテストを書くことが一般的です。データエンジニアリングの世界でも同じ考え方を適用したのがSQLテストです。たとえば次のような観点でテストを定義します。

- **NULLチェック**: 重要なカラムにNULLが入っていないか
- **一意性チェック**: プライマリキーとなるカラムに重複がないか
- **範囲チェック**: 数値が想定の範囲内に収まっているか
- **参照整合性チェック**: マスタテーブルに存在しないコードが混入していないか

これらのテストが失敗したとき（つまり期待と異なるデータが見つかったとき）に通知を受け取る仕組みと組み合わせることで、データマートの異常を素早く検知できるようになります。

:::message
dbtというSQLの変換管理ツールを使うと、こうしたテストを設定ファイルに記述するだけで自動化できます。BigQueryとの相性も良く、中〜大規模なデータ基盤では標準的な選択肢になっています。本章では、dbtなしで純粋なBigQueryクエリとしてテストを書く方法を中心に扱います。
:::

---

## GA4エクスポートデータでのNULLチェックと一意性チェック

GA4のBigQueryエクスポートデータを使ったデータマートでよく起きる問題の一つが、セッションIDの重複やNULL混入です。

GA4のイベントデータでは、`ga_session_id` は `event_params` の中にネストされており、直接カラムとして参照することができません。`UNNEST` を使って展開する必要があります。

以下は、セッションIDのNULLと重複を検出するテストクエリの例です。

```sql
-- テスト: ga_session_id のNULL件数を確認する
SELECT
  COUNT(*) AS null_session_id_count
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
```

このクエリの結果が0件であれば、テスト通過（期待通り）です。1件以上あれば、データの異常を示すアラートとして扱います。

次に、日次セッション集計テーブルの一意性チェックです。セッション単位で集計したデータマートでは、1セッションが複数行になっていると集計値が膨らんでしまいます。

```sql
-- テスト: セッション集計テーブルの主キー重複チェック
SELECT
  event_date,
  session_id,
  COUNT(*) AS duplicate_count
FROM
  `your_project.datamart.session_summary`
WHERE
  event_date = '2025-01-15'
GROUP BY
  event_date,
  session_id
HAVING
  COUNT(*) > 1
;
```

`HAVING COUNT(*) > 1` に引っかかる行が存在する場合、データマートの重複バグを示しています。

---

## 流入元データの整合性チェック

データマートに集計した流入元データが正しいかを確認するテストも重要です。GA4のBigQueryエクスポートでは、流入元の情報は `collected_traffic_source` カラムの中の `manual_medium` と `manual_source` を参照します。

```sql
-- テスト: 想定外の流入mediumが混入していないかを確認する
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND event_name = 'session_start'
GROUP BY
  medium
ORDER BY
  event_count DESC
;
```

このクエリで `medium` の一覧を確認し、`organic`、`cpc`、`email` などの想定値以外が含まれていないかをチェックします。たとえばスペルミスやUTMパラメータの設定ミスにより `CPC`（大文字）や `referral ` （末尾スペース）などが混入していることがあります。

さらに一歩進めて、想定値以外のmediumが存在した場合に結果を返すテストクエリにすることで、異常の自動検知に活用できます。

```sql
-- テスト: 許可されていないmediumが存在すれば結果を返す
WITH allowed_mediums AS (
  SELECT medium FROM UNNEST(['organic', 'cpc', 'email', 'social', 'referral', '(none)']) AS medium
),
actual_mediums AS (
  SELECT DISTINCT
    collected_traffic_source.manual_medium AS medium
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
)
SELECT
  a.medium AS unexpected_medium
FROM
  actual_mediums a
LEFT JOIN
  allowed_mediums al ON a.medium = al.medium
WHERE
  al.medium IS NULL
;
```

クエリが0行を返せばテスト通過、1行以上返れば想定外のmediumが混入しているというシグナルです。

---

## テストの自動実行――BigQuery Scheduled Queriesを活用する

テストクエリを書いただけでは、毎日手動で実行しなければならず、運用の手間がかかります。BigQueryには「スケジュールドクエリ（Scheduled Queries）」という機能があり、任意のSQLを定期的に自動実行できます。

テスト結果をログテーブルに書き出す構成にすることで、「いつテストが失敗したか」の履歴を蓄積できます。

```sql
-- テスト結果をログテーブルに INSERT する例
INSERT INTO `your_project.datamart.test_results` (
  test_name,
  test_date,
  result_count,
  status,
  executed_at
)
SELECT
  'null_session_id_check' AS test_name,
  CURRENT_DATE()          AS test_date,
  COUNT(*)                AS result_count,
  IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
  CURRENT_TIMESTAMP()     AS executed_at
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
```

このテスト結果テーブルを Looker Studio や Google スプレッドシートで可視化すると、品質監視ダッシュボードとして活用できます。Scheduled Queries の通知機能と組み合わせれば、FAILが発生したタイミングでメール通知を受け取ることも可能です。

:::message
Scheduled Queries はBigQueryのコンソール（`クエリのスケジュール設定`）から設定できます。実行間隔は日次・週次など柔軟に指定できます。なお、クエリの実行コストはスキャンするデータ量に比例するため、`_TABLE_SUFFIX` で日付を絞り込むことがコスト管理の観点からも重要です。
:::

---

## まとめ

BigQueryでSQLテストを導入することで、データマートの品質崩壊を早期に発見できる仕組みが整います。本章のポイントを整理します。

- **SQLテストの目的**はデータの異常（NULL・重複・想定外の値）を自動的に検知すること
- **GA4のBigQueryエクスポートデータ**では `UNNEST(event_params)` でセッションIDを取得し、`collected_traffic_source.manual_medium` / `manual_source` で流入元を参照する
- テストクエリは「期待通りであれば0行を返す」設計にすると、結果の判定がシンプルになる
- **Scheduled Queries** で定期自動実行し、結果をログテーブルに蓄積することで品質監視の仕組みが完成する

「まず1本だけテストを書く」ことから始めてみてください。NULLチェックや一意性チェックといったシンプルなテストでも、データマートへの信頼度が大きく高まります。テストが積み重なるにつれて、数字を安心して意思決定に使える基盤が育っていきます。
