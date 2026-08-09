---
title: "ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果"
emoji: "⭐"
type: "idea"
topics: ["bigquery","ec","sql","googleanalytics","datanalysis"]
published: false
---

## はじめに

「レビューが増えれば売れる」とはよく言われますが、実際に自社ECのデータで検証したことはありますか？

感覚的には理解できても、「レビューが何件以上になると転換率が変わるのか」「どの商品カテゴリでレビューの影響が大きいのか」といった具体的な数字を把握できているケースは多くありません。特に中小ECでは、レビュー施策の優先度が低く置かれがちで、定量的な根拠なしに運用されているケースも見受けられます。

本記事では、GA4のBigQueryエクスポートデータとECの受注データを組み合わせて、商品レビュー数と売上・転換率の関係を定量的に分析する方法をSQLとともに解説します。分析の考え方と読み方についても丁寧に説明しますので、SQLに不慣れな方もぜひ最後までお読みください。

## なぜBigQueryで分析するのか

GA4の管理画面でも商品ごとのPV数やカート追加数は確認できます。しかし、「レビュー件数」という外部データとGA4の行動データを掛け合わせて分析しようとすると、標準レポートではすぐに限界を迎えます。

BigQueryを使うメリットは大きく3点あります。

1. **柔軟なデータ結合**：ECシステムのレビューデータとGA4の行動ログを、商品IDをキーに結合できます。
2. **過去データへの遡及**：GA4の管理画面では直近90日程度が中心ですが、BigQueryエクスポートを設定していれば数年分のデータを一括分析できます。
3. **セグメント別の深掘り**：「流入元×レビュー数×転換率」のような多次元分析も、SQLを書くだけで実現できます。

初期設定の手間はかかりますが、一度基盤を整えると繰り返し活用できるため、データドリブンな施策判断が格段にやりやすくなります。

## 前提となるデータ準備

本記事では、以下の2つのデータソースが利用可能であることを前提とします。

- **GA4のBigQueryエクスポートデータ**（`your_project.analytics_XXXXXXXX.events_*`）
- **ECシステムから抽出した商品マスタ＋レビューサマリーテーブル**（`your_project.ec_data.product_reviews`）

レビューサマリーテーブルには、少なくとも以下のカラムが含まれている想定です。

| カラム名 | 内容 |
|---|---|
| item_id | 商品ID（GA4のitem_idと一致させる） |
| review_count | 総レビュー件数 |
| avg_rating | 平均評価点 |
| category | 商品カテゴリ |

GA4のBigQueryエクスポートがまだ設定されていない場合は、GA4の管理画面から「BigQueryのリンク設定」を行ってください（無料枠の範囲内で利用できます）。

## SQLで商品ごとの転換率とレビュー数を集計する

まず、GA4データから商品ページの閲覧数・カート追加数・購入数を商品IDごとに集計します。`ga_session_id` はイベントパラメータとして格納されているため、`UNNEST(event_params)` 経由で取得する点に注意してください。

```sql
WITH session_base AS (
  SELECT
    event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value
     FROM UNNEST(items)
     LIMIT 1) AS item_id
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'add_to_cart', 'purchase')
),

item_funnel AS (
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'add_to_cart') AS cart_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM session_base
  WHERE item_id IS NOT NULL
  GROUP BY item_id
)

SELECT
  f.item_id,
  f.view_count,
  f.cart_count,
  f.purchase_count,
  SAFE_DIVIDE(f.purchase_count, f.view_count) AS view_to_purchase_rate,
  r.review_count,
  r.avg_rating,
  r.category
FROM item_funnel f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
ORDER BY f.view_count DESC
LIMIT 200;
```

このクエリで得られた結果を、BigQueryのエクスポートからスプレッドシートやLooker Studioに取り込むことで、視覚的に傾向を掴むことができます。

## レビュー件数を段階別に区切って比較する

転換率の違いをわかりやすく見るには、レビュー件数を「0件」「1〜4件」「5〜9件」「10件以上」などの段階に区切って比較するのが有効です。

```sql
WITH item_funnel AS (
  -- 前節のitem_funnelクエリをここに入れる
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM (
    SELECT
      event_name,
      (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
    FROM `your_project.analytics_XXXXXXXX.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name IN ('view_item', 'purchase')
  )
  WHERE item_id IS NOT NULL
  GROUP BY item_id
),

