月次KPIレポートを作るたびに「数字は出せても、考察が書けない」と悩んでいませんか。

集計作業に追われてしまい、肝心の「なぜそうなったか」が後回しになりがちなのがKPIレポートの実態です。

本記事では、GA4のデータをBigQueryで集計し、Claude Codeに月次考察文まで生成させるプロンプト設計の考え方を解説しています。

記事のポイント：

・BigQueryでGA4セッションIDを正しく取得するUNNESTクエリの書き方
・流入元の判定にcollected_traffic_sourceを使う理由と具体SQL
・Claude Codeに考察を出力させるプロンプトの3要素（背景・データ・出力形式）
・目標値や異常値を一緒に渡すことで考察の精度を上げる方法
・対話的な追加質問でレポートを深掘りする実践的な使い方

数字を「並べる」だけのレポートから、意思決定に使える「考察付きレポート」に変えるための具体的な手順をまとめました。

まずは1チャネル分のデータだけに絞って試してみるところから始めてみてください。

https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design

#BigQuery #ClaudeCode
