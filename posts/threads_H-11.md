複数の広告媒体を運用していても、Google広告とYahoo!広告のレポートを別々の管理画面で確認していませんか。

媒体をまたいだ予算配分を感覚ではなくデータで判断するために、BigQueryへの統合データ基盤を構築する方法をまとめました。

記事の内容

・Yahoo!広告データをBigQueryに取り込む3つの方法（手動CSV／APIスクリプト／ETLサービス）を比較
・Google広告×Yahoo!広告を横断集計できる統合ビューの設計方針とSQL例
・媒体別CPA・CTR・CVRを1本のSQLで比較するクエリパターン
・GA4のBigQueryエクスポートと掛け合わせ、広告流入ユーザーのサイト内行動まで分析する方法
・collected_traffic_source.manual_mediumを使ったYahoo!流入の正確な絞り込み方

まずは既存のGA4 BigQueryエクスポートと手動アップロードしたYahoo!広告CSVを統合ビューで結合するだけでも、媒体間比較の精度が大きく変わります。

詳細はこちらからご覧ください。
https://zenn.dev/web_benriya/articles/yahoo-ads-bigquery-google-integrated-analysis

#BigQuery #広告運用
