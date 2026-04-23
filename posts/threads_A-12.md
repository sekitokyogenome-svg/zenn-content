「この広告、最初の接点はどこだったのか」を正確に把握できていますか？

GA4の標準レポートでは、ファーストタッチとラストタッチを比較する機能がありません。BigQueryにエクスポートしたデータとウィンドウ関数を組み合わせることで、チャネルごとの貢献を正確に可視化できます。

今回の記事では以下の内容を解説しています。

- ファーストタッチ（認知チャネル）とラストタッチ（刈り取りチャネル）の違い
- collected_traffic_source と traffic_source の使い分け
- FIRST_VALUE を使ったファーストタッチ取得SQL
- LAST_VALUE を使ったラストタッチ取得SQL
- 両者を並べてチャネルの役割を比較する実践的なクエリ設計

「Organic Searchで認知されて、Paid Searchで購入される」パターンが多いのか、そうでないのか。データを見るだけで広告予算配分の議論が変わります。

SQLテンプレートをそのまま使えるよう実例形式で掲載しています。

https://zenn.dev/web_benriya/articles/ga4-bigquery-first-touch-last-touch

#GA4 #BigQuery
