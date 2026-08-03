BigQueryにデータがあるのに、SQLが書けなくて活用できていませんか？
Gemini in BigQueryを使えば、日本語でやりたい分析を入力するだけでSQLを生成できます。

記事で解説している内容をまとめると、

・Gemini in BigQueryはSQL生成・説明・エラー修正をコンソール上でサポートするAI機能
・プロンプトに集計軸・期間・並び順を明示すると生成精度が上がる
・GA4データのga_session_idはUNNEST(event_params)経由でないと取得できない
・流入チャネルはcollected_traffic_source.manual_medium/manual_sourceを使う
・生成されたSQLはテーブル名・日付範囲・集計ロジックを人の目で確認してから実行する
・うまく動いたSQLをテンプレートとしてチームで蓄積すると効率が上がる

「AIが書いた下書きを人が確認・修正する」というプロセスを大切にすることが、精度の高い分析につながります。
まずは小さな分析から試してみてください。

https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026

#BigQuery #GeminiAI
