-- 出典: P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法
-- 記事: articles/pmax-campaign-bigquery-analysis.md（Google広告データとの掛け合わせでCPAを算出する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- Google広告データとGA4データを日付・キャンペーンで結合するイメージ
-- ※ Data Transfer のテーブル名・スキーマは環境によって異なります
SELECT
  ads.campaign_name,
  ROUND(ads.cost_micros / 1000000, 0)              AS cost_jpy,
  ga.conversions,
  ROUND(
    (ads.cost_micros / 1000000) / NULLIF(ga.conversions, 0), 0
  )                                                AS cpa_jpy
FROM (
  SELECT
    campaign_name,
    SUM(cost_micros) AS cost_micros
  FROM `your_project.google_ads_transfer.p_Campaign_XXXXXXXXX`
  WHERE _PARTITIONDATE = '2024-07-31'
  GROUP BY campaign_name
) AS ads
LEFT JOIN (
  SELECT
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS conversions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = '20240731'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY source
) AS ga
ON TRUE  -- キャンペーン名でのJOINはUTM設定が必要
