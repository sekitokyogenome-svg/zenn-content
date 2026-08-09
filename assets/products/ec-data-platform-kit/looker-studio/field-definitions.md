# フィールド定義書

ダッシュボードが参照するビューと、その列の一覧。
Looker Studio 側のフィールド名はここに合わせる。

## `your_project.ec_dataset.products`（bigquery-ai-embed-ec-product-similarity__01.sql）

出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する

- （列エイリアスなし。ビュー定義を直接参照）

## `your_project.ec_dataset.product_embeddings`（bigquery-ai-embed-ec-product-similarity__02.sql）

出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する

- `content`
- `embedding`

## `${PROJECT}.${DATASET}.v_session_summary`（bigquery-bi-engine-looker-studio-speedup__01.sql）

出典: BigQueryのBI Engineを有効化してLooker Studioの表示速度を改善する

- `country`
- `device_category`
- `ga_session_id`
- `medium`
- `session_date`
- `source`

## `project.dataset_mart.mart_channel_roas`（bigquery-channel-roas-looker-studio__04.sql）

出典: チャネル別ROASをBigQueryで集計してLooker Studioに可視化する

- `cpa`
- `medium`
- `month`
- `purchases`
- `revenue`
- `roas_pct`
- `source`
- `spend`
- `users`

## `${PROJECT}.${DATASET}.v_linear_attribution`（bigquery-data-driven-attribution__03.sql）

出典: BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する

- `channel`
- `linear_attribution_score`
- `total_touchpoints`

## `${PROJECT}.${DATASET}.stg_sessions`（bigquery-data-lineage-datamart-dependency__01.sql）

出典: BigQueryのデータリネージ機能でデータマートの依存関係を可視化する

- `ga_session_id`
- `medium`
- `revenue`
- `source`

## `${PROJECT}.${DATASET}.mart_revenue_by_channel`（bigquery-data-lineage-datamart-dependency__02.sql）

出典: BigQueryのデータリネージ機能でデータマートの依存関係を可視化する

- `medium`
- `sessions`
- `source`
- `total_revenue`

## `${PROJECT}.${DATASET}.rfm_segments`（bigquery-ec-rfm-analysis-email-strategy__04.sql）

出典: BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた

- （列エイリアスなし。ビュー定義を直接参照）

## `your-project.mart.daily_sales`（bigquery-ec-seasonal-sales-prediction__01.sql）

出典: BigQueryでEC季節商品の売上予測モデルを作った話

- `daily_revenue`
- `sale_date`
- `transaction_count`
- `unique_buyers`

## `your-project.staging.sessions_202603`（bigquery-ga4-cost-query-optimization__07.sql）

出典: BigQueryでGA4データのコスト管理・クエリ最適化入門

- `medium`
- `session_id`
- `source`

## `your-project.staging.sessions_partitioned`（bigquery-ga4-cost-query-optimization__08.sql）

出典: BigQueryでGA4データのコスト管理・クエリ最適化入門

- `event_date_parsed`
- `medium`
- `session_id`

## `your_project.reporting.keyword_roas_monthly`（bigquery-google-ads-ga4-keyword-roas__04.sql）

出典: BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する

- （列エイリアスなし。ビュー定義を直接参照）

## `${PROJECT}.${DATASET}.v_roas_summary`（bigquery-looker-studio-cross-media-roas__02.sql）

出典: BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順

- `cost`
- `medium`
- `revenue`
- `roas`
- `source`

## `${PROJECT}.${DATASET}.mart_monthly_kpi`（bigquery-looker-studio-monthly-kpi-auto__01.sql）

出典: BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した

- `avg_order_value`
- `cvr`
- `device`
- `has_purchase`
- `medium`
- `month`
- `purchases`
- `revenue`
- `revenue_per_session`
- `session_id`
- `sessions`
- `source`
- `users`

## `${PROJECT}.${DATASET}.mart_monthly_kpi_with_ads`（bigquery-looker-studio-monthly-kpi-auto__02.sql）

