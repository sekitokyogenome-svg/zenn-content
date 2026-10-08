BigQueryのAI関数を使い始めたら、月末に想定外の請求が届いた経験はありませんか？

AI.GENERATEやAI.CLASSIFYはトークン単位の課金モデルです。
通常のBigQueryのスキャン課金とは仕組みが異なるため、既存の感覚では管理できません。

今回の記事では、コストを膨らませない設計パターンを整理しました。

・全件処理は禁物。WHEREで対象を絞ってからAI関数を実行する
・プロンプトは簡潔に。AI.CLASSIFYなど専用関数を優先して使う
・max_output_tokensを設定して出力トークンの上限を管理する
・処理結果をキャッシュテーブルに保存し、再実行を防ぐ
・軽量モデルで事前スクリーニングし、高精度モデルの使用を最小化する
・INFORMATION_SCHEMAでAI関数のコスト動向を日次で監視する

AI関数は設計次第でコストを大幅に抑えられます。
規模感の目安と具体的なSQLも記事で公開しています。

https://zenn.dev/web_benriya/articles/bigquery-ai-functions-cost-optimization

#BigQuery #GoogleCloud
