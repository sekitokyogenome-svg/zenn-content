「どの商品が在庫として眠り続けているのか、把握できていますか？」

商品点数が増えるほど、感覚的な在庫管理には限界があります。
GA4のBigQueryエクスポートデータと在庫データを組み合わせれば、商品別の在庫回転率を数字で可視化できます。

記事では以下を解説しています。

・在庫回転率の算式と読み方（回転率＝販売数量÷平均在庫数）
・GA4のBigQueryエクスポートからUNNEST(items)を使って商品別販売数量を取得するSQL
・在庫マスタとLEFT JOINして回転率を一括算出するSQL
・流入チャネル別（collected_traffic_source）に死に筋を掘り下げる方法
・Looker Studioで回転率ダッシュボードを構築する手順

回転率の低い商品＝キャッシュフローを圧迫する死に筋候補です。
まず直近1〜3ヶ月分を算出して、下位10〜20商品をリストアップするところから始めてみてください。

詳しくはこちら → https://zenn.dev/web_benriya/articles/ec-inventory-turnover-bigquery-product

#BigQuery #EC運営
