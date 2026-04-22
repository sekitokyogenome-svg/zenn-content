GA4の「平均エンゲージメント時間」、BigQueryで正しく集計できていますか？
探索レポートの数値だけに頼ると、実態とかけ離れた判断につながることがあります。

BigQueryでGA4のページ別滞在時間を集計する際のポイントをまとめました。

・GA4の滞在時間はengagement_time_msecパラメータで記録される
・event_paramsのネスト構造に格納されているため、UNNESTによる展開が必要
・engagement_time_msec > 0 でフィルタし、不要なレコードを除外する
・user_engagementが未発火のケースはLEADによるタイムスタンプ差分で補完できる
・セッション全体の滞在時間は合計値・平均値・中央値を組み合わせて把握する
・engagement_time_msecとタイムスタンプ差分は用途に応じて使い分けるのが実務的なアプローチ

記事内ではそのまま使えるSQLテンプレートを掲載しています。
GA4データをBigQueryで本格活用したい方のご参考になれば幸いです。

https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page

#GA4 #BigQuery
