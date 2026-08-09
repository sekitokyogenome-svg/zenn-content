---
title: "【第3部 自動化とパイプライン】BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法"
---

## はじめに

毎朝、Googleスプレッドシートを開いて前日のデータを手動でコピー＆ペーストしていませんか？あるいは、Looker Studioのレポートが古いデータを表示したまま更新されず、会議の直前に慌てて確認するといった経験はないでしょうか。

GA4のデータをBigQueryにエクスポートしている場合、そのデータを毎日自動で整形・集計してデータマートとして保存しておけば、こうした手間を大幅に削減できます。BigQueryには「スケジュールクエリ」という機能があり、SQLクエリを定期的に自動実行してテーブルを更新することが可能です。

本章では、BigQueryのスケジュールクエリを使ってGA4データのデータマートを毎朝自動更新する方法を、設定手順から監視方法まで順を追って解説します。SQLの細かい知識がなくても概要を理解できるよう、丁寧に説明していきますので、非エンジニアの方にもご参考いただけます。

## データマートとは何か、なぜ必要なのか

「データマート」とは、分析目的に合わせてデータを整形・集計した中間テーブルのことを指します。GA4のBigQueryエクスポートではイベントレベルの生データが蓄積されますが、そのままでは「昨日のセッション数は何件か」「流入元ごとのコンバージョン率はどのくらいか」といった集計をクエリのたびに一から行う必要があります。

データマートを作成すると、以下のメリットがあります。

- **クエリの速度向上**：事前に集計済みのデータを参照するため、レポート表示が速くなります
- **コスト削減**：BigQueryは読み込むデータ量に応じて課金されるため、集計済みの小さなテーブルを参照することで費用を抑えられます
- **Looker Studioとの連携が楽になる**：接続先テーブルが整理されており、ディメンションや指標の設定が簡単になります
- **チーム共有がしやすい**：集計ロジックをSQLとして一元管理できるため、「どのデータを使っているか」が明確になります

スケジュールクエリと組み合わせることで、毎朝自動的にデータマートが更新され、Looker Studioを開くだけで前日のデータを確認できる環境が整います。

## データマート用SQLの書き方（GA4エクスポートテーブル使用）

まず、データマートのもとになるSQLクエリを作成します。以下は、GA4のBigQueryエクスポートテーブルから日別・流入元別のセッション数とコンバージョン数を集計する例です。

```sql
-- データマート：日別・流入元別セッションサマリー
-- 実行対象: myproject.analytics_XXXXXXX.events_*

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `myproject.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  date, medium, source
ORDER BY
  date DESC, sessions DESC
```

:::message
`myproject.analytics_XXXXXXX` の部分は、ご自身のGCPプロジェクトIDとGA4プロパティIDに合わせて変更してください。ga_session_idはevent_paramsの中にネストされているため、UNNEST経由での参照が必要です。直接 `ga_session_id` というカラム名で参照しようとするとエラーになりますのでご注意ください。
:::

また、流入元の情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使用しています。これはGA4のBigQueryエクスポートにおける推奨の参照方法です。`traffic_source` テーブルとは異なる値が返ることがあるため、フィールドの違いを把握しておくと分析精度が上がります。

このクエリをスケジュールクエリとして登録することで、毎朝自動的に過去7日分のデータが集計されたテーブルが更新されます。

## BigQueryスケジュールクエリの設定手順

BigQueryのコンソールからスケジュールクエリを設定する手順を説明します。

**1. クエリエディタでSQLを確認する**

上記のSQLをBigQueryコンソールのクエリエディタに貼り付け、まず手動で実行して正しい結果が返ることを確認します。エラーが出る場合はプロジェクトIDやテーブル名を確認してください。

**2. スケジュールクエリとして登録する**

クエリエディタ上部の「スケジュール」ボタン（または「その他」→「クエリをスケジュール」）をクリックします。表示されたダイアログで以下を設定します。

| 設定項目 | 推奨値の例 |
|---|---|
| クエリ名 | `daily_session_summary` |
| 繰り返しの頻度 | 毎日 |
| 実行時刻 | 午前8時（日本時間） |
| 宛先データセット | `datamart` |
| 宛先テーブル | `session_summary` |
| テーブルへの書き込み設定 | テーブルを上書きする |

**3. タイムゾーンの設定に注意する**

スケジュールクエリのタイムゾーンはデフォルトでUTCになっています。日本時間の午前8時に実行したい場合は、タイムゾーンを「Asia/Tokyo」に設定するか、UTC換算（日本時間−9時間）を考慮して設定してください。タイムゾーンのズレは見落としやすいポイントで、「昨日分のデータが含まれていない」というトラブルの原因になることがあります。

**4. サービスアカウントの権限を確認する**

スケジュールクエリの実行には、適切な権限を持つサービスアカウントが必要です。最低限、以下の権限が付与されていることを確認してください。

- BigQuery ジョブユーザー（`roles/bigquery.jobUser`）
- BigQuery データ編集者（`roles/bigquery.dataEditor`）

```bash
# gcloudコマンドでサービスアカウントに権限を付与する例
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:YOUR_SA@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:YOUR_SA@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"
```

:::message
スケジュールクエリは初回登録時にGoogle Cloud Data Transfer Service APIの有効化が求められます。プロンプトが表示された場合は「有効化」を選択してください。
:::

## スケジュールクエリの監視とアラート設定

スケジュールクエリは自動実行されるため、失敗しても気づかないケースがあります。ここでは、実行状況を監視する方法を2つ紹介します。

### 方法1：BigQueryコンソールでの確認

BigQueryコンソールの左メニューから「スケジュールされたクエリ」を選択すると、登録済みのスケジュールクエリの一覧と直近の実行履歴を確認できます。各クエリの「実行履歴」タブには、実行日時・ステータス（成功／失敗）・処理したバイト数が表示されます。毎朝確認する運用であれば、この画面を起点にするだけでも十分です。

### 方法2：Cloud Monitoringでアラートを設定する

スケジュールクエリが失敗したときにメール通知を受け取るには、Google Cloud MonitoringのAlerts機能を活用します。まず、ログベースのカスタムメトリクスを作成します。

```bash
# Cloud Monitoringでログベースのアラートメトリクスを作成する例
gcloud logging metrics create scheduled_query_failure \
  --description="BigQuery scheduled query failure" \
  --log-filter='resource.type="bigquery_resource" AND protoPayload.status.code!=0 AND protoPayload.methodName="jobservice.jobcompleted"'
```

作成したメトリクスをもとに、GCPコンソールの「Monitoring」→「アラート」→「ポリシーを作成」からメール通知を設定します。失敗件数が1件以上になったときに通知が届くよう設定しておくと、運用上の安心感が高まります。

### データの鮮度をSQLで確認する

データマートテーブルが正しく更新されているかどうかを、以下のSQLで簡単に確認できます。

```sql
-- テーブルの最終更新日時を確認する
SELECT
  table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified_jst
FROM
  `myproject.datamart.INFORMATION_SCHEMA.TABLES`
WHERE
  table_name = 'session_summary'
```

:::message
`myproject.datamart` の部分は、実際のプロジェクトIDとデータセット名に置き換えてください。このクエリをLooker Studioのデータソースとして接続すると、レポート上でデータの更新日時を可視化することもできます。
:::

## まとめ

BigQueryのスケジュールクエリを活用することで、GA4データの日次集計作業を自動化し、毎朝最新のデータマートが用意された状態を維持できます。本章の内容をまとめると以下のとおりです。

- **データマートの作成**：GA4のBigQueryエクスポートテーブルからSQLで集計テーブルを作成する。ga_session_idはUNNEST(event_params)経由で取得し、流入元はcollected_traffic_sourceを参照する
- **スケジュールクエリの設定**：BigQueryコンソールから実行時刻・宛先テーブル・書き込み方法を設定する
- **タイムゾーンに注意**：実行時刻のタイムゾーンをAsia/Tokyoに設定し、日次データのズレを防ぐ
- **監視の仕組みを作る**：実行履歴の確認とCloud Monitoringのアラート設定でエラーを見逃さない環境を整える

次のステップとしては、スケジュールクエリで更新されたデータマートをLooker Studioに接続して自動更新ダッシュボードを構築することをおすすめします。データの収集から可視化までのパイプラインが整うと、日々の分析業務がぐっとスムーズになります。また、複数のデータマートテーブルを用途別に作成しておくと、売上分析・広告効果測定・顧客行動分析など、目的に応じた切り口でデータを参照しやすくなります。
