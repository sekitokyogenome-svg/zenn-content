「類似商品を探したい」「意味的に近いレビューをまとめたい」というEC事業のデータ処理をSQLだけで完結させられることをご存知でしょうか？

AI.EMBEDを使えば、テキストをベクトルに変換し、VECTOR_SEARCHで意味の近いデータを検索できます。新しい記事を公開しました。

記事の内容：
・AI.EMBEDとAI.GENERATE_EMBEDDINGの違いと使い分け
・task_typeの種類（RETRIEVAL_DOCUMENT／RETRIEVAL_QUERY／CLUSTERING等）と選び方
・商品説明文をベクトル化してテーブルに保存するSQL
・GA4サイト内検索キーワードをベクトル化する実装例
・VECTOR_SEARCHで類似テキストを検索する方法
・VECTOR_INDEXを作成して大規模テーブルで高速化する手順
・カスタマーレビューをクラスタリング用にベクトル化する応用例
・「ユニーク値に絞る」「差分だけ更新」「結果を再利用」のコスト削減設計

ベクトル検索は専門的に聞こえますが、BigQueryのAI関数を使えばSQLの中で完結します。類似商品レコメンドや問い合わせのクラスタリングを自社データで試したい方の参考になれば幸いです。

https://zenn.dev/web_benriya/articles/bigquery-ai-embedding-generation

#BigQuery #データ分析
