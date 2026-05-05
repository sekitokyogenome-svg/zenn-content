毎月の月次報告書づくりに、半日潰してませんか。

データ集計、Excelで表とグラフ、前月比のコメント、フォーマット整えてPDF化。
これを毎月、社長や役員のために手作業でやっている事業責任者は多いはず。

BigQueryからKPIを抽出して、Claude Codeで月次報告書をMarkdownで自動生成し、Slackに自動投稿する仕組みを作りました。

流れはこの3ステップ。
・BigQueryでKPI集計SQLをテンプレ化（セッション・CV・売上・チャネル別）
・Claude APIにデータを渡してMarkdownレポートを生成
・Slack Webhookで月初の朝に自動通知

ポイントはClaudeに渡すプロンプトの設計です。
「エグゼクティブサマリ3行」「前月比に矢印付き」「課題と改善提案を3つ」と指示しておくだけで、毎月安定したフォーマットの報告書が出てきます。

Cloud Schedulerで毎月1日の朝9時にセットすれば、出社前にSlackに月次報告書が届いている状態にできます。

SQL・Pythonコード・プロンプト設計まで全部記事にまとめました。

https://zenn.dev/web_benriya/articles/bigquery-claude-code-monthly-business-report

#BigQuery #ClaudeCode