毎朝GA4のダッシュボードを手動で開いて数字を確認する作業、まだ続けていますか？

Claude Code × BigQuery MCP × Slack Webhookを組み合わせることで、GA4の主要指標を毎朝Slackに自動通知する仕組みを構築しました。

記事で解説している内容はこちらです。

・BigQuery MCPサーバーの設定方法（settings.jsonへの追記手順）
・前日比を含むチャネル別セッション数・CV数・売上を取得するSQLクエリ
・Claude APIでクエリ結果をビジネス向け日本語サマリーに変換する実装
・Slack Webhookでフォーマット済みメッセージを送信するPythonスクリプト
・Cloud Schedulerで毎朝7時に自動実行する設定手順

ダッシュボードを開く手間がなくなるだけでなく、AIが前日比の変化点を自動でハイライトするため、売上・流入の異変に気づくスピードも上がります。

GA4×BigQueryのレポート自動化に取り組んでいる方は、ぜひ参考にしてみてください。

https://zenn.dev/web_benriya/articles/claude-code-mcp-ga4-slack-daily-report

#GA4 #BigQuery
