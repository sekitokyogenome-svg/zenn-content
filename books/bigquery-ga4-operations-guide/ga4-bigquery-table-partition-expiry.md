---
title: "【第4部 高速化】GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法"
---

## はじめに

GA4のデータをBigQueryにエクスポートして分析環境を構築しているものの、「気がつけばストレージコストが増え続けている」「BigQueryのダッシュボードを開いたらテーブルのサイズが数GBを超えていた」というご経験はないでしょうか。

GA4はデフォルトで毎日のイベントデータをBigQueryに書き出しますが、保持期間を明示的に設定しない限り、データは無期限に蓄積されます。アクセス数の多いECサイトであれば、1年も経たないうちにテーブルが数十GBから数百GBに達することも珍しくありません。

BigQueryの料金体系ではストレージに対しても課金が発生します。分析に使わない古いデータが積み上がっていれば、それだけ無駄なコストを払い続けることになります。この問題を解決する手段のひとつが「パーティション有効期限（Partition Expiration）」の設定です。

本章では、パーティション有効期限の概念から具体的な設定方法、注意点までを順を追って解説します。BigQueryの操作に慣れていない方でも理解しやすいよう、GUIとSQLの両面からご説明します。

---

## パーティション有効期限とは何か

BigQueryのパーティションテーブルとは、日付や時刻を単位としてデータを区切って保存する仕組みです。GA4のBigQueryエクスポートでは、`events_YYYYMMDD` という形式のテーブルが日次で生成されますが、これはシャーディング（日付シャード）と呼ばれる形式であり、厳密にはパーティションテーブルとは異なります。

パーティション有効期限とは、テーブルを構成する各パーティション（日付単位のデータ区画）に対して、「作成から○日後に自動削除する」というルールを設けることです。たとえば有効期限を365日に設定すれば、1年以上前のパーティションは自動的にBigQueryが削除してくれます。人手で古いデータを削除するオペレーションが不要になる点が大きなメリットです。

なお、GA4のデフォルトエクスポート形式（日付シャードテーブル）には直接パーティション有効期限を適用できません。有効期限を活用するには、日付シャードテーブルを結合してパーティションテーブルとして再構築するか、テーブル単位の有効期限（テーブル有効期限）を活用するか、あるいはスケジュールドクエリで定期的に古いシャードを削除するといった方法を組み合わせる必要があります。以降のセクションで、それぞれの方法を具体的に解説します。

---

## 方法1：テーブル有効期限（Table Expiration）でシャードを自動削除する

GA4の日付シャードテーブル（`events_YYYYMMDD`）に対して手軽に適用できるのが、データセット単位の「デフォルトテーブル有効期限」です。データセットにデフォルト有効期限を設定すると、そのデータセット内に新たに作成されるテーブルすべてに有効期限が付与されます。

BigQueryコンソール（GUIから設定する場合）での手順は以下のとおりです。

1. BigQueryのコンソールにアクセスし、対象のデータセット名をクリックします。
2. 「データセットの詳細」画面右上の「編集」をクリックします。
3. 「デフォルトのテーブル有効期限」欄に保持したい日数（例：365）を入力します。
4. 「保存」をクリックして完了です。

:::message
デフォルトテーブル有効期限は、**設定後に新しく作成されるテーブル**に対してのみ適用されます。すでに存在する既存の `events_YYYYMMDD` テーブルには遡及適用されません。既存テーブルへの適用が必要な場合は、後述のSQLによる個別設定をご利用ください。
:::

SQLで個別のテーブルに有効期限を設定する場合は、`ALTER TABLE` 文を使用します。

```sql
-- 特定のテーブルに有効期限を設定する例（例：2025年1月1日のシャード）
ALTER TABLE `your_project.analytics_XXXXXXXXX.events_20250101`
SET OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
);
```

上記のクエリを日付ごとに実行するのは現実的ではないため、スクリプトでまとめて適用する方法が実用的です。

```sql
-- データセット内の全シャードに365日の有効期限を一括設定するストアドプロシージャ
FOR record IN (
  SELECT table_id
  FROM `your_project.analytics_XXXXXXXXX.__TABLES__`
  WHERE REGEXP_CONTAINS(table_id, r'^events_\d{8}$')
)
DO
  EXECUTE IMMEDIATE FORMAT(
    """
    ALTER TABLE `your_project.analytics_XXXXXXXXX.%s`
    SET OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY))
    """,
    record.table_id
  );
END FOR;
```

`your_project` と `analytics_XXXXXXXXX` の部分はご自身のプロジェクトIDとデータセットIDに置き換えてください。