出典: BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した

- `ad_cost`
- `cpa`
- `month`
- `roas`

## `${PROJECT}.${DATASET}.ec_user_features`（bigquery-ml-gemini-ec-purchase-prediction__02.sql）

出典: BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する

- （列エイリアスなし。ビュー定義を直接参照）

## `your-project.mart.mart_daily_sessions`（bigquery-partition-clustering-ga4-optimization__02.sql）

出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する

- `country`
- `device_category`
- `event_date`
- `ga_session_id`
- `session_medium`

## `your-project.mart.mart_daily_sessions`（bigquery-partition-clustering-ga4-optimization__03.sql）

出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する

- （列エイリアスなし。ビュー定義を直接参照）

## `your-project.mart.mart_sessions`（bigquery-partition-clustering-ga4-optimization__06.sql）

出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する

- `device_category`
- `event_date`
- `ga_session_id`
- `session_medium`

## `your-project.mart.mart_page_views`（bigquery-partition-clustering-ga4-optimization__07.sql）

出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する

- `device_category`
- `event_date`
- `page_path`

## `${PROJECT}.${DATASET}.session_mart`（bigquery-struct-array-ga4-modeling__05.sql）

出典: BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする

- `country`
- `device_category`
- `ep`
- `ga_session_id`
- `medium`
- `page_view_count`
- `purchase_count`
- `source`

## `${PROJECT}.${DATASET}.target_table`（bigquery-time-travel-data-recovery__02.sql）

出典: BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法

- （列エイリアスなし。ビュー定義を直接参照）

## `your_project.ml_dataset.user_item_interactions`（bigquery-vertex-ai-ec-recommendation__02.sql）

出典: BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話

- `interaction_score`
- `purchase_count`
- `view_count`

## `${PROJECT}.${DATASET}.unified_ad_performance`（claude-code-multi-ad-roas-comparison__01.sql）

出典: Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した

- `clicks`
- `conversion_value`
- `conversions`
- `cost`
- `impressions`
- `platform`

## `${PROJECT}.${DATASET}.v_return_rate_by_category`（ec-return-rate-ga4-bigquery-category__03.sql）

出典: ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した

- `item_category`
- `month`
- `purchase_count`

## `project.staging.stg_page_views`（ga4-bigquery-3layer-design__02.sql）

出典: GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】

- `page_location`
- `source`

## `project.mart.channel_summary`（ga4-bigquery-3layer-design__03.sql）

出典: GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】

- `conversions`
- `medium`
- `sessions`
- `source`

## `project.staging.stg_events`（ga4-bigquery-looker-studio-ec-analytics-full__01.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `country`
- `device_category`
- `event_date`
- `ga_session_id`
- `medium`
- `page_location`
- `page_title`
- `purchase_revenue`
- `source`
- `transaction_id`

## `project.staging.stg_sessions`（ga4-bigquery-looker-studio-ec-analytics-full__02.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `device_category`
- `ga_session_id`
- `has_add_to_cart`
- `has_purchase`
- `has_view_item`
- `is_session_start`
- `medium`
- `session_date`
- `session_revenue`
- `source`

## `project.staging.stg_purchases`（ga4-bigquery-looker-studio-ec-analytics-full__03.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `device_category`
- `ga_session_id`
- `medium`
- `purchase_date`
- `source`

## `project.mart.mart_traffic`（ga4-bigquery-looker-studio-ec-analytics-full__04.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `converting_sessions`
- `sessions`
- `total_revenue`

## `project.mart.mart_funnel`（ga4-bigquery-looker-studio-ec-analytics-full__05.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `add_to_cart_sessions`
- `month`
- `purchase_sessions`
- `total_sessions`
- `view_item_sessions`

## `project.mart.mart_cohort`（ga4-bigquery-looker-studio-ec-analytics-full__06.sql）

出典: GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順

- `activity_month`
- `cohort_month`
- `months_since_first`
- `returning_users`

## `your-project.staging.stg_sessions`（ga4-bigquery-session-id-definition__07.sql）

