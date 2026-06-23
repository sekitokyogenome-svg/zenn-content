「今月の売上は上がっているのに、なぜか手応えがない」と感じたことはありませんか。
前年同期と比べなければ、季節変動を排除した本当の成長は見えてきません。

BigQuery × Looker Studioで前年同期比（YoY）グラフを構築する方法をまとめました。

・Looker Studio標準機能では2本の折れ線を重ねた時系列表示が難しい
・BigQueryのCTEとJOINで今年・前年のデータを同じテーブルに横並びにする
・日別・月別それぞれのSQLパターンを掲載
・折れ線2本重ね・棒と折れ線の複合チャート・スコアカードの3種を解説
・日付パラメータ（@DS_START_DATE）で期間を動的に切り替え、クエリコスト削減にも有効
・うるう年・事業開始初年度・季節イベントずれへの対処法も収録

一度ビューを作成すれば、毎月の定例レポートで前年比確認が自動化されます。
ぜひご活用ください。

https://zenn.dev/web_benriya/articles/bigquery-looker-studio-yoy-comparison-chart

#BigQuery #LookerStudio