joined AS (
  SELECT
    f.item_id,
    f.view_count,
    f.purchase_count,
    r.review_count,
    r.category,
    CASE
      WHEN r.review_count = 0          THEN '0件'
      WHEN r.review_count BETWEEN 1 AND 4  THEN '1〜4件'
      WHEN r.review_count BETWEEN 5 AND 9  THEN '5〜9件'
      WHEN r.review_count >= 10        THEN '10件以上'
      ELSE '不明'
    END AS review_bucket
  FROM item_funnel f
  LEFT JOIN `your_project.ec_data.product_reviews` r
    ON f.item_id = r.item_id
)

SELECT
  review_bucket,
  COUNT(DISTINCT item_id)                           AS item_count,
  SUM(view_count)                                   AS total_views,
  SUM(purchase_count)                               AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchase_count), SUM(view_count)) * 100, 2) AS cvr_pct
FROM joined
GROUP BY review_bucket
ORDER BY
  CASE review_bucket
    WHEN '0件'   THEN 1
    WHEN '1〜4件' THEN 2
    WHEN '5〜9件' THEN 3
    WHEN '10件以上' THEN 4
    ELSE 5
  END;
```

このクエリを実行すると、例えば以下のような傾向が見えてきます（あくまで一例であり、自社データでの結果は異なります）。

| レビュー件数 | 対象商品数 | 平均CVR |
|---|---|---|
| 0件 | 120 | 0.8% |
| 1〜4件 | 85 | 1.4% |
| 5〜9件 | 40 | 2.1% |
| 10件以上 | 25 | 3.2% |

このような数値が出た場合、「10件以上のレビューがある商品のCVRは0件商品の約4倍程度高い傾向にある」という定性的な仮説を、自社データで裏付けることができます。

:::message
SQLの `SAFE_DIVIDE` 関数はゼロ除算を防ぐためのものです。`purchase_count / view_count` と書くとview_countが0のときにエラーになるため、BigQueryでは必ず `SAFE_DIVIDE` を使うことをお勧めします。
:::

## 流入元別にレビュー効果の差を見る

レビューの効果は、流入元によって異なる場合があります。たとえば自然検索（SEO）流入のユーザーはすでに購買意欲が高いため、レビューの有無に関わらず転換しやすい傾向があります。一方、SNS広告流入のユーザーは比較検討段階にいることが多く、レビューによる信頼醸成が転換に大きく影響することがあります。

以下のSQLでは、GA4の `collected_traffic_source` を使って流入元を取得します（`event_params` の `medium` ではなく、セッションレベルで付与される `collected_traffic_source` フィールドを使用します）。

```sql
WITH session_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
  FROM `your_project.analytics_XXXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'purchase')
),

funnel_by_traffic AS (
  SELECT
    COALESCE(medium, '(none)') AS medium,
    item_id,
    COUNTIF(event_name = 'view_item')  AS views,
    COUNTIF(event_name = 'purchase')   AS purchases
  FROM session_traffic
  WHERE item_id IS NOT NULL
  GROUP BY medium, item_id
)

SELECT
  f.medium,
  CASE
    WHEN r.review_count = 0        THEN '0件'
    WHEN r.review_count < 5        THEN '1〜4件'
    WHEN r.review_count < 10       THEN '5〜9件'
    ELSE '10件以上'
  END AS review_bucket,
  COUNT(DISTINCT f.item_id)                                        AS item_count,
  SUM(f.views)                                                     AS total_views,
  SUM(f.purchases)                                                 AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(f.purchases), SUM(f.views)) * 100, 2)     AS cvr_pct
FROM funnel_by_traffic f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
GROUP BY f.medium, review_bucket
ORDER BY f.medium, review_bucket;
```

このクエリの結果から、「自社のどの流入チャネルでレビューの効果が大きいか」を把握できます。レビュー獲得施策に使えるリソースが限られている場合、効果が高いチャネルに注力するという判断もできます。

## まとめ

本記事では、GA4のBigQueryエクスポートデータとECのレビューデータを組み合わせて、商品レビュー数と転換率の関係を定量的に分析する方法を解説しました。

要点を整理します。

- **BigQueryを使うことで**、GA4の標準レポートでは難しい「外部データとの結合」や「長期間の横断分析」が実現できます。
- **レビュー件数を段階別に集計すること**で、「何件を超えると効果が出やすいか」という施策設計の根拠が得られます。
- **流入元別の分析を加えること**で、レビュー施策の優先度付けがより精緻になります。

次のアクションとして、まずはGA4のBigQueryエクスポートを設定し、本記事のSQLを自社データで試してみることをお勧めします。テーブル名やカラム名を自社の構成に合わせて調整するだけで、同様の分析が再現できます。定量的なエビデンスをもとにレビュー獲得施策を立案することで、施策の効果測定も格段にしやすくなります。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
