Google広告のROAS、管理画面の数値を信じていませんか？

・Google広告の管理画面とGA4の数値はしばしば乖離する
・ラストクリック帰属への依存が、本当に貢献しているキーワードを隠している
・売上ではなく粗利で評価しないと、黒字キーワードが見えてこない
・BigQueryにGA4データとGoogle広告データを集約すれば、キーワード単位で正確なROASを算出できる
・UNNEST(event_params)でga_session_idを展開し、collected_traffic_sourceで流入元を判定するのがポイント
・FULL OUTER JOINで広告費とGA4売上を結合することで、どちらかにしか存在しないキーワードも漏れなく把握できる
・BigQueryビューとして保存すればLooker Studioでのダッシュボード化も容易

キーワードの費用対効果を「感覚」ではなく「データ」で判断したい方にとって、実装可能なSQLテンプレートを含む解説記事です。

https://zenn.dev/web_benriya/articles/bigquery-google-ads-ga4-keyword-roas

#GoogleAds #BigQuery
