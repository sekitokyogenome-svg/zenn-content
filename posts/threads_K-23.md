BigQueryで機械学習モデルを作ろうとして、特徴量のSQLが複雑すぎて手が止まった経験はありませんか？

BigQueryのData Science Agentを使うと、自然言語で指示するだけで特徴量エンジニアリングからモデル学習・評価まで一通り進められます。

今回の記事では、EC購買データを使ったリピート購入予測モデルを例に、次の手順を解説しています。

・データ概要の把握と特徴量の設計方針をAgentに伝える
・目的変数（90日以内のリピート購入）と説明変数のSQL生成を指示する
・BigQuery ML（LOGISTIC_REG）でのモデル学習をAgentに実行させる
・精度・再現率・AUCを確認し、実務で使えるレベルかどうかをAgentが判断する
・特徴量重要度（ML.GLOBAL_EXPLAIN）で「初回購入金額が最も効く」ことを可視化する
・新規ユーザーへの予測実行と結果テーブルへの保存まで自然言語で完結させる

SQLの構文を調べる手間が減り、特徴量設計とモデル解釈の判断に集中できるようになります。

BigQuery MLの活用を検討している方に、実務で使えるプロンプトとSQL例を交えて解説しています。ぜひご覧ください。

https://zenn.dev/web_benriya/articles/bigquery-data-science-agent-workflow

#BigQuery #機械学習
