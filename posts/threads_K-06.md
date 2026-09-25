CSの問い合わせテキストや商品レビュー、フォームの自由記述……これらを分析に使いたいのに、列に分解する前処理で手が止まっていませんか？

BigQueryのAI.GENERATE_TABLEを使うと、非構造化テキストを定義した列構成のテーブルに直接変換できます。

・問い合わせのカテゴリ・緊急度・商品名・要約を1つのSQLで同時に抽出
・AI.GENERATEのようにSTRUCTをパースする手間が不要
・結果がそのままGROUP BYやWHEREで使える通常の列として返ってくる
・TABLE SCHEMAのdescriptionに選択肢を書くだけで出力が安定する
・GA4のform_submitイベントと組み合わせてセッション文脈ごと構造化できる
・前段のWHERE絞り込み＋結果のマテリアライズでコストを抑える設計

「複数の情報を同時に取り出したい」ならAI.GENERATE_TABLE、「1列の生成・要約」ならAI.GENERATE、という使い分けが判断の基準になります。

テキストデータを分析に使えるかたちに変える具体的な実装手順を解説しています。

https://zenn.dev/web_benriya/articles/bigquery-ai-generate-table-structuring

#BigQuery #データ分析
