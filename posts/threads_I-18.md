「売上は伸びているのに、手元にお金が残らない」——その原因、チャネル別の粗利率で見えてきませんか？

EC事業で陥りがちなのが、売上高だけを追いかけて収益性の差を見落とすことです。
商品単位・流入チャネル単位で粗利率を把握することで、以下が実現できます。

・Instagram広告経由は粗利率5%、自然検索経由は45%——同じ商品でもこれほどの差がある
・広告予算の配分を見直すだけで収益構造を改善できる
・GA4のBigQueryエクスポートとcollected_traffic_sourceで流入元を正確に取得
・UNNEST(event_params)でga_session_idを取得し、注文IDと突合
・社内の売上・原価テーブルとBigQueryで結合し、商品×チャネル別にSAFE_DIVIDEで粗利率を算出
・Looker Studioのピボットテーブル＋ヒートマップで「ゴールデンゾーン」「レッドゾーン」を一目で可視化
・スケジュールクエリで毎朝自動更新も可能

詳細なSQL付きで解説しています。自社データへの適用方法もぜひご確認ください。

https://zenn.dev/web_benriya/articles/ec-gross-margin-bigquery-product-channel

#BigQuery #EC事業
