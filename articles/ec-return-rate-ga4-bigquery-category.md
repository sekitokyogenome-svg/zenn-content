---
title: "ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した"
emoji: "↩️"
type: "idea"
topics: ["bigquery","googleanalytics","ec","sql","lookerstudio"]
published: false
---

## はじめに

ECサイトを運営していると、売上の数字だけでなく「返品率」が経営の足を引っ張っているケースに気づくことがあります。「先月も返品対応に追われた」「特定の商品だけ返品が多い気がする」という感覚はあるものの、正確にどのカテゴリで・どの流入経路から来たユーザーが返品しやすいのかを把握できていない事業者は少なくありません。

返品は単なるコストではなく、「購入前後のギャップ」を示すシグナルです。サイズ感の説明不足なのか、商品画像と実物の乖離なのか、特定の広告経由のユーザーが期待値を高く持ちすぎているのか——原因によって対策がまったく異なります。

本記事では、GA4のBigQueryエクスポートとSQLを組み合わせて、商品カテゴリ別の返品率を可視化し、原因の仮説を立てるところまでの手順を紹介します。エンジニアでなくても手順を追えるよう、SQLは丁寧に解説しますので、ぜひ参考にしてみてください。

## GA4で返品イベントを計測する設計

分析の前提として、GA4に「返品」を示すカスタムイベントが送信されていることが必要です。ECプラットフォームによって返品データの取得方法は異なりますが、一般的には以下の2つのアプローチがあります。

**アプローチ1: 返品申請フォームの完了をイベントとして送信する**
返品申請ページに `return_request_complete` のようなカスタムイベントを設置し、`item_id`・`item_category`・`order_id` などをパラメータとして渡します。

**アプローチ2: バックエンドの返品処理をMeasurement Protocol経由でGA4に送信する**
受注管理システムで返品が確定したタイミングで、Measurement ProtocolからGA4にイベントを送る方法です。精度が高く、後から処理された返品も漏れなく計測できます。

どちらの方法でも、以下のパラメータをイベントに含めておくと、後のBigQuery分析がスムーズになります。

| パラメータ名 | 例 | 役割 |
|---|---|---|
| item_category | `tops` / `shoes` | カテゴリ別集計に使用 |
| item_id | `SKU-12345` | 商品単位の分析に使用 |
| order_id | `ORD-98765` | 購入イベントとの紐づけ |
| return_reason | `size_mismatch` | 返品理由の分類 |

:::message
GA4の標準eコマースイベント（`purchase`）にも `item_category` フィールドが含まれます。返品イベントにも同じ値を渡すことで、BigQuery上での結合が容易になります。
:::

## BigQueryで商品カテゴリ別の返品率を集計するSQL

GA4のデータをBigQueryにエクスポートしている場合、以下のSQLで商品カテゴリ別の購入数・返品数・返品率を集計できます。

```sql
WITH
-- 購入イベントをカテゴリ別に集計
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS purchase_count
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
  GROUP BY
    item_category
),

-- 返品イベントをカテゴリ別に集計
returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS return_count
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
  GROUP BY
    item_category
)

SELECT
  p.item_category,
  p.purchase_count,
  COALESCE(r.return_count, 0) AS return_count,
  ROUND(SAFE_DIVIDE(COALESCE(r.return_count, 0), p.purchase_count) * 100, 2) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.item_category = r.item_category
WHERE
  p.item_category IS NOT NULL
ORDER BY
  return_rate_pct DESC
;
```

`SAFE_DIVIDE` を使うことでゼロ除算のエラーを回避しています。また、`COALESCE` で返品がないカテゴリも `0` として表示されるようにしています。

このクエリを実行すると、たとえば以下のような結果が得られます。

| item_category | purchase_count | return_count | return_rate_pct |
|---|---|---|---|
| shoes | 1,240 | 186 | 15.00 |
| outerwear | 980 | 127 | 12.96 |
| tops | 3,100 | 248 | 8.00 |
| bottoms | 2,450 | 147 | 6.00 |

この例では、`shoes`（靴）と `outerwear`（アウター）の返品率が突出して高いことが分かります。

