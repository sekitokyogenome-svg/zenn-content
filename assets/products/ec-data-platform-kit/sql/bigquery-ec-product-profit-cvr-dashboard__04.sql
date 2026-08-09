-- BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った
-- 用途: 4象限マトリクスで優先度を整理する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  item_id,
  item_name,
  cvr,
  gross_margin_pct,
  CASE
    WHEN cvr >= 3.0 AND gross_margin_pct >= 40 THEN '最優先投資'
    WHEN cvr >= 3.0 AND gross_margin_pct < 40 THEN '改善不要（維持）'
    WHEN cvr < 3.0 AND gross_margin_pct >= 40 THEN 'CVR改善'
    ELSE '撤退検討'
  END AS quadrant
FROM product_profit
ORDER BY quadrant, gross_profit DESC;
