

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery", "gemini", "ga4", "sql", "ai"]
published: false
---

## 「SQLが書けないと、GA4のデータを活かせない」という壁

「GA4のデータをBigQueryにエクスポートしたけれど、SQLが難しくて分析が進まない…」

中小ECの現場で、こんな悩みを抱えていませんか？GA4の管理画面では見られない深い分析をしたくてBigQuery連携を始めたものの、ネストされたスキーマやUNNESTの構文に苦戦して、結局レポートが出せないまま放置——という方は少なくありません。

そこで注目したいのが **Gemini in BigQuery** です。BigQueryのコンソール上で自然言語を入力するだけで、AIがSQLを生成してくれる機能です。本記事では、GA4データに対して実際にどう使うのかを具体的な手順とプロンプト例つきで解説します。

## Gemini in BigQueryとは

Gemini in BigQueryは、Google CloudのAI「Gemini」がBigQueryのエディタに統合された機能です。主にできることは以下の通りです。

- **自然言語 → SQL生成**：日本語の質問からSELECT文を自動生成
- **SQL説明**：既存のSQLが何をしているかを日本語で解説
- **SQLの補完・修正**：途中まで書いたSQLの続きを提案

:::message
Gemini in BigQueryを利用するには、Google Cloud プロジェクトで「Gemini for Google Cloud API」を有効にし、適切なIAMロール（`roles/aiplatform.user` など）を付与する必要があります。
:::

## 実践：GA4データに自然言語で質問してみる

### ステップ1：BigQueryコンソールでGeminiを有効化

1. BigQueryコンソール右上の「Gemini」アイコン（✨マーク）をクリック
2. SQLエディタ上部に表示されるチャット欄、または「Generate SQL」ボタンを確認

### ステップ2：テーブルを指定して自然言語で質問

エディタ上部のプロンプト欄に以下のように入力します。

```
テーブル `project_id.analytics_XXXXXX.events_*` から、
過去30日間のチャネル別セッション数とコンバージョン率を集計してください。
コンバージョンイベントは purchase です。
```

### ステップ3：生成されたSQLを確認・修正

Geminiが生成するSQLの**典型例**は以下のようなイメージです。

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name
  FROM
    `project_id.analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

session_summary AS (
  SELECT
    session_id,
    IFNULL(medium, '(none)') AS medium,
    IFNULL(source, '(direct)') AS source,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM sessions
  GROUP BY session_id, medium, source
)

SELECT
  source,
  medium,
  COUNT(DISTINCT session_id) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT session_id)) * 100, 2) AS cvr_percent
FROM session_summary
GROUP BY source, medium
ORDER BY sessions DESC;
```

:::message alert
Geminiが生成するSQLは**そのまま実行すると誤りを含む場合があります**。特にGA4のネスト構造（`UNNEST(event_params)`）やフィールド名は、生成結果を必ず目視で確認してください。上記のSQLも、プロジェクトIDやデータセット名は自分の環境に置き換える必要があります。
:::

## 精度を上げる3つのプロンプトのコツ

Geminiに適当な質問を投げると、的外れなSQLが返ってくることがあります。精度を上げるポイントを押さえましょう。

### 1. テーブル名をフルパスで明示する

```
# ❌ 曖昧な指定
「GA4のデータからセッション数を出して」

# ✅ 具体的な指定
「`my-project.analytics_123456789.events_*` から
 _TABLE_SUFFIXで直近7日間に絞り、セッション数を日別に集計して」
```

### 2. フィールドの取得方法をヒントとして与える

GA4のBigQueryスキーマは独特です。ヒントを添えるだけで精度が大きく変わります。

```
セッションIDは CONCAT(user_pseudo_id, CAST((SELECT value.int_value 
FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) で生成してください。
チャネルは collected_traffic_source.manual_medium を使ってください。
```

### 3. 出力カラムと並び順を指定する

```
出力カラム：日付, チャネル, セッション数, CV数, CVR
並び順：日付の昇順
```

## Geminiに任せきりにしないための検証ステップ

生成されたSQLを信頼しすぎると、誤った数値をもとに意思決定してしまうリスクがあります。以下の検証を習慣にしましょう。

| 検証項目 | 方法 |
| --- | --- |
| 行数の妥当性 | GA4管理画面のセッション数とオーダーを比較 |
| フィールド名 | `INFORMATION_SCHEMA.COLUMNS` で実在を確認 |
| 日付フィルタ | `_TABLE_SUFFIX` の範囲が意図通りか目視 |
| UNNEST漏れ | `event_params` や `items` を参照する際にUNNESTしているか |

## まとめ：AIはSQL学習の「最強の壁打ち相手」

Gemini in BigQueryは、SQLに不慣れな方にとって強力な補助ツールです。ただし、生成結果を鵜呑みにせず「プロンプトの工夫」と「結果の検証」をセットで行うことが重要です。

使い続けるうちに「Geminiが書いたSQLを読んで学ぶ」→「自分でも書けるようになる」という好循環が生まれます。AIを"代替"ではなく"学習パートナー"として活用するのがおすすめです。

---

:::message
「BigQueryを導入したけれど、何から分析すればいいかわからない」「SQLの書き方を相談したい」という方へ——GA4×BigQuery×AIを活用したデータ分析の壁打ち・伴走サポートを行っています。まずはお気軽にご相談ください。
👉 [ココナラのサービスページはこちら](https://coconala.com/services/1791205)
:::
```