「GA4でオーガニック検索を分析しようとすると、キーワードがほぼ見えない」という状況に悩んでいませんか？

GA4単体では検索クエリの大半が（not provided）になります。しかし、Search ConsoleのBigQueryエクスポートと結合することで、この問題を解消できます。

記事で解説している内容：

- Search ConsoleをBigQueryにエクスポートする設定手順
- searchdata_url_impressionテーブルの構造と主要カラム
- キーワード別・ランディングページ別のSEOパフォーマンス集計SQL
- GA4のセッションデータとSearch Consoleを日付×URLで結合するクエリ
- 「検索クリックは多いがCVRが低いページ」など改善優先度の見つけ方
- URLの正規化方法（クエリパラメータ除去）と日付ずれへの対処

GA4の行動データ×Search Consoleのキーワードデータを組み合わせることで、SEO施策の優先順位付けに使える分析基盤が構築できます。

SQLテンプレートをそのままコピーしてお使いいただけます。

https://zenn.dev/web_benriya/articles/ga4-bigquery-search-console-organic

#BigQuery #SEO対策
