-- 424. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（BigQueryでカスタムチャネルグループを定義する）
-- 用途: BigQueryでカスタムチャネルグループを定義する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TEMP FUNCTION classify_channel(
  source STRING, medium STRING, page_referrer STRING
) AS (
  CASE
    WHEN REGEXP_CONTAINS(COALESCE(page_referrer, ''),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai')
      THEN 'AI Search'
    WHEN source = 'chatgpt' AND medium = 'ai-search' THEN 'AI Search'
    WHEN medium = 'organic' THEN 'Organic Search'
    WHEN medium = 'cpc' THEN 'Paid Search'
    WHEN medium = 'referral' THEN 'Referral'
    WHEN medium = '(none)' AND source = '(direct)' THEN 'Direct'
    ELSE 'Other'
  END
);
