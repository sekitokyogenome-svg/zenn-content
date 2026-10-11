「データを見たいのに、毎回エンジニアにSQL依頼している」「自分で数字を確認できる環境がない」と感じていませんか。

BigQueryのConversational Analytics（会話型分析）を使うと、自然言語でデータを照会できるデータエージェントを構築できます。実装の要点をまとめました。

- Knowledge CatalogでテーブルとカラムにAIが読める説明を付与する
- BigQuery Studioのチャット欄から日本語で質問するだけでSQLが自動生成される
- APIを通じてSlackボットや社内Webアプリに組み込める
- instructionsパラメータにビジネスルールを記述して回答精度を高める
- セッションIDを引き継ぐことで「その中でROASが低い広告は？」という追加質問にも対応できる
- Claude Code × BigQuery MCPと組み合わせると多段階の自律分析も実現できる
- コスト上限をプロジェクト設定で制御することで想定外の課金を防げる

SQLを知らない経営者や事業担当者が自分でデータを照会できる環境が整えば、意思決定のスピードが変わります。具体的な実装手順はZennの記事にまとめました。

https://zenn.dev/web_benriya/articles/bigquery-conversational-analytics-data-agent

#BigQuery #データ分析