出典: GA4×BigQueryでセッションIDを正しく定義する方法

- `ga_session_id`
- `ga_session_number`
- `landing_page`
- `medium`
- `session_id`
- `source`

## `project.staging.stg_events`（ga4-bigquery-unnest-sql-patterns__08.sql）

出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集

- `city`
- `country`
- `device_category`
- `engagement_time_msec`
- `event_date`
- `medium`
- `page_location`
- `page_referrer`
- `page_title`
- `session_id`
- `source`

## `your_project.your_mart_dataset.mart_dashboard_daily`（looker-studio-bigquery-ec-dashboard-guide__01.sql）

出典: Looker Studio × BigQueryでEC売上ダッシュボードを1日で作る完全手順

- `aov`
- `cvr`
- `device_category`
- `medium`
- `revenue`
- `sessions`
- `source`
- `transactions`

## `${PROJECT}.${DATASET}.unified_ads_daily`（looker-studio-bigquery-google-meta-ads__01.sql）

出典: Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する

- `clicks`
- `conversion_value`
- `conversions`
- `impressions`
- `platform`
- `spend`

## `${PROJECT}.${DATASET}.ads_platform_comparison`（looker-studio-bigquery-google-meta-ads__02.sql）

出典: Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する

- `cpa`
- `cpc`
- `ctr`
- `cvr`
- `roas`
- `total_clicks`
- `total_conversion_value`
- `total_conversions`
- `total_impressions`
- `total_spend`

## `${PROJECT}.${DATASET}.mobile_dashboard_daily`（looker-studio-bigquery-mobile-optimized__01.sql）

出典: Looker Studio × BigQueryでスマホ最適化したダッシュボードを作る

- `cvr`
- `purchases`
- `revenue`
- `sessions`
- `users`

## `${PROJECT}.${DATASET}.unified_ads_performance`（looker-studio-custom-metrics-roas-cpa__02.sql）

出典: Looker Studioのカスタム指標でROAS・CPAを自動計算する設定

- `ad_cost`
- `clicks`
- `conversion_value`
- `conversions`
- `impressions`
- `platform`

## `${PROJECT}.${DATASET}.ec_sales_drilldown`（looker-studio-drilldown-ec-dashboard__01.sql）

出典: Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る

- `brand`
- `category`
- `device_type`
- `items`
- `medium`
- `product_name`
- `quantity`
- `revenue`
- `source`

## `${PROJECT}.${DATASET}.ec_sales_drilldown`（looker-studio-drilldown-ec-dashboard__02.sql）

出典: Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る

- `brand`
- `category`
- `device_type`
- `items`
- `medium`
- `product_name`
- `quantity`
- `revenue`
- `source`

## `your_project.mart.daily_summary`（looker-studio-slow-fix-bigquery-migration__01.sql）

出典: Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した

- `conversions`
- `device_category`
- `event_date`
- `medium`
- `page_views`
- `revenue`
- `sessions`
- `source`
- `users`

## `your_project.mart.daily_summary`（looker-studio-slow-fix-bigquery-migration__02.sql）

出典: Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した

- （列エイリアスなし。ビュー定義を直接参照）

## `your_project.ec_dataset.unified_sales`（rakuten-amazon-ec-bigquery-integration__01.sql）

出典: 楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法

- `channel`
- `order_date`
- `order_id`
- `price`
- `product_id`
- `product_name`
- `quantity`
- `revenue`
- `shipping_fee`
- `status`

## `your_project.ec_summary.monthly_revenue_202506`（small-ec-bigquery-free-tier-strategy__03.sql）

出典: 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略

- `ep`
- `medium`
- `purchase_count`
- `source`
- `total_revenue`

## `your_project.ads_dataset.unified_ads_stats`（yahoo-ads-bigquery-google-integrated-analysis__01.sql）

出典: Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法

- `campaign_name`
- `clicks`
- `conversions`
- `cost_jpy`
- `impressions`
- `media_source`
- `report_date`
