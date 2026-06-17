「広告費を使って新規顧客を獲得しているが、チャネルごとのCACを正確に把握できているか？」EC事業において、CAC（顧客獲得コスト）を媒体別に算出できると、広告予算の配分精度が大きく変わります。

GA4×BigQueryを使ってCACを媒体別に計算する方法を解説しました。

・「新規顧客」の定義：Cookieベース、初回purchaseイベント、CRMデータとの比較
・分析期間内で初めてpurchaseが発生したユーザーを新規顧客として特定するSQL
・collected_traffic_sourceを使ったチャネル別（Paid Search／Social／Email等）の分類
・広告費データを手動CTEまたはGoogle Sheets外部テーブルで結合してCACを算出
・LTV:CAC比率（3:1以上が健全の目安）でチャネルの投資対効果を評価する方法
・Google広告・Instagram・TikTokなど媒体別の予算配分判断への活用例

月次でCACを追跡してLooker Studioで可視化しておくと、広告効率の変化にすぐに気づける体制が整います。

詳細はこちらからご覧ください。
https://zenn.dev/web_benriya/articles/ga4-bigquery-cac-by-channel

#GA4 #BigQuery
