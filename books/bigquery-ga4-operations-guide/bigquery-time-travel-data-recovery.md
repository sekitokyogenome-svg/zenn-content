---
title: "【第5部 品質と復旧】BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法"
---

## はじめに

「BigQueryでテーブルを誤って削除してしまった」「UPDATE文を実行したら意図しない行まで上書きされてしまった」——そんな経験はありませんか？

データ分析基盤を運用していると、ヒューマンエラーは避けられません。特にGA4のBigQueryエクスポートを活用されている方は、蓄積したイベントデータや独自の集計テーブルを誤操作で失うリスクを常に抱えています。バックアップを別途取っていれば安心ですが、日々の運用でそこまで手が回っていないケースも多いかと思います。

BigQueryには「タイムトラベル」と呼ばれる機能が標準で備わっており、過去7日間（デフォルト設定）の任意の時点にさかのぼってデータを参照・復旧することができます。この機能を知っておくだけで、万が一の際に冷静に対処できるようになります。本章では、タイムトラベルの仕組みと具体的なSQL操作方法を、実際のGA4テーブルを例に挙げながら解説します。

---

## BigQueryのタイムトラベルとは

タイムトラベルはBigQueryが内部的に保持している「変更前のデータスナップショット」を参照する仕組みです。テーブルに対してDELETE・UPDATE・テーブル削除などの変更操作が行われても、BigQueryはデフォルトで**7日間**（最大7日、最短2日まで設定変更可能）にわたって変更前のデータを保持し続けます。

利用できる操作は主に以下の2つです。

- **FOR SYSTEM_TIME AS OF** 句を使ったクエリ（過去の状態を SELECT で参照）
- **テーブルの復元**（削除済みテーブルを `bq cp` コマンドや `CREATE TABLE` で再作成）

追加費用なしで使える点も大きなメリットです。ただし、7日を超えてしまったデータは復旧できないため、気づいたときに速やかに対応することが重要です。

:::message
タイムトラベルで参照できる期間は、テーブルの「タイムトラベル期間」設定によります。デフォルトは7日間ですが、データセット単位またはテーブル単位で2〜7日の範囲で変更可能です。
:::

---

## 過去時点のデータをSELECTで確認する

データを復旧する前に、まず「どの時点の状態に戻したいか」を確認しましょう。`FOR SYSTEM_TIME AS OF` 句を使うと、指定した時刻時点のテーブルの内容をSELECTで参照できます。

以下はGA4のBigQueryエクスポートテーブルに対して、24時間前の状態を確認するクエリの例です。

```sql
-- 24時間前のGA4イベントデータを確認する
SELECT
  event_date,
  event_name,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXX.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date, event_name, ga_session_id, medium, source
ORDER BY
  event_date DESC
LIMIT 100;
```

`FOR SYSTEM_TIME AS OF` に渡すのはタイムスタンプです。`TIMESTAMP_SUB` 関数や `TIMESTAMP '2025-07-30 10:00:00 UTC'` のようにリテラルで指定することもできます。まずこのSELECTで「過去のデータが正しく残っているか」「どの時点まで戻れば正常な状態か」を確認してから、復旧作業に進むと安全です。

:::message
`ga_session_id` はBigQueryのGA4エクスポートテーブルにおいてトップレベルのカラムとして存在しないため、`UNNEST(event_params)` を経由して取得する必要があります。直接 `event_params.ga_session_id` のように参照するとエラーになりますのでご注意ください。
:::

---

## 誤更新したデータを元に戻す（テーブル上書き）

UPDATE文やDELETE文を誤って実行してしまった場合、タイムトラベルで取得した過去の状態を使ってテーブルを上書き復元できます。

以下の手順で対応します。

**手順1: 復旧先テーブルに過去の状態を上書きする**

```sql
-- 誤更新前の状態でテーブルを上書き復元する
CREATE OR REPLACE TABLE `your_project.your_dataset.target_table`
AS
SELECT *
FROM `your_project.your_dataset.target_table`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC';
```

`CREATE OR REPLACE TABLE` と `FOR SYSTEM_TIME AS OF` を組み合わせることで、指定時点のスナップショットを現在のテーブルに上書きできます。`TIMESTAMP` はUTC基準で指定することに注意してください。日本時間（JST）で考える場合は9時間を差し引いた値を入力するか、`TIMESTAMP '2025-07-30 09:00:00+09:00'` のようにタイムゾーンを明示します。

