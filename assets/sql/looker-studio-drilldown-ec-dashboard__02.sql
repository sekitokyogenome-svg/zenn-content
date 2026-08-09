-- 出典: Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る
-- 記事: articles/looker-studio-drilldown-ec-dashboard.md（NULL値の対策をする）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

IFNULL(items.item_category, '未分類') AS category,
IFNULL(items.item_brand, 'ノーブランド') AS brand
