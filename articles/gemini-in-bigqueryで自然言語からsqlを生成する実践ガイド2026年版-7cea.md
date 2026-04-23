

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery", "gemini", "ga4", "sql", "ai"]
published: false
---

## 「SQLが書けない…でもデータは見たい」という切実な悩み

「GA4のデータをBigQueryにエクスポートしたけど、SQLが書けなくて宝の持ち腐れになっている」——EC事業者やマーケターの方から、この相談を本当に多くいただきます。

SQLを学ぶ時間もない、外注するほどの予算もない。そんなジレンマを解消してくれるのが **Gemini in BigQuery** です。自然言語（日本語）で質問するだけでSQLを生成してくれるこの機能、実務でどこまで使えるのか、GA4データを題材に検証しました。

## Gemini in BigQueryとは

BigQueryのコンソール上でGeminiが統合されており、エディタ上部のペンアイコン（SQL生成）や、チャットパネルから自然言語でSQLを生成・補完できます。

:::message
2025年現在、Gemini in BigQueryはGoogle Cloud の「Gemini for Google Cloud」ライセンスが必要です。プロジェクトでの有効化はCloud コンソールの「Gemini for Google Cloud」から行えます。
:::

## 実践：GA4データに対して自然言語でSQLを生成する

### ステップ1：テーブルを指定して質問する

BigQueryエディタ上部の ✨ アイコンをクリックし、以下のように入力します。

**プロンプト例：**
> `analytics_XXXXXXX.events_*` テーブルから、過去30日間のセッション数をチャネル別に集計して、多い順に並べてください

**Geminiが生成するSQL（例）：**

```sql
SELECT
  collected_traffic_source.manual_medium AS channel_medium,
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
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') = 1
GROUP BY
  channel_medium
ORDER BY
  sessions DESC;
```

生成されたSQLはそのままエディタに挿入され、内容を確認してから実行できます。

### ステップ2：生成SQLを「レビュー」する癖をつける

Geminiの生成精度はかなり高くなっていますが、GA4 BigQueryスキーマ特有の落とし穴があります。生成後に以下のチェックを推奨します。

:::message alert
**レビュー時の3大チェックポイント**
1. **セッションIDの定義** — `user_pseudo_id + ga_session_id` の連結になっているか
2. **UNNEST処理** — `event_params` や `items` が正しくUNNESTされているか
3. **テーブルサフィックス** — `_TABLE_SUFFIX` の日付フィルタでスキャン量が制御されているか
:::

### ステップ3：段階的に複雑な質問へ拡張する

一度に複雑な質問をするより、段階的にプロンプトを発展させるのがコツです。

**ステップ3-1：まずシンプルに**
> 過去7日間のページビュー数を日別に出してください

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(*) AS page_views
FROM
  `project_id.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'page_view'
GROUP BY
  date
ORDER BY
  date;
```

**ステップ3-2：条件を追加**
> 上記をデバイスカテゴリ別にも分けてください

**ステップ3-3：さらに深掘り**
> モバイルだけに絞り、ランディングページ別のセッション数とCVR（purchaseイベント基準）を出してください

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS landing_page
  FROM
    `project_id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
    AND device.category = 'mobile'
),
conversions AS (
  SELECT DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM
    `project_id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'purchase'
    AND device.category = 'mobile'
)
SELECT
  s.landing_page,
  COUNT(DISTINCT s.session_id) AS sessions,
  COUNT(DISTINCT c.session_id) AS conversions,
  SAFE_DIVIDE(COUNT(DISTINCT c.session_id), COUNT(DISTINCT s.session_id)) AS cvr
FROM
  sessions s
LEFT JOIN
  conversions c ON s.session_id = c.session_id
GROUP BY
  s.landing_page
ORDER BY
  sessions DESC
LIMIT 20;
```

段階的に質問することで、Geminiが文脈を理解しやすくなり、精度が向上します。

## Gemini活用で得られた効果（実体験ベース）

| 指標 | Gemini導入前 | Gemini導入後 |
|---|---|---|
| SQL作成時間（1クエリ平均） | 20〜40分 | 3〜8分 |
| SQLエラーによるやり直し回数 | 3〜5回 | 0〜1回 |
| 月間の分析レポート作成数 | 2本 | 8本 |

SQLを書く工程のハードルが下がった結果、**「分析の頻度」そのものが増える**のが最大の恩恵です。

## 注意点：Geminiに丸投げしてはいけない理由

Geminiは強力なアシスタントですが、以下の点は人間が判断する領域です。

- **「何を分析すべきか」の問い設計** — AIは質問に答えるだけで、問いは作ってくれません
- **ビジネス文脈の解釈** — CVRが下がった原因がセール終了なのか、UI変更なのかはデータの外にあります
- **スキャン量とコスト管理** — 生成SQLが全期間スキャンしていないかは必ず確認しましょう

## まとめ

Gemini in BigQueryは「SQLの壁」を大幅に下げてくれるツールです。ただし、精度を高めるにはGA4スキーマの基本知識と、段階的なプロンプト設計が重要になります。

**SQLが書けなくても、正しい「問い」が立てられれば、データは答えてくれる時代になりました。**

---

:::message
「GA4×BigQuery環境は構築したけど、何をどう分析すればいいかわからない」「Geminiを使っても出てきたSQLが正しいか判断できない」——そんなお悩みがあれば、GA4・BigQuery分析の伴走サポートをご活用ください。御社のデータに合わせた分析設計からSQL作成・レビューまで対応しています。
👉 [ココナラのサービスページはこちら](https://coconala.com/services/1791205)
:::
```