

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["BigQuery", "Gemini", "GA4", "SQL", "AI"]
published: false
---

## 「SQLが書けないから、GA4のデータを活かしきれない…」

EC担当者やWEBマーケターの方から、こんな相談をよくいただきます。

- GA4のデータがBigQueryに溜まっているけど、SQLが書けず放置している
- ChatGPTにSQL生成を頼んでいるが、テーブル構造と合わずエラーになる
- エンジニアに依頼するたびに数日かかり、施策のスピードが落ちる

実は、BigQueryのコンソール上で **Gemini（旧Duet AI）** を使えば、自然言語で質問するだけで、**実テーブルの構造を理解した正確なSQL** を生成できます。

本記事では、GA4エクスポートデータを題材に、Gemini in BigQueryの実践的な使い方を解説します。

## Gemini in BigQueryとは？

Google CloudのBigQueryコンソールに統合されたAIアシスタント機能です。外部のAIツールと決定的に異なるのは、**接続中のデータセットのスキーマ（テーブル構造）を自動的に参照する** 点です。

| 比較項目 | 外部AI（ChatGPT等） | Gemini in BigQuery |
|---|---|---|
| テーブル構造の認識 | 手動で伝える必要あり | 自動で参照 |
| フィールド名の正確性 | 幻覚（ハルシネーション）リスク高 | 実スキーマ準拠 |
| 生成後の実行 | コピペが必要 | そのまま実行可能 |
| コスト | 別途API費用 | BigQuery利用料に含まれる※ |

※Gemini for Google Cloud の有効化が必要です（Gemini Code Assist サブスクリプション等）。

## 事前準備：Gemini機能の有効化

:::message
Gemini in BigQueryを使うには、Google Cloud プロジェクトで **Gemini for Google Cloud API** を有効化し、適切なIAMロール（`roles/aiplatform.user` 等）を付与する必要があります。組織のポリシーによっては管理者への申請が必要です。
:::

有効化後、BigQueryコンソールのSQLエディタ上部に ✨（スパークル）アイコンまたは「SQLを生成」ボタンが表示されます。

## 実践：GA4データへの自然言語クエリ3選

### ① チャネル別セッション数を出したい

**プロンプト例：**
> 過去30日間のチャネル（medium）別セッション数を多い順に出して

**Geminiが生成するSQLの例：**

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
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') = 1
GROUP BY medium
ORDER BY sessions DESC;
```

:::message alert
生成されたSQLは必ず内容を確認してから実行してください。テーブル名やフィルタ条件がプロジェクトの設定と合っているか、目視チェックが重要です。
:::

### ② 商品別の購入回数ランキングを知りたい

**プロンプト例：**
> purchaseイベントのアイテム名ごとの購入回数トップ20を出して

**生成されるSQLの例：**

```sql
SELECT
  items.item_name,
  COUNT(*) AS purchase_count
FROM
  `your_project.analytics_XXXXXXX.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY items.item_name
ORDER BY purchase_count DESC
LIMIT 20;
```

GA4特有の **UNNEST(items)** を正しく展開してくれるのは、スキーマを認識しているGeminiならではの強みです。

### ③ 曜日×時間帯のセッションヒートマップ用データ

**プロンプト例：**
> 曜日と時間帯（0〜23時）ごとのセッション数を集計して。曜日は日本語で出して

**生成されるSQLの例：**

```sql
SELECT
  CASE EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d', event_date))
    WHEN 1 THEN '日曜' WHEN 2 THEN '月曜' WHEN 3 THEN '火曜'
    WHEN 4 THEN '水曜' WHEN 5 THEN '木曜' WHEN 6 THEN '金曜'
    WHEN 7 THEN '土曜'
  END AS day_of_week,
  EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS hour_jst,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
GROUP BY day_of_week, hour_jst
ORDER BY
  EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d', event_date)),
  hour_jst;
```

:::message
タイムゾーンの扱いには注意が必要です。`event_timestamp` はUTCで記録されているため、日本時間に変換するには `TIMESTAMP_ADD(..., INTERVAL 9 HOUR)` を追加するか、プロンプトで「日本時間で」と明示するのがおすすめです。
:::

## Gemini活用のコツ：プロンプトの書き方

より正確なSQLを生成させるために、以下を意識してみてください。

1. **テーブル名を明示する** → 「events_*テーブルから」と指定
2. **期間を具体的に書く** → 「過去30日」「2025年1月〜6月」
3. **集計単位を明確にする** → 「セッション単位で」「ユーザー単位で」
4. **出力形式を指定する** → 「多い順に」「上位10件」

曖昧なプロンプトは曖昧なSQLを生む——これはどのAIツールでも共通の原則です。

## まとめ

- Gemini in BigQueryは **実テーブルのスキーマを自動認識** するため、外部AIより正確なSQLを生成しやすい
- GA4の複雑な構造（UNNEST、event_params等）も適切に展開してくれる
- ただし、生成されたSQLの **目視確認は不可欠**
- プロンプトは「テーブル名・期間・集計単位・出力形式」を明示すると精度が上がる

SQLが書けなくても、正しいプロンプトの型を知っていれば、GA4データを自分の手で分析できる時代になりました。

---

:::message
📊 **GA4 × BigQueryの初期設定から分析レポート構築まで、まるごとサポートします**

「Geminiを試したいけど、そもそもBigQueryエクスポートの設定がまだ…」
「生成されたSQLが合っているか、プロに確認してほしい」

そんな方は、ココナラでGA4・BigQuery分析の代行・伴走サポートを行っています。
まずはお気軽にご相談ください 👇

https://coconala.com/services/1791205
:::
```