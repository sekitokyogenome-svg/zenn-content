BigQueryでLLMを活用しようとして、「記事のとおりにやったら動かない」という経験はありませんか。

その原因の多くが、情報の世代ずれです。

・ML.GENERATE_TEXT（旧世代）はCREATE MODELでモデルオブジェクトを作る2段構え
・AI.*関数（新世代）はモデルオブジェクト不要、SELECT/WHEREに直接書けるスカラー関数
・スカラー関数になったことで「当てる前に絞れる」ため、コスト削減にも直結
・新規に書くなら迷わずAI関数。安定稼働中のML.GENERATE_TEXTは急いで移行不要
・移行する場合は並行稼働で結果を比較してから切り替える
・分類・判定系は影響が大きい。この機会にAI.CLASSIFYへの置き換えも検討できる

BigQueryのLLM活用で混乱している方は、まず世代の違いを整理するところから始めると詰まりにくくなります。

記事はこちら：https://zenn.dev/web_benriya/articles/bigquery-ml-generate-text-to-ai-functions

#BigQuery #GoogleCloud
