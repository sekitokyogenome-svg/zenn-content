---
title: "BigQuery だけで GA4 風の EC ダミーデータを作る — 重複購入と NULL を仕込んで SQL を検証する"
emoji: "🧪"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql", "ga4"]
published: false
publish_queue: true
---

## この記事でわかること

- 外部ツールを使わず、BigQuery の SQL だけで GA4 エクスポート風の EC イベントを生成する方法
- 重複購入・`transaction_id` の NULL など、集計を壊す罠をあえて仕込み、期待値を `ASSERT` で固定するやり方
- 生成してから SQL を流すまでにつまずいた点（パーティション指定、スキーマ不足、ワイルドカードの落とし穴）

## 前提

- BigQuery のプロジェクトと、データセットを作れる権限
- 費用: この記事のデータは13,417行・論理サイズ約4MB（テーブル情報の値）です。クエリのスキャン量もその範囲に収まり、無料枠（毎月1TiBのクエリ処理、10GiBのストレージ。[公式料金表](https://cloud.google.com/bigquery/pricing)）に収まる規模です。ご自身の課金設定は事前に確認してください
- この記事のデータはすべて**架空**です。実在のストアの数値ではありません

## なぜダミーデータが要るのか

GA4 の BigQuery エクスポートを前提にした SQL は、本番のデータに流す前に「間違った結果が出ていないか」を確かめたくなります。公開データセット `bigquery-public-data.ga4_obfuscated_sample_ecommerce` もありますが、2020-11〜2021-01 の期間のデータ（[公式](https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset)）で、新しい項目（`session_traffic_source_last_click` など）は入っていない可能性があります（自分では確認していません）。

自前で作るもう一つの利点は、**答えを自分で決められる**ことです。重複購入を5件仕込めば、「重複を除いた購入は何件のはずか」が先に分かります。SQL が正しいかどうかを、期待値との一致で判定できます。

## 設計: 決定的に生成して、罠と期待値を先に決める

乱数は `RAND()` ではなく `FARM_FINGERPRINT` で作ります。同じ入力から同じ値が出るため、何度流しても同じデータになり、期待値を固定できます。

仕込んだ罠は次の4つです。

| 罠 | 内容 | 狙い |
|---|---|---|
| T1 | 同一 `transaction_id` の purchase を5件複製 | 重複排除の有無で売上が変わるか |
| T2 | `transaction_id` が NULL の purchase を9件 | NULL の扱いで購入数がズレないか |
| T3 | `ga_session_id` をユーザー間で衝突させる | `user_pseudo_id` と組にして数えているか |
| T4 | `purchase_revenue` は円、`purchase_revenue_in_usd` は USD | 通貨を取り違えないか |

## 生成 SQL

2026-09-01〜09-30 の1か月分を作ります。流入元は google/cpc・google/organic・direct・yahoo/cpc・newsletter/email の5種で、流入元ごとにカート追加率を変えています。

```sql
-- 架空の GA4 EC 風イベントを生成する（FARM_FINGERPRINT で決定的）
CREATE OR REPLACE TABLE `logical-web.dummy_ga4_ec.events_all`
OPTIONS (description='架空データ。実データではない') AS
WITH s AS (
  SELECT d, i,
    1 + MOD(ABS(FARM_FINGERPRINT(CONCAT('u', d, '-', i))), 2500) AS uid,
    1700000000 + MOD(ABS(FARM_FINGERPRINT(CONCAT('g', d, '-', i))), 200) AS ga_session_id,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('c', d, '-', i))), 100) AS rc,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('v', d, '-', i))), 100) AS rv,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('a', d, '-', i))), 100) AS ra,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('b', d, '-', i))), 100) AS rb,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('p', d, '-', i))), 100) AS rp,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('k', d, '-', i))), 12) AS sku,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('q', d, '-', i))), 2) + 1 AS qty,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('t', d, '-', i))), 50000) AS sec
  FROM UNNEST(GENERATE_ARRAY(0, 29)) AS d,
       UNNEST(GENERATE_ARRAY(1, 160)) AS i
  WHERE MOD(ABS(FARM_FINGERPRINT(CONCAT('n', d, '-', i))), 100) < 85
),
s2 AS (
  SELECT *,
    CASE WHEN rc < 20 THEN 'google' WHEN rc < 50 THEN 'google' WHEN rc < 75 THEN '(direct)'
         WHEN rc < 85 THEN 'yahoo' ELSE 'newsletter' END AS src,
    CASE WHEN rc < 20 THEN 'cpc' WHEN rc < 50 THEN 'organic' WHEN rc < 75 THEN '(none)'
         WHEN rc < 85 THEN 'cpc' ELSE 'email' END AS med,
    CASE WHEN rc < 20 THEN 'brand_search' WHEN rc < 50 THEN '(organic)' WHEN rc < 75 THEN '(direct)'
         WHEN rc < 85 THEN 'ly_ads_sale' ELSE 'mail_autumn' END AS camp,
    -- 流入元ごとにカート追加率を変える（direct高め / organic低め）
    CASE WHEN rc < 20 THEN 30 WHEN rc < 50 THEN 20 WHEN rc < 75 THEN 45 WHEN rc < 85 THEN 15 ELSE 40 END AS p_atc,
    1000 + sku * 700 AS price
  FROM s
),
stages AS (
  SELECT s2.*, st.name, st.ord FROM s2, UNNEST([
    STRUCT('session_start' AS name, 0 AS ord), STRUCT('page_view', 1),
    STRUCT('view_item', 2), STRUCT('add_to_cart', 3),
    STRUCT('begin_checkout', 4), STRUCT('purchase', 5)]) AS st
  WHERE st.ord <= 1
     OR (st.ord = 2 AND rv < 80)
     OR (st.ord = 3 AND rv < 80 AND ra < p_atc)
     OR (st.ord = 4 AND rv < 80 AND ra < p_atc AND rb < 60)
     OR (st.ord = 5 AND rv < 80 AND ra < p_atc AND rb < 60 AND rp < 70)
),
base AS (
  SELECT *,
    FORMAT_DATE('%Y%m%d', DATE_ADD(DATE '2026-09-01', INTERVAL d DAY)) AS event_date,
    UNIX_MICROS(TIMESTAMP(DATE_ADD(DATE '2026-09-01', INTERVAL d DAY))) + (sec + ord * 40) * 1000000 AS ts,
    CONCAT('T', FORMAT('%02d', d), '-', FORMAT('%03d', i)) AS txn
  FROM stages
)
SELECT
  event_date,
  ts + ord AS event_timestamp,
  name AS event_name,
  [STRUCT('ga_session_id' AS key, STRUCT(CAST(NULL AS STRING) AS string_value, CAST(ga_session_id AS INT64) AS int_value, CAST(NULL AS FLOAT64) AS float_value, CAST(NULL AS FLOAT64) AS double_value) AS value),
   STRUCT('page_location', STRUCT(CONCAT('https://shop.example.invalid/', IF(ord >= 2, CONCAT('item/SKU-', FORMAT('%02d', sku)), ''), '?utm_source=', src), NULL, NULL, NULL)),
   STRUCT('currency', STRUCT('JPY', NULL, NULL, NULL))] AS event_params,
  CONCAT('dummy_', FORMAT('%05d', uid)) AS user_pseudo_id,
  CAST(NULL AS STRING) AS user_id,
  STRUCT(IF(MOD(uid, 10) < 6, 'mobile', 'desktop') AS category) AS device,
  STRUCT('Japan' AS country) AS geo,
  STRUCT(src AS source, med AS medium, camp AS name) AS traffic_source,
  STRUCT(src AS manual_source, med AS manual_medium, camp AS manual_campaign_name, CAST(NULL AS STRING) AS gclid) AS collected_traffic_source,
  STRUCT(
    IF(med IN ('cpc','email'),
       STRUCT(CAST(NULL AS STRING) AS campaign_id, camp AS campaign_name, src AS source, med AS medium, CAST(NULL AS STRING) AS term, CAST(NULL AS STRING) AS content, CAST(NULL AS STRING) AS source_platform),
       CAST(NULL AS STRUCT<campaign_id STRING, campaign_name STRING, source STRING, medium STRING, term STRING, content STRING, source_platform STRING>)) AS manual_campaign,
    STRUCT(CAST(NULL AS STRING) AS campaign_id, camp AS campaign_name, src AS source, med AS medium, 'Manual' AS source_platform,
           CASE med WHEN 'cpc' THEN 'Paid Search' WHEN 'organic' THEN 'Organic Search' WHEN 'email' THEN 'Email' ELSE 'Direct' END AS default_channel_group) AS cross_channel_campaign
  ) AS session_traffic_source_last_click,
  IF(name = 'purchase',
     STRUCT(IF(MOD(i, 37) = 0, CAST(NULL AS STRING), txn) AS transaction_id,
            CAST(price * qty AS FLOAT64) AS purchase_revenue,
            ROUND(price * qty / 150, 2) AS purchase_revenue_in_usd,
            qty AS total_item_quantity),
     CAST(NULL AS STRUCT<transaction_id STRING, purchase_revenue FLOAT64, purchase_revenue_in_usd FLOAT64, total_item_quantity INT64>)) AS ecommerce,
  IF(ord >= 2,
     [STRUCT(CONCAT('SKU-', FORMAT('%02d', sku)) AS item_id, CONCAT('ダミー商品', FORMAT('%02d', sku)) AS item_name, CAST(price AS FLOAT64) AS price, qty AS quantity)],
     CAST([] AS ARRAY<STRUCT<item_id STRING, item_name STRING, price FLOAT64, quantity INT64>>)) AS items
FROM base;
```

その後、T1（重複購入）を追加します。

```sql
-- 同じ transaction_id の purchase を5件だけ複製する
INSERT INTO `logical-web.dummy_ga4_ec.events_all`
SELECT * FROM `logical-web.dummy_ga4_ec.events_all`
WHERE event_name = 'purchase' AND ecommerce.transaction_id IS NOT NULL
ORDER BY ecommerce.transaction_id LIMIT 5;
```

※ 上の SQL では、プロジェクト名 `logical-web` と データセット名 `dummy_ga4_ec` を使っています。自分の環境に置き換えてください。

## 期待値を ASSERT で固定する

生成した直後に、仕込んだ罠の件数をその場で検証します。

```sql
-- 生成結果が想定どおりか確かめる（失敗すると例外になる）
ASSERT (SELECT COUNT(*) FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_name='session_start') = 4058 AS 'sessions';
ASSERT (SELECT COUNT(*) FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 443 AS 'purchase rows incl. dups';
ASSERT (SELECT COUNT(DISTINCT ecommerce.transaction_id) FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 429 AS 'distinct txn';
ASSERT (SELECT COUNTIF(ecommerce.transaction_id IS NULL) FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 9 AS 'null txn';
ASSERT (SELECT SUM(ecommerce.purchase_revenue) FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 3238700 AS 'raw revenue';
```

購入は443行で、重複を除いた `transaction_id` は429種、NULL が9件、重複込みの売上合計は 3,238,700 円です。

## 日別テーブルに分割する

実際のエクスポートは `events_YYYYMMDD` の日別テーブルです。SQL 側を `events_*` と `_TABLE_SUFFIX` で書くために、同じ形に分割します。

```sql
-- events_all を events_YYYYMMDD の日別テーブルに分割する
FOR r IN (SELECT DISTINCT event_date AS d FROM `logical-web.dummy_ga4_ec.events_all`) DO
  EXECUTE IMMEDIATE FORMAT(
    "CREATE OR REPLACE TABLE `logical-web.dummy_ga4_ec.events_%s` AS SELECT * FROM `logical-web.dummy_ga4_ec.events_all` WHERE event_date = '%s'",
    r.d, r.d);
END FOR;
```

## つまずいた点

1. **`PARTITION BY` に文字列の日付は使えない**: `event_date` は STRING（`'20260901'` の形）なので、`PARTITION BY PARSE_DATE('%Y%m%d', event_date)` はエラーになります。この規模ならパーティションは不要なので外しました
2. **`cross_channel_campaign` が無くて SQL が失敗した**: 最初は `session_traffic_source_last_click` に `manual_campaign` だけを入れていました。`cross_channel_campaign.medium` を参照する SQL は「フィールドが存在しない」でエラーになります。SQL の誤りではなく、ダミー側のスキーマ不足でした。上の生成 SQL は、`cross_channel_campaign` を加えた後の形です
3. **`events_*` は `events_all` も拾う**: ワイルドカードは `events_all` にも一致します（`_TABLE_SUFFIX` は `all`）。`_TABLE_SUFFIX BETWEEN '20260901' AND '20260930'` のように日付で絞れば除外されます。本物のエクスポートの `events_intraday_*` も同じ理由で日付で絞るのが安全です
4. **読み取り専用のツールでは `DECLARE` が使えない**: 自分が使った BigQuery 連携ツールの読み取り専用モードでは、`DECLARE` を含むスクリプトが「SELECT 文のみ許可」というエラーで実行できませんでした（BigQuery 自体の仕様ではなく、そのツールの制限です）。パラメータを使う SQL は、書き込み可能な実行経路で流しました

## このデータで確かめられること

罠があるおかげで、次のような確認ができます。

- 購入を `transaction_id` で重複排除しないと、売上が 3,238,700 円のまま。排除すると 3,197,400 円になる
- セッションを `ga_session_id` だけで数えると、衝突分だけ過少になる（`user_pseudo_id` と組にすると、4,058セッションが4,046に畳まれる。ユーザー内で衝突した12件ぶんです）
- 流入元別の購入率に差があるので、チャネル別 CVR の SQL が差を拾えているかを見られる

実際に、このデータでアトリビューションや LTV 予測の SQL を流して、構文エラーや配分合計の不一致がないか確認できました。

## 限界

- 本物の GA4 エクスポートとは異なります。日別シャードと `events_all` を併用しており、`events_intraday_*` や、多くの項目（`user_properties`、`app_info` など）はありません
- 乱数は決定的ですが、実データの偏り（曜日差、季節性、ロングテール）は再現していません。CVR や LTV の「値」の妥当性を見るためには使えません。確認できるのは、SQL が動くか・罠を踏まないかです

## まとめ

- BigQuery の SQL だけで、GA4 風の EC データを決定的に作れる
- 重複購入・NULL・ID の衝突を仕込み、期待値を `ASSERT` で固定すると、SQL の検証が機械的になる
- 本番データに流す前の動作確認に使い、数値の妥当性は本番データで見る

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
