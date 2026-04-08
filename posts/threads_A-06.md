GA4のBigQueryデータ、UNNESTでつまずいていませんか？

event_paramsやitemsがネスト構造になっていて、
普通のSELECTでは中身が取れない。
GA4×BigQuery分析の最初の壁です。

実務で頻出する7つのUNNESTパターンをまとめました。

- 単一パラメータの取り出し方
- セッションIDの正しい構築方法
- eコマースitemsのCROSS JOIN展開
- トラフィックソースの新しい取得方法（非推奨フィールドに注意）
- stagingビューにまとめて再利用する設計

コピペで使えるSQLテンプレート集として整理しています。
分析の度にUNNESTで悩む時間を減らせるはずです。

https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns

#BigQuery #GA4
