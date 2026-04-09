GA4×BigQueryで分析を始めたとき、
最初につまずくのが「セッションID」の扱いです。

GA4にはUAのようなセッションIDカラムがありません。
event_paramsの中にga_session_idとして埋まっています。

この記事では：
- UNNESTでga_session_idを正しく取り出す方法
- user_pseudo_id × ga_session_idで一意なセッションを定義する方法
- stagingビューに組み込んで再利用する設計

を実践的なSQLつきで解説しました。

セッション単位の分析をBigQueryで始める第一歩です。

https://zenn.dev/web_benriya/articles/ga4-bigquery-session-id-definition

#BigQuery #GA4
