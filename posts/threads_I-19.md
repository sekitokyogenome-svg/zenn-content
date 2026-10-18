自社ECサイトの「サイト速度が遅い」は本当にCVRを下げているのか、数字で確かめられていますか？

感覚ではなく、Googleが公開しているリアルユーザーの速度データ（CrUX）とGA4のBigQueryエクスポートを組み合わせれば、定量的な検証が可能です。

記事では以下の手順を解説しています。

・CrUX（Chrome User Experience Report）をBigQueryで無料取得する方法
・LCP（最大コンテンツ描画）の良好・要改善・不良の割合をSQLで算出する
・GA4のBigQueryエクスポートでセッション単位のCVRを月次集計する
・速度の変化とCVRの変化を月次で並べてbefore/after比較する
・スマートフォン限定の速度データで、モバイルCVRへの影響を切り分ける
・改善インパクトの大きいページ（商品一覧・カートなど）の特定方法

CrUXはPageSpeed Insightsと同じフィールドデータが元になっており、ツールの数値との照合も容易です。SQLの基礎知識があれば今日から実践できます。

速度改善の効果は数値で追えてこそ意味があります。まずは現状のLCP水準を把握するところから始めてみてください。

https://zenn.dev/web_benriya/articles/ec-site-speed-cvr-bigquery-crux

#BigQuery #ECサイト改善