---

## 方法2：パーティションテーブルに統合して有効期限を管理する

より本格的な運用を目指す場合は、日付シャードテーブルをひとつのパーティションテーブルに統合する方法をお勧めします。パーティションテーブルであれば、テーブルレベルでパーティション有効期限を設定でき、古いデータの自動削除をより細かく制御できます。

以下のSQLは、GA4の日付シャードテーブルを結合しつつ、パーティションカラムを持つ新しいテーブルを作成する例です。

```sql
-- GA4のイベントデータをパーティションテーブルとして統合する
CREATE TABLE IF NOT EXISTS `your_project.analytics_XXXXXXXXX.events_partitioned`
PARTITION BY event_date
OPTIONS (
  partition_expiration_days = 365
)
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  ecommerce.purchase_revenue AS purchase_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE());
```

:::message
GA4のイベントパラメータ（`ga_session_id` など）は `event_params` 配列にネストされており、直接カラムとして参照することはできません。`UNNEST(event_params)` を経由して取得する必要があります。また、流入元の情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使用してください。
:::

このパーティションテーブルを作成した後は、スケジュールドクエリを使って毎日の差分データを追記（`INSERT INTO`）するよう設定することで、常に最新データを保持しつつ古いパーティションは自動削除されるようになります。

---

## 方法3：スケジュールドクエリで古いシャードを定期削除する

パーティションテーブルへの移行に時間をかけたくない場合や、現状の日付シャード形式を維持したまま容量を管理したい場合は、スケジュールドクエリによる定期削除も有効な選択肢です。

BigQueryのスケジュールドクエリ機能を使い、以下のような削除クエリを毎日実行するよう設定します。

```sql
-- 365日より古い events_ シャードテーブルを削除する
-- ※ BigQueryのDROP TABLEをストアドプロシージャで実行
FOR record IN (
  SELECT table_id
  FROM `your_project.analytics_XXXXXXXXX.__TABLES__`
  WHERE
    REGEXP_CONTAINS(table_id, r'^events_\d{8}$')
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(table_id, r'\d{8}')) < DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
)
DO
  EXECUTE IMMEDIATE FORMAT(
    'DROP TABLE IF EXISTS `your_project.analytics_XXXXXXXXX.%s`',
    record.table_id
  );
END FOR;
```

スケジュールドクエリの設定は、BigQueryコンソールの「スケジュールされたクエリ」メニューから行えます。繰り返し頻度を「毎日」に設定し、深夜帯など利用が少ない時間帯に実行するとよいでしょう。

:::message
スケジュールドクエリを実行するサービスアカウントには、対象データセットに対する `bigquery.tables.delete` 権限が必要です。権限が不足している場合はエラーが発生しますので、IAMの設定もあわせてご確認ください。
:::

---

## コスト削減効果の目安と注意点

パーティション有効期限やテーブル削除の設定によってどの程度のコスト削減が見込めるかは、サイトのトラフィック規模とデータ保持期間によって異なります。一般的な目安として、月間セッション数が数万件規模のECサイトで2〜3年分のデータを保持している場合、1年分に圧縮するだけで月数百円から数千円程度のストレージコスト削減になることがあります。

注意点として、削除したデータは原則として復元できません。設定を適用する前に、本当に不要なデータかどうかを慎重にご確認ください。また、法令や社内規程でデータ保持期間が定められている業種・業態では、コンプライアンス上の観点から削除期間を短くできない場合もあります。

さらに、BigQueryには「長期保存ストレージ」の料金優遇があり、90日間変更がないパーティションやテーブルは自動的に低コストの長期ストレージ扱いになります。アクセスが少ない古いデータは有効期限を設定せずとも自然にコストが下がる側面もありますので、削除とコスト管理のバランスを検討したうえで方針を決めることをお勧めします。

---

## まとめ

本章では、GA4×BigQueryにおけるテーブル肥大化を防ぐためのパーティション有効期限・テーブル有効期限の設定方法を3つの角度から解説しました。

- **テーブル有効期限（デフォルト or SQL）** ：既存の日付シャード形式を維持したまま手軽に設定できる
- **パーティションテーブルへの統合** ：長期運用や柔軟なデータ管理に適した本格的なアプローチ
- **スケジュールドクエリによる定期削除** ：既存構成を変えずに自動削除を実現したい場合に有効

いずれの方法も一度設定してしまえばほぼ自動で動作するため、メンテナンスの手間を最小限に抑えながらコスト管理を実現できます。まずはデータセットのデフォルトテーブル有効期限を設定するところから始めてみてください。
