BigQueryのAI.GENERATE、「引数が多くてどれを設定すべきかわからない」という声をよく聞きます。実は押さえるべきポイントは3つだけです。

今回の記事では、AI.GENERATEの仕様を実務目線で整理しました。

- temperatureは分類タスクなら0.0が基本。高い値が有効な場面はほぼない
- max_output_tokensはタスクごとに絞る。分類なら1桁で十分、無駄に大きくしない
- 戻り値はSTRUCT。candidates[0].contentを取り出す書き方を覚えれば7割の場面に対応できる
- GA4のga_session_idはUNNEST経由で取得、流入元はcollected_traffic_sourceを使う
- 結果はCREATE TABLE ASでマテリアライズして再利用する。これがコスト管理の基本
- AI.CLASSIFYやAI.IFで足りない場面でのみAI.GENERATEに降りる、という順序が効率的

マネージド関数との使い分けからコスト設計まで、よくあるトラブルの対処も含めてまとめています。

詳細はこちらからご覧ください。
https://zenn.dev/web_benriya/articles/bigquery-ai-generate-complete-guide

#BigQuery #GoogleCloud
