GA4の管理画面だけでは、会員ランクや施策バリアントといった「ビジネス固有の切り口」での分析はできません。
BigQueryを使えば、その制約を一気に突破できます。

今回の記事では、GA4×BigQueryでカスタムディメンションを活用した実践的な分析手法を解説しています。

・イベントスコープ（event_params）とユーザースコープ（user_properties）の違いと取得方法
・文字列・整数・浮動小数点など、値の型に応じたUNNESTパターン
・ABテストのバリアント別CVR比較を行うSQL
・会員ランク別の行動分析（セッション数・カート追加・購入）を集計するSQL
・最新のuser_propertiesを正確に取得するROW_NUMBER活用パターン
・「どのカスタムディメンションが入っているか」を確認する探索クエリ

GA4の標準レポートでは見えなかった数値が、BigQueryでは手に取るようにわかります。
分析設計の前に、まず「何が入っているか」を確認するクエリを走らせることをお勧めします。

https://zenn.dev/web_benriya/articles/ga4-bigquery-custom-dimensions

#GA4 #BigQuery
