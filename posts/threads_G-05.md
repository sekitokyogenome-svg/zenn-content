GA4のデータを毎日確認しているのに、異常値が出たとき「なぜ？」の特定に半日かかっていませんか。

Claude CodeとBigQueryを組み合わせれば、異常値の検知から原因仮説の出力まで自動化できます。

この記事でご紹介している内容：

・GA4のBigQueryエクスポートで流入元×日別のセッション数・CVRを集計するSQL設計
・ga_session_idはUNNEST経由、流入元はcollected_traffic_sourceで取得する正しい書き方
・Claude Codeに渡すプロンプトの3つの核心（判定基準の数値明示・3カテゴリの仮説・確認方法の同時出力）
・出力された仮説を変動幅と影響規模で優先順位づけする実践的な考え方
・PythonスクリプトでBigQuery→Claude API→Slack通知まで全自動化するサンプルコード

コピーして使えるSQLとプロンプトテンプレートを整理しています。BigQueryに慣れていない方でもそのまま試せます。

毎週月曜の朝に先週の異常値サマリーが手元に届く運用体制を、まず小さく始めてみることをお勧めします。

記事はこちら → https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt

#GA4分析自動化 #ClaudeCode
