

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["BigQuery", "Gemini", "GA4", "SQL", "AI"]
published: false
---

## 「SQLが書けないけど、GA4のデータを自分で分析したい…」

EC運営をしていると、こんな場面がありませんか？

- 「先月のチャネル別CVRを出して」と分析担当に依頼→返ってくるまで3日
- ChatGPTにSQL生成を頼んだが、GA4のテーブル構造と合わずエラー連発
- BigQueryの画面は開けるけど、SQLの書き方がわからず閉じてしまう

2024年後半からBigQueryに統合された **Gemini in BigQuery（旧Duet AI）** を使えば、自然言語で質問するだけでSQLが生成されます。この記事では、GA4エクスポートデータに対して実際にGeminiを使う手順と、精度を上げるためのコツを解説します。

## Gemini in BigQueryとは？

BigQueryのコンソール上で使えるAIアシスタント機能です。エディタ上部のペンアイコン（✏️）またはチャットパネルから、自然言語でやりたいことを伝えるとSQLを自動生成してくれます。

:::message
**利用条件**: Google Cloud プロジェクトで「Gemini for Google Cloud API」が有効化されていること。BigQuery の無料枠（サンドボックス）では利用できない場合があります。
:::

## 実践：自然言語からGA4分析SQLを生成する

### ステップ1：データセットを指定してプロンプトを入力

BigQueryエディタを開き、GA4エクスポート先のデータセット（例：`analytics_123456789`）を左パネルで選択した状態で、Geminiアイコンをクリックします。

**入力するプロンプト例：**

> `analytics_123456789.events_*` テーブルを使って、2025年5月のチャネル別セッション数とコンバージョン率を集計するSQLを書いて。コンバージョンイベントは `purchase` とする。

### ステップ2：生成されたSQLを確認・修正する

Geminiが生成するSQLは概ね以下のような構造になります。ただし、**そのまま完璧に動くとは限りません**。特にGA4のネスト構造（`UNNEST(event_params)`）の扱いで修正が必要になるケースがあります。

以下は、Geminiの出力をベースに精度を高めた実用SQLです：

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
    collected_traffic_source.manual_source AS source,
    event_name
  FROM
    `project_id.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250501' AND '20250531'
)

SELECT
  IFNULL(medium, '(none)') AS channel_medium,
  IFNULL(source, '(direct)') AS channel_source,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END) AS conversions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END),
    COUNT(DISTINCT session_id)
  ) AS cvr
FROM sessions
GROUP BY 1, 2
ORDER BY sessions DESC
```

### ステップ3：結果を読み解く

出力イメージ：

| channel_medium | channel_source | sessions | conversions | cvr    |
|---------------|---------------|----------|-------------|--------|
| cpc           | google        | 12,450   | 187         | 0.0150 |
| organic       | google        | 8,320    | 108         | 0.0130 |
| (none)        | (direct)      | 6,100    | 42          | 0.0069 |
| referral      | instagram.com | 3,200    | 89          | 0.0278 |

この結果から「Instagramからの流入はセッション数は少ないがCVRが高い」といった示唆が得られます。

## Geminiの精度を上げる3つのコツ

### 1. テーブル名をフルパスで指定する

```
❌ 「GA4のデータからセッション数を出して」
✅ 「`project_id.analytics_123456789.events_*` テーブルを使って…」
```

テーブルを明示しないと、Geminiが存在しないテーブルを参照するSQLを生成することがあります。

### 2. カラムの取得方法を補足する

GA4のBigQueryエクスポートはネスト構造が特殊です。プロンプトに以下のような補足を加えると精度が上がります。

> 「`event_params` は UNNEST して key/value で取得すること。`ga_session_id` は `event_params` 内の `int_value` から取得する。」

### 3. 生成結果は「下書き」として扱う

:::message alert
Geminiが生成するSQLをノーチェックで本番利用するのは危険です。特にGA4のフィールド名（`collected_traffic_source` 等）は、外部AIが正しく把握していないことが多いため、必ず実行前にフィールド名を確認してください。
:::

## ChatGPT／Claude Code との使い分け

| ツール | 強み | GA4分析での注意点 |
|--------|------|------------------|
| Gemini in BigQuery | テーブルスキーマを自動参照できる | 複雑なネスト構造で精度が落ちることがある |
| ChatGPT / Claude | プロンプトの柔軟性が高い | GA4テーブル構造を都度教える必要がある |
| Claude Code（ローカル） | SQL生成→実行→修正を自動ループできる | 初期セットアップにBQ認証設定が必要 |

おすすめの運用は、**Geminiで下書きSQLを生成→手動で修正→定型化したSQLはClaude Codeで自動実行パイプラインに組み込む**という流れです。

## まとめ

- Gemini in BigQueryは「SQLの下書きツール」として非常に有用
- GA4データを扱う場合、テーブル名のフルパス指定とネスト構造の補足がカギ
- 生成されたSQLは必ず検証し、フィールド名の正確性を確認する

SQLが書けなくても、AIの力を借りれば「自分でデータを見る」第一歩は踏み出せます。ただし、GA4 × BigQueryの独特なテーブル構造を理解しているかどうかで、分析の質は大きく変わります。

---

:::message
「GA4のBigQuery設定からSQL作成まで、自社に合った形でサポートしてほしい」という方へ。GA4・BigQuery・AI活用の実務支援を行っています。
👉 [ココナラでGA4×BigQuery分析のサポートを見る](https://coconala.com/services/1791205)
:::
```