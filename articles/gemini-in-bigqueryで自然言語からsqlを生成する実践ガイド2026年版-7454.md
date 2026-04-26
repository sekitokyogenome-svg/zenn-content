

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery", "gemini", "ga4", "sql", "ai"]
published: false
---

## 「SQLが書けないから、GA4のデータを活用しきれない…」

EC担当者やマーケターの方から、こんな相談をよくいただきます。

- GA4の標準レポートでは見たい切り口のデータが出せない
- BigQueryにエクスポートしたけど、SQLが難しくて手が出ない
- ChatGPTでSQL生成を試したが、GA4のテーブル構造に合わず動かない

そんな課題を解決してくれるのが、**Gemini in BigQuery**です。BigQueryのコンソール上で自然言語を入力するだけで、**接続中のテーブルスキーマを理解した上で**SQLを生成してくれます。

この記事では、GA4 × BigQueryの実務で使えるGeminiプロンプト例と、生成されたSQLの検証ポイントを解説します。

## Gemini in BigQueryとは

Google CloudのBigQuery SQLワークスペースに統合されたAIアシスタント機能です。

**ChatGPTとの決定的な違い：**

| 比較項目 | ChatGPT等の外部AI | Gemini in BigQuery |
|---|---|---|
| テーブル構造の把握 | 手動で伝える必要あり | 自動で参照 |
| カラム名の正確性 | 幻覚（ハルシネーション）が多い | スキーマ準拠で生成 |
| 実行環境 | コピペが必要 | その場で実行可能 |

:::message
2025年現在、Gemini in BigQueryはGoogle Cloud コンソールの「BigQuery Studio」から利用できます。Duet AI時代の名称から統合・リブランドされています。
:::

## 実践：自然言語プロンプトからSQL生成

### ステップ1：BigQuery Studioを開く

BigQuery Studioのエディタ上部にあるGeminiアイコン（✨ペンマーク）をクリックし、自然言語入力モードに切り替えます。対象のGA4データセットを選択しておくことがポイントです。

### ステップ2：プロンプトを入力する

実務で使える3つのプロンプト例を紹介します。

**例1：チャネル別セッション数**

> `analytics_XXXXXXX.events_*` テーブルから、過去30日間のcollected_traffic_source.manual_mediumごとのセッション数を集計してください。セッションはuser_pseudo_idとga_session_idの組み合わせで一意とします。

生成されるSQLのイメージ：

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY medium
ORDER BY sessions DESC;
```

**例2：商品別の購入回数と売上**

> purchaseイベントからitemsを展開して、item_name別の購入回数と合計売上（price × quantity）を出してください。上位20件を売上降順で。

```sql
SELECT
  items.item_name,
  COUNT(*) AS purchase_count,
  SUM(items.price * items.quantity) AS total_revenue
FROM
  `project_id.analytics_XXXXXXX.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY items.item_name
ORDER BY total_revenue DESC
LIMIT 20;
```

**例3：ランディングページ別CVR**

> session_startイベントのpage_locationをランディングページとし、同一セッション内でpurchaseが発生した割合（CVR）をランディングページ別に算出してください。

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS landing_page
  FROM `project_id.analytics_XXXXXXX.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
conversions AS (
  SELECT DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `project_id.analytics_XXXXXXX.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
)
SELECT
  s.landing_page,
  COUNT(DISTINCT s.session_id) AS sessions,
  COUNT(DISTINCT c.session_id) AS conversions,
  SAFE_DIVIDE(COUNT(DISTINCT c.session_id), COUNT(DISTINCT s.session_id)) AS cvr
FROM sessions s
LEFT JOIN conversions c ON s.session_id = c.session_id
GROUP BY s.landing_page
HAVING sessions >= 10
ORDER BY cvr DESC;
```

## Gemini生成SQLの検証ポイント

AIが生成したSQLは、そのまま信用せず**3つの観点**でチェックしましょう。

:::message alert
Geminiが生成するSQLも間違うことがあります。特に以下の点は毎回確認してください。
:::

**1. セッション定義の正確性**
`ga_session_id`単体ではなく、`user_pseudo_id`との組み合わせで一意になっているか。

**2. _TABLE_SUFFIXの範囲**
日付フィルタが意図した期間になっているか。`intraday`テーブルを含めるべきか。

**3. UNNEST の有無**
`event_params`や`items`など、RECORD型フィールドを正しくUNNESTしているか。

## プロンプトのコツ

Geminiの精度を上げるために、プロンプトに以下を含めると効果的です。

- **テーブル名を明示する**（`analytics_XXXXXXX.events_*`）
- **セッション定義を指定する**（user_pseudo_id + ga_session_id）
- **期間を具体的に書く**（「過去30日」「2025年5月」など）
- **出力カラム名を指定する**（曖昧さを排除できる）

## まとめ

Gemini in BigQueryを使えば、SQLの専門知識がなくてもGA4データの高度な分析に挑戦できます。ただし、GA4特有のネスト構造やセッション定義の理解は依然として重要です。AIが生成したSQLを「読めて・検証できる」レベルを目指しましょう。

---

:::message
**「BigQuery×GA4の分析環境を整えたいけど、何から手をつければいいかわからない」**という方へ。

GA4のBigQueryエクスポート設定から、実務で使えるSQLテンプレートの構築、Looker Studioでの可視化まで、ココナラでワンストップ支援しています。

👉 [GA4×BigQuery分析のご相談はこちら](https://coconala.com/services/1791205)
:::
```