**手順2: 部分的な復旧（特定行のみ戻す）**

テーブル全体ではなく、特定の条件に合致する行だけを元に戻したい場合は、MERGE文を活用します。

```sql
-- 特定条件の行のみ過去状態から復旧するMERGE例
MERGE `your_project.your_dataset.target_table` AS current
USING (
  SELECT *
  FROM `your_project.your_dataset.target_table`
  FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC'
  WHERE order_status = 'cancelled'  -- 誤更新された行の条件
) AS past
ON current.order_id = past.order_id
WHEN MATCHED THEN
  UPDATE SET
    current.order_status = past.order_status,
    current.updated_at   = past.updated_at;
```

このように、過去状態をサブクエリとして参照しながらMERGEを実行することで、影響範囲を最小限に抑えた復旧が可能です。

---

## 削除されたテーブルを復元する

テーブルそのものを誤って削除してしまった場合は、`bq cp` コマンドを使って復元します。`bq` コマンドはGoogle Cloud SDKに含まれているCLIツールです。

```bash
# 削除されたテーブルをタイムトラベルで復元する
bq cp \
  "your_project:your_dataset.deleted_table@-3600000" \
  "your_project:your_dataset.deleted_table_restored"
```

`@-3600000` の部分は「現在から3,600,000ミリ秒（1時間）前」を意味します。ミリ秒単位で指定するのがポイントです。代わりに `@1722312000000` のようにUnixエポックのミリ秒タイムスタンプを直接指定することもできます。

復元先テーブル名（上記例では `deleted_table_restored`）は存在しないテーブル名を指定してください。既存テーブルへの上書きには `--force` フラグが必要です。

```bash
# Unixタイムスタンプ（ミリ秒）で指定する場合
bq cp \
  "your_project:your_dataset.deleted_table@1722312000000" \
  "your_project:your_dataset.deleted_table"
```

:::message
テーブルが削除されていても、タイムトラベル期間内（デフォルト7日以内）であれば上記の方法で復元が可能です。7日を超えた場合は復旧できないため、削除に気づいたらできるだけ早く対応してください。
:::

---

## GA4集計テーブルの復旧シナリオ例

実際の運用でよく起こるシナリオとして、GA4データをもとに作成した独自集計テーブルを誤って上書きしてしまうケースを考えてみます。

たとえば、月次のセッション数・流入元別集計テーブルを定期バッチで更新している場合、スクリプトのバグで集計条件が変わってしまい、正しくないデータで上書きされてしまうことがあります。

```sql
-- 誤上書き前の集計テーブル（タイムトラベルで確認）
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXX.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date, sessions DESC;
```

このクエリで「2時間前の集計元データが正常か」を確認できます。元データが正常であれば、集計テーブルを上書きしたジョブを再実行するか、`CREATE OR REPLACE TABLE` で過去状態から集計テーブルを再作成することで対応可能です。

---

## まとめ

本章では、BigQueryのタイムトラベル機能を使ったデータ復旧方法を解説しました。要点を整理します。

- タイムトラベルはデフォルトで**7日間**有効で、追加費用なしで利用できる
- `FOR SYSTEM_TIME AS OF` 句でSELECT・CREATE TABLE・MERGEに組み込める
- 削除済みテーブルは `bq cp` コマンドにミリ秒タイムスタンプを付加して復元できる
- 復旧前に必ず過去状態のSELECTで内容を確認してから上書きするのが安全
- GA4のBigQueryエクスポートテーブルでも同様に適用できる

「事前にバックアップが取れていなかった」という状況でも、7日以内であればタイムトラベルが頼りになります。ただし、タイムトラベルはあくまで緊急時の対処法です。定期的なスナップショット（`CREATE SNAPSHOT TABLE`）の運用や、本番テーブルへの直接書き込みを避けるようなデータパイプライン設計を並行して検討されることをお勧めします。

次のアクションとして、まず自社のBigQueryプロジェクトで `FOR SYSTEM_TIME AS OF` を使ったテストクエリを実行してみてください。本番環境を触る前に動作を確認しておくと、いざというときに慌てずに済みます。
