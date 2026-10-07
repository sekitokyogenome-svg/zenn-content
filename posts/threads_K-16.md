BigQueryのAI関数でSQLを書いたとき、分類結果が行によってバラバラになったり、JSON出力にコードフェンスが混入して後続クエリが壊れた経験はありませんか？

SQL内プロンプト設計のポイントをまとめました。

・チャットAIと違い、SQL内AI関数は数千〜数百万行を並列処理するため出力の安定が最優先
・出力形式の明示（「1つのみ出力」「説明文不要」）で余計な文字が入らなくなる
・分類タスクは AI.CLASSIFY の labels 指定が AI.GENERATE より安定する
・複数フィールドを返す場合は AI.GENERATE_TABLE の output_schema で型を強制する
・入力前処理（改行除去・文字数制限）でプロンプト構造の誤認を防ぐ
・LOWER(TRIM(...)) と LIKE 部分一致で後処理の揺れ吸収を設計する
・再現性が重要な分類・抽出タスクは temperature = 0 を指定する

SQL内プロンプト設計の5パターンとよくある失敗の対処法を実例とともに解説しています。

https://zenn.dev/web_benriya/articles/bigquery-ai-prompt-design-in-sql

#BigQuery #AI関数
