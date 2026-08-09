-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（値の型に応じた取得方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 文字列型
(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'plan_type') AS plan_type

-- 整数型
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'item_count') AS item_count

-- 浮動小数点型
(SELECT value.float_value FROM UNNEST(event_params) WHERE key = 'scroll_depth') AS scroll_depth

-- double型
(SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'score') AS score
