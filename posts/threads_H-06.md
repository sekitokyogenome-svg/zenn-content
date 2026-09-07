LINE広告を出稿しているのに「本当に効果が出ているのか」が数字で把握できていませんか？

LINE広告の管理画面とGA4の数値が合わない、CPAやROASが算出できない——このような状況を解消するための設定と集計SQLをまとめました。

・LINE広告のリンクにUTMパラメータ（utm_source=line / utm_medium=cpc）を付与し、GA4で流入元を正しく識別する
・GA4のBigQueryエクスポートを有効化し、イベントデータをSQLで自由に集計できる環境を整える
・ga_session_idはUNNEST(event_params)経由で取得し、collected_traffic_source.manual_mediumで流入元を絞り込む
・LINE広告経由のセッションと購入イベントをセッションIDで結合し、コンバージョン数・売上・CPA・ROASを算出するSQLを紹介
・Looker StudioのBigQueryコネクタと組み合わせることで、毎月の広告効果を自動でダッシュボード化できる

広告費の投資判断を数値に基づいて行えるようになると、予算の最適化も仮説検証もスピードが変わります。

まずはUTMパラメータの設定とBigQueryエクスポートの有効化から着手してみてください。

https://zenn.dev/web_benriya/articles/line-ads-ga4-bigquery-cpa-roas

#GA4 #BigQuery
