

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】"
emoji: "🤖"
type: "tech"
topics: ["BigQuery", "GA4", "Gemini", "SQL", "AI"]
published: false
---

## 「SQLを書ける人がいない」問題、まだ抱えていませんか？

「GA4のデータをBigQueryにエクスポートしたけど、SQLが書けるメンバーがいなくて活用できていない」——EC事業者やWEBマーケターの方から、こうした相談を頻繁にいただきます。

2025年後半からBigQueryに統合されたGeminiのSQL生成機能が大幅に進化し、自然言語で質問するだけで実用レベルのSQLが返ってくるようになりました。本記事では、GA4 × BigQueryの実務で使える具体的なプロンプトとSQL生成例を紹介します。

## Gemini in BigQueryとは

BigQueryのコンソール上で自然言語の質問を入力すると、Geminiがテーブルスキーマを読み取り、適切なSQLを自動生成してくれる機能です。2026年現在、以下の特徴があります。

- **スキーマ自動認識**: 対象データセットのカラム名・型を自動で参照
- **GA4エクスポートテーブル対応**: `events_*` テーブルのネスト構造（UNNEST）も適切に展開
- **日本語プロンプト対応**: 日本語での質問にも高精度で応答

:::message
Gemini in BigQueryの利用には、Google CloudプロジェクトでGemini for Google Cloud APIの有効化が必要です。料金体系はクエリごとの従量課金ではなく、Duet AI（現Gemini）のサブスクリプションに含まれます。
:::

## 実践：GA4データで使える自然言語プロンプト5選

以下、BigQueryコンソールの「SQLを生成」欄に入力するプロンプトと、生成されるSQLの例を紹介します。データセットは `project_id.analytics_123456789.events_*` を前提とします。

### ① チャネル別セッション数

**プロンプト例：**
> 過去30日間のチャネル（medium）別セッション数を集計して、多い順に表示して

**生成されるSQL：**

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
  `project_id.analytics_123456789.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY medium
ORDER BY sessions DESC
```

### ② 商品別の購入回数と売上

**プロンプト例：**
> purchaseイベントのアイテム別に購入回数と合計売上を出して

```sql
SELECT
  items.item_name,
  COUNT(*) AS purchase_count,
  SUM(items.item_revenue) AS total_revenue
FROM
  `project_id.analytics_123456789.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY items.item_name
ORDER BY total_revenue DESC
```

### ③ ランディングページ別CVR

**プロンプト例：**
> ランディングページ別にセッション数とCVR（purchaseイベント発生率）を算出して

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS landing_page,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase
  FROM
    `project_id.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') = 1
  GROUP BY session_id, landing_page
)
SELECT
  landing_page,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_percent
FROM sessions
GROUP BY landing_page
ORDER BY sessions DESC
LIMIT 20
```

## 精度を上げるプロンプトの書き方

Geminiの生成精度を高めるために、以下の4点を意識してください。

| ポイント | 良い例 | 悪い例 |
|---------|--------|--------|
| 期間を指定する | 「過去30日間の」 | 「最近の」 |
| イベント名を明示する | 「purchaseイベント」 | 「コンバージョン」 |
| 集計軸を具体的に | 「manual_medium別に」 | 「チャネル別に」 |
| 出力形式を伝える | 「多い順にTOP20」 | 「一覧で」 |

:::message alert
Geminiが生成したSQLは、実行前に必ずレビューしてください。特にUNNEST処理やJOIN条件は意図しない重複が発生する場合があります。生成結果を「そのまま信じる」のではなく「たたき台として活用する」スタンスが重要です。
:::

## Gemini × BigQueryが変えるデータ活用の現場

この機能により、SQLの知識がないマーケターでも以下のワークフローが実現します。

1. **自然言語で質問** → SQLが自動生成される
2. **生成されたSQLをレビュー** → 必要に応じて手動修正
3. **実行して結果を取得** → Looker Studioに接続して可視化

SQLを「ゼロから書く」のではなく「AIが出した8割の精度を、人が10割に仕上げる」——この分業が、データ活用のハードルを大きく下げてくれます。

## まとめ

- Gemini in BigQueryはGA4のネスト構造にも対応し、実用レベルのSQLを生成できる
- プロンプトに「期間・イベント名・集計軸・出力形式」を含めると精度が上がる
- 生成されたSQLは必ず人がレビューし、たたき台として活用する

---

:::message
「GA4 × BigQueryの初期設定から分析基盤の構築まで、まるごと相談したい」という方へ。GA4・BigQuery・Looker Studioを組み合わせたデータ活用の伴走支援を行っています。

👉 **[ココナラでサービスを見る](https://coconala.com/services/1791205)**
:::
```