「データエージェントを作ったのに、回答がブレる」「同じ質問でも毎回違う数字が返ってくる」という経験はありませんか。

BigQueryのデータエージェントは、instructionsパラメータの設計次第で回答精度が大きく変わります。実務で効果のあったパターンをまとめました。

- instructionsは「役割・用語定義・計算ルール・スコープ・出力形式」の5セクションで構成する
- ROASやLTVなど定義が複数あり得る指標は、分子・分母をSQLの計算式で明示する
- 「先月」「先週」などの曖昧な期間表現はDATE_TRUNCを使った具体的な定義に変換する
- GA4データを扱う場合はga_session_idのUNNEST取得と、collected_traffic_source.manual_mediumの使用を指示に明記する
- 除外条件（返品注文・テスト注文）を指示に書かないと、集計値が実態とズレる
- instructionsは800文字程度が効果と読み込み負荷のバランスが取れる目安
- instructionsを関数化してプロジェクト全体で一元管理すると、複数のエージェントで同じビジネスルールを共有できる

エージェントの出力がブレる原因の多くは、モデルの性能ではなく指示の設計にあります。具体的な書き方の例と失敗パターンはZennにまとめました。

https://zenn.dev/web_benriya/articles/bigquery-data-agent-instructions-tuning

#BigQuery #AIエージェント
