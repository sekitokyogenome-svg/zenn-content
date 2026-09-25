BigQueryのAI関数で「ポジティブか否か」「緊急度は何点か」を判定したいとき、結果を後続のSQLに使うためにテキストを数値や真偽値にパースする手間が発生していませんか。

AI.GENERATE_BOOL / AI.GENERATE_INT / AI.GENERATE_DOUBLEを使えば、その変換ステップを省けます。本記事では3つの型付き判定関数の使い方を実例で解説しています。

記事の主な内容：
・AI.GENERATE_BOOLでCS問い合わせのスパム判定やレビューのポジネガ判定をBOOL型で直接返す
・AI.GENERATE_INTで問い合わせ緊急度を1〜5の整数スコアで返し、そのままORDER BYに使う
・AI.GENERATE_DOUBLEで感情強度を0.0〜1.0で返し、商品別AVGをそのまま計算する
・GA4との組み合わせ：UNNEST(event_params)でga_session_idを取得し、流入チャネル別に緊急度を集計する実例
・AI.CLASSIFY / AI.IF / AI.SCOREとの使い分け判断フロー
・プロンプト短縮・前段フィルタ・結果のマテリアライズによるコスト最適化

型変換のパースエラーを避けながら、判定結果をSQLの条件式や集計に直接組み込む設計の参考にしてください。

https://zenn.dev/web_benriya/articles/bigquery-ai-generate-typed-functions

#BigQuery #データ分析
