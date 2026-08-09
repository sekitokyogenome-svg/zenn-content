-- ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した
-- 用途: LookerStudioでダッシュボード化して継続モニタリング
-- 必要テーブル: events_*, v_return_rate_by_category
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_return_rate_by_category` AS
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
GROUP BY
  month, item_category
;
