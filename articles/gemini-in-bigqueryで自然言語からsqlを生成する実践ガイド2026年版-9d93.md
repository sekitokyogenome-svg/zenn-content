

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】"
emoji: "🤖"
type: "tech"
topics: ["BigQuery", "GA4", "Gemini", "SQL", "AI"]
published: false
---

## 「SQLが書けないから、GA4のデータを活かしきれない…」

ECサイトを運営していて、GA4とBigQueryの連携は済んでいる。でも、いざ分析しようとするとSQLの壁にぶつかる――そんな悩みを抱えていませんか？

2025年後半からBigQuery上で使えるGeminiのSQL生成機能が大幅に強化され、**自然言語で質問するだけで実用的なSQLが生成される**時代になりました。本記事では、EC担当者がすぐに使える実践的なプロンプトとワークフローを紹介します。

## Gemini in BigQueryとは

BigQueryコンソール右上の「Gemini」アイコン、またはSQL入力欄で **ペンアイコン（SQL生成）** をクリックすると、自然言語でクエリを指示できます。

主なできること：
- 自然言語 → SQL自動生成
- 既存SQLの説明・修正提案
- テーブルスキーマの自動参照

:::message
Gemini in BigQueryを使うには、Google CloudプロジェクトでGemini for Google Cloud APIを有効にし、適切なIAMロール（`roles/aiplatform.user`等）が必要です。
:::

## 実践①：日本語プロンプトでGA4データを分析する

### ケース1：チャネル別の売上集計

BigQueryのSQL入力欄で以下のように入力します。

**プロンプト例：**
> GA4のBigQueryエクスポートテーブルから、過去30日間のチャネル別セッション数と購入収益を集計して

Geminiが生成するSQLの例（必要に応じて手動で微調整）：

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
      )
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `project_id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
purchases AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
      )
    ) AS session_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `project_id.analytics_XXXXXXX.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)
SELECT
  IFNULL(s.medium, '(none)') AS channel_medium,
  COUNT(DISTINCT s.session_id) AS sessions,
  IFNULL(SUM(p.revenue), 0) AS total_revenue
FROM
  sessions s
LEFT JOIN
  purchases p ON s.session_id = p.session_id
GROUP BY
  channel_medium
ORDER BY
  total_revenue DESC;
```

### ケース2：商品カテゴリ別CVR

**プロンプト例：**
> 商品カテゴリ別に、商品詳細ページの閲覧数と購入完了数、CVRを出して

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
  COUNTIF(event_name = 'view_item') AS view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNTIF(event_name = 'view_item')
  ) AS cvr
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name IN ('view_item', 'purchase')
GROUP BY
  item_category
HAVING
  view_count > 0
ORDER BY
  cvr DESC;
```

## 精度を上げる3つのプロンプトのコツ

Geminiが生成するSQLの精度は、プロンプトの書き方で大きく変わります。

### 1. テーブル名を明示する

```
テーブル `project_id.analytics_XXXXXXX.events_*` を使って…
```

プロジェクト内にテーブルが多いと、Geminiが意図しないテーブルを参照する場合があります。

### 2. 期間・条件を具体的に書く

```
❌ 最近のデータから
✅ 2025年6月1日〜6月30日のデータから
```

### 3. 出力カラムを指定する

```
✅ セッションID、チャネル、購入金額の3列で出力して
```

:::message alert
Geminiが生成したSQLは**必ず目視で確認**してから実行してください。特にGA4のネストされたフィールド（`event_params`や`items`）のUNNEST処理は、意図しない行の膨張が起きることがあります。
:::

## 実践②：生成されたSQLをClaude Codeで改良する

Geminiで生成した「おおよそ正しいSQL」を、ローカルのClaude Codeでリファクタリングする運用もおすすめです。

```bash
# Claude Codeにファイルを渡して改良を依頼
claude "このGA4のSQLを、セッションスコープで正確にCVRを計算するように修正して。
UNNESTによる行膨張も防いで。" < query.sql
```

**Gemini × Claudeの使い分け：**
| 用途 | ツール |
|---|---|
| 初期SQL生成（BigQuery上で即実行） | Gemini in BigQuery |
| SQL最適化・レビュー | Claude Code |
| 定型レポートのテンプレ化 | Claude Code |

## まとめ

- Gemini in BigQueryで**SQLが書けなくてもGA4データの分析を始められる**
- プロンプトの工夫（テーブル名明示・期間指定・出力カラム指定）で精度が上がる
- 生成されたSQLは目視確認が必須。Claude Codeとの併用でさらに実用的に

AIによるSQL生成は「完璧な正解を出すツール」ではなく、「分析の初速を上げるツール」です。まずは日常の集計から試してみてください。

---

:::message
「GA4×BigQueryの初期設定から分析設計まで、まるっと相談したい」という方へ。ココナラでGA4・BigQuery・AI活用のコンサルティングを提供しています。
👉 [サービス詳細はこちら](https://coconala.com/services/1791205)
:::
```