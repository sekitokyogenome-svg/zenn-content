毎回BigQueryでGA4のrawテーブルにクエリを流していませんか？同じ集計を繰り返すたびにコストが積み上がる構造、Scheduled Queriesで変えられます。

BigQueryのScheduled Queriesを使って、日次・週次・月次の集計テーブルを自動生成する設計とSQLを解説しました。

- 日次集計はMERGE文で冪等性を担保し、再実行しても重複しない設計にする
- パーティション＋クラスタリングを設定することでダッシュボードからの読み取り速度が上がる
- 週次は毎週月曜、月次は毎月1日にトリガーする運用パターンを採用
- GA4エクスポートの遅延に備えてテーブル存在チェックを入れる
- スケジュールの時刻はUTC指定のため、JST換算を間違えないよう注意が必要
- GCPコンソールとbqコマンド、両方の設定手順を掲載
- 失敗時のPub/Sub×Slack通知連携まで含めた運用設計を紹介

一度仕組みを作れば、毎朝の集計は全自動になります。ダッシュボードのクエリ速度とBigQueryコスト、両方を同時に改善できます。

https://zenn.dev/web_benriya/articles/bigquery-ga4-scheduled-aggregation-tables

#BigQuery #GA4分析