## 返品率が高いカテゴリの流入元を深掘りする

カテゴリ別の返品率が把握できたら、次は「どの流入経路から来たユーザーが返品しやすいのか」を確認します。同じカテゴリでも、SNS広告経由と自然検索経由では購入者の温度感が異なることがあるためです。

以下のSQLでは、`collected_traffic_source` を使って流入元ごとの返品率を集計しています。

```sql
WITH
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
),

returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
)

SELECT
  p.item_category,
  p.medium,
  p.source,
  COUNT(DISTINCT p.order_id) AS purchase_count,
  COUNT(DISTINCT r.order_id) AS return_count,
  ROUND(
    SAFE_DIVIDE(COUNT(DISTINCT r.order_id), COUNT(DISTINCT p.order_id)) * 100, 2
  ) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.order_id = r.order_id
WHERE
  p.item_category IN ('shoes', 'outerwear')   -- 返品率が高いカテゴリに絞る
  AND p.item_category IS NOT NULL
GROUP BY
  p.item_category, p.medium, p.source
ORDER BY
  p.item_category, return_rate_pct DESC
;
```

:::message
`ga_session_id` はイベントのトップレベルフィールドとして直接参照することはできません。`UNNEST(event_params)` を経由して `key = 'ga_session_id'` の値を取得する必要があります。
:::

このクエリの結果として、たとえば「靴カテゴリはInstagram広告（medium: paid_social）経由の返品率が特に高い」といった傾向が見えてくることがあります。その場合、広告クリエイティブや商品LP上のサイズ感の説明が不十分である可能性が考えられます。

## LookerStudioでダッシュボード化して継続モニタリング

一度きりの分析で終わらせず、毎月・毎週の返品率推移をモニタリングする仕組みを作るとより効果的です。BigQueryのクエリ結果をLookerStudio（旧データポータル）に接続することで、視覚的なダッシュボードを無料で作成できます。

**LookerStudioとの連携手順（概要）**

1. LookerStudio（[lookerstudio.google.com](https://lookerstudio.google.com)）を開き、新しいレポートを作成する
2. データソースとして「BigQuery」を選択し、集計済みのビューまたはクエリを指定する
3. 棒グラフや折れ線グラフを使って「カテゴリ別返品率」「月次推移」「流入元別比較」を配置する

```sql
-- BigQueryにビューとして保存しておくと、LookerStudioから繰り返し参照できる
CREATE OR REPLACE VIEW `your_project.your_dataset.v_return_rate_by_category` AS
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_count
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
GROUP BY
  month, item_category
;
```

ビューを作成しておくと、LookerStudio側でフィルタや期間指定を柔軟に変えながら分析できます。ダッシュボードを月次レビュー資料として活用することで、施策の効果検証サイクルも回しやすくなります。

## まとめ

本記事では、GA4とBigQueryを組み合わせてECの返品率を商品カテゴリ別・流入元別に分析する手順を紹介しました。要点を整理します。

- **GA4への返品イベント設計が基盤**：`item_category`・`order_id` などのパラメータを最初から設計に組み込むことが、後の分析精度を左右します
- **カテゴリ別集計で「問題カテゴリ」を特定**：全体の平均に埋もれていた返品率の高いカテゴリが浮かび上がります
- **流入元のクロス分析で原因の仮説を立てる**：SNS広告と自然検索では購入者のペルソナが異なり、返品率に差が出るケースがあります
- **LookerStudioで継続モニタリング**：一度作ったビューを活用し、月次・週次で返品率を追う習慣が改善サイクルを加速させます

次のアクションとしては、まず自社のGA4に返品イベントが正しく設定されているかを確認することをお勧めします。BigQueryエクスポートが有効であれば、本記事のSQLをベースに集計を試してみてください。データを見ることで、感覚だけに頼らない返品対策の議論が社内でできるようになります。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [チャネル別ROASをBigQueryで集計してLooker Studioに可視化する](https://zenn.dev/web_benriya/articles/bigquery-channel-roas-looker-studio)
- [BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った](https://zenn.dev/web_benriya/articles/bigquery-ec-product-profit-cvr-dashboard)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
