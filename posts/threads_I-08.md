GA4のコンバージョン数値と実際の売上が合わない——その原因を特定できていますか？

EC事業者がBigQueryでGA4×受注データを結合して正確な売上帰属分析を実現する方法を解説しました。

・GA4単体では「確定受注」の実態を把握しにくい理由
・キャンセル・決済失敗が含まれるGA4コンバージョンの限界
・受注管理システムのデータをBigQueryに取り込む手順
・ga_session_idとuser_pseudo_idを結合キーにするSQLの実装
・collected_traffic_source.manual_mediumで流入元を正確に取得
・LEFT JOINで電話注文など未計測分も漏らさず集計する設計
・Looker Studioで流入経路別売上ダッシュボードを構築する方法

広告ROASを正確に算出するための第一歩として、まず受注テーブルにGA4のIDが保存されているかを確認してみてください。

https://zenn.dev/web_benriya/articles/bigquery-ec-order-ga4-revenue-attribution

#BigQuery #GA4
