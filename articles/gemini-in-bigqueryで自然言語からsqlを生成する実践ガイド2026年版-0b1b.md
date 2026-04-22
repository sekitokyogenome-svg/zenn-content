

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery", "gemini", "ga4", "sql", "ai"]
published: false
---

## 「SQLが書けないから、GA4データを活用しきれない…」

ECサイトを運営していて、GA4のデータはBigQueryにエクスポートしている。でも、分析のたびにSQLを調べて書くのが大変——。そんな悩みを抱えるマーケターの方は多いのではないでしょうか。

2025年後半にGA化したGemini in BigQueryを使えば、**日本語で質問するだけでSQLが自動生成**されます。本記事では、EC分析の実務で使える具体的なプロンプトとSQLの検証方法を解説します。

## Gemini in BigQueryとは

BigQueryのコンソール上で利用できるAIアシスタント機能です。自然言語で「〇〇を集計して」と入力すると、対象テーブルのスキーマを読み取り、SQLクエリを自動生成してくれます。

:::message
2026年1月現在、Gemini in BigQueryはGoogle Cloud コンソールのBigQuery Studio内で利用可能です。Gemini Code Assist のサブスクリプション、またはBigQuery向けGemini機能の有効化が必要です。
:::

## 実践①：チャネル別セッション数を自然言語で取得

### プロンプト例

BigQuery Studioの入力欄に以下のように書きます。

```
analytics_XXXXXXX.events_* テーブルから、
過去7日間のチャネル（manual_medium）別のセッション数を集計してください。
セッションはuser_pseudo_idとga_session_idの組み合わせで識別します。
```

### Geminiが生成するSQL（例）

```sql
SELECT
  collected_traffic_source.manual_medium AS channel,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND collected_traffic_source.manual_medium IS NOT NULL
GROUP BY
  channel
ORDER BY
  sessions DESC;
```

生成されたSQLはそのまま実行できますが、**必ず内容を確認してから実行**してください。

## 実践②：購入コンバージョン率をページ別に算出

### プロンプト例

```
GA4のBigQueryテーブルから、
過去30日間でpage_viewイベントが多い上位20ページについて、
各ページを閲覧したセッションのうちpurchaseイベントが発生した割合（CVR）を算出してください。
```

### 生成されたSQLの検証ポイント

Geminiが生成するSQLは高精度ですが、GA4特有の構造で注意すべき点があります。

:::message alert
**よくあるGemini生成SQLの落とし穴**
1. `event_params` の UNNEST を忘れて `page_location` を直接参照しようとする
2. セッションIDの構築で `ga_session_id` ではなく `ga_session_number` を使ってしまう
3. `_TABLE_SUFFIX` の日付フォーマットが `YYYY-MM-DD` になっている（正しくは `YYYYMMDD`）
:::

修正が必要な場合は、Geminiに「ga_session_idはevent_paramsの中にあります。UNNESTして取得してください」と追加で指示すると、正しく修正されます。

## 実践③：LTV分析用のSQL生成

ECで特に重要なLTV（顧客生涯価値）分析もプロンプト一つで対応できます。

### プロンプト例

```
過去90日間のpurchaseイベントから、
ユーザーごとの購入回数・合計売上・初回購入日・最終購入日を算出し、
購入回数が多い順に上位100ユーザーを表示してください。
売上はevent_paramsのvalueキーから取得してください。
```

### 生成SQL（例）

```sql
SELECT
  user_pseudo_id,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS total_revenue,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_purchase_date,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_purchase_date
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'purchase'
GROUP BY
  user_pseudo_id
ORDER BY
  purchase_count DESC
LIMIT 100;
```

## Geminiに正確なSQLを書かせる3つのコツ

| # | コツ | 具体例 |
|---|------|--------|
| 1 | **テーブル名を明示する** | `analytics_XXXXXXX.events_*` と正確に指定 |
| 2 | **GA4のデータ構造を補足する** | 「event_paramsはネストされた配列です」と添える |
| 3 | **集計ロジックを定義する** | 「セッション＝user_pseudo_id + ga_session_id」と明記 |

プロンプトが曖昧だと、Geminiは一般的なテーブル構造を前提としたSQLを生成します。GA4 BigQueryの独特なスキーマ（ネスト構造・`_TABLE_SUFFIX` によるシャーディング）は、**プロンプト内で明確に伝える**のがポイントです。

## まとめ

- Gemini in BigQueryを使えば、日本語の指示だけでGA4分析用SQLを生成できる
- ただしGA4特有のネスト構造やフィールド名は、プロンプトで補足すると精度が上がる
- 生成されたSQLは鵜呑みにせず、フィールド名・日付フォーマット・UNNEST処理を確認する

SQLの自動生成は便利ですが、「正しい問いを立てる力」と「生成結果を検証する力」は依然として人間の仕事です。AIをうまく活用して、データドリブンなEC運営を実現しましょう。

---

:::message
「GA4×BigQueryの初期設定がまだ…」「Geminiを使ってみたいけど環境構築が不安…」という方へ。GA4のBigQueryエクスポート設定からAI分析環境の構築まで、ココナラでサポートしています。
👉 [GA4・BigQuery・AI活用のご相談はこちら](https://coconala.com/services/1791205)
:::
```