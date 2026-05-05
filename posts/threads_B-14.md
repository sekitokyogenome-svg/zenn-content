毎月の事業報告書、データ集計からスライド作成まで半日以上かけていませんか？
BigQueryとClaude Codeを組み合わせると、月次報告書の作成を自動化できます。

記事で紹介している内容です。

・BigQueryでセッション・CVR・売上・チャネル別KPIをSQL一本で抽出
・ga_session_idをUNNEST経由で正確に集計し、サンプリングを回避
・collected_traffic_sourceでチャネル分類を精度高く行う
・抽出したデータをClaude APIに渡しMarkdown形式のレポートを自動生成
・レポートをSlack Webhookでチームに即時共有
・cron／Cloud Schedulerで毎月1日に全自動実行

実装はPythonスクリプト1本にまとまっており、既存のBigQuery環境があればすぐ導入できます。

月次報告書の作成コストを削減し、その時間を改善施策の立案に充てたい方にとって参考になる内容です。

https://zenn.dev/web_benriya/articles/bigquery-claude-code-monthly-business-report

#BigQuery #ClaudeCode
