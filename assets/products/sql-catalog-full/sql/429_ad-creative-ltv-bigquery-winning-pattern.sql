-- 429. 広告クリエイティブ別のLTVをBigQueryで追跡して勝ちパターンを見つける（クリエイティブ別LTVを集計するSQLクエリ）
-- 用途: クリエイティブ別LTVを集計するSQLクエリ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_session AS (
  -- （上記のfirst_sessionクエリをここに挿入）
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM (
    SELECT
      user_pseudo_id,
      collected_traffic_source.manual_medium   AS first_medium,
      collected_traffic_source.manual_source   AS first_source,
      collected_traffic_source.manual_campaign_name AS first_campaign,
      collected_traffic_source.manual_content  AS first_creative,
      MIN(event_timestamp) AS first_event_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY user_pseudo_id
        ORDER BY MIN(event_timestamp) ASC
      ) AS rn
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name = 'session_start'
      AND collected_traffic_source.manual_medium IS NOT NULL
    GROUP BY
      user_pseudo_id,
      first_medium,
      first_source,
      first_campaign,
      first_creative
  )
  WHERE rn = 1
),

-- 購買イベントの集計
purchases AS (
  SELECT
    user_pseudo_id,
    event_timestamp AS purchase_timestamp,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'transaction_id'
      LIMIT 1
    ) AS transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
    AND ecommerce.purchase_revenue IS NOT NULL
),

-- 初回流入情報と購買を結合してLTVを計算
user_ltv AS (
  SELECT
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source,
    COUNT(DISTINCT p.transaction_id)          AS purchase_count,
    ROUND(SUM(p.revenue), 2)                  AS total_revenue
  FROM first_session fs
  LEFT JOIN purchases p
    ON fs.user_pseudo_id = p.user_pseudo_id
  GROUP BY
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source
)

-- クリエイティブ別に集計
SELECT
  first_campaign,
  first_creative,
  first_medium,
  first_source,
  COUNT(DISTINCT user_pseudo_id)              AS user_count,
  SUM(purchase_count)                         AS total_orders,
  ROUND(AVG(total_revenue), 2)                AS avg_ltv_per_user,
  ROUND(SUM(total_revenue), 2)                AS total_revenue,
  ROUND(SUM(purchase_count) / NULLIF(COUNT(DISTINCT user_pseudo_id), 0), 2) AS avg_orders_per_user
FROM user_ltv
GROUP BY
  first_campaign,
  first_creative,
  first_medium,
  first_source
ORDER BY
  avg_ltv_per_user DESC;
