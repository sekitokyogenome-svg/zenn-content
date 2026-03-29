---
title: "AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する"
emoji: "🤖"
type: "idea"
topics: ["googleanalytics", "bigquery", "ai"]
published: true
---

## はじめに

「最近、ChatGPTやPerplexityからサイトにアクセスが来ているらしいが、GA4のレポートではどこにも出てこない」――そんな違和感を覚えたことはないでしょうか。

AI検索エンジン（ChatGPT、Perplexity、Gemini など）からの流入は、GA4の標準レポートでは **「direct」や「referral」に埋もれてしまう** ことが多く、実態が見えにくい状態です。しかし、この流入は今後さらに増加が見込まれるトラフィックソースであり、早い段階で計測基盤を整えておくことが重要です。

本記事では、GA4のBigQueryエクスポートデータを使って、AI検索からの流入を特定・分析する方法を解説します。

## なぜAI検索流入はGA4で見えにくいのか

AI検索エンジンからの流入が見えにくい理由は主に2つあります。

1. **リファラが送信されない場合がある**: ChatGPTのデスクトップアプリなど一部の環境ではリファラが空になり、GA4上では「direct」に分類される
2. **既存のチャネルグループに該当しない**: GA4のデフォルトチャネルグループには「AI Search」というカテゴリが存在しないため、`chatgpt.com` や `perplexity.ai` からの流入は「Referral」に分類される

つまり、意識して計測しない限り、AI検索流入はdirectとreferralの中に散らばって認識できません。

## AI検索のリファラパターンを知る

まず、主要なAI検索エンジンのリファラドメインを整理しておきます。

| AI検索エンジン | リファラドメイン |
|---|---|
| ChatGPT | `chatgpt.com`, `chat.openai.com` |
| Perplexity | `perplexity.ai` |
| Google Gemini | `gemini.google.com` |
| Microsoft Copilot | `copilot.microsoft.com` |
| Claude | `claude.ai` |

:::message
これらのドメインは今後変更・追加される可能性があります。定期的に自社のリファラデータを確認し、新しいAI検索エンジンからの流入がないかチェックしましょう。
:::

## BigQueryでAI検索セッションを特定するSQL

GA4のBigQueryエクスポートデータから、AI検索エンジン経由のセッションを抽出します。`page_referrer` パラメータにリファラ情報が含まれているので、これを活用します。

```sql
-- AI検索エンジンからのセッションを日別に集計
WITH session_referrers AS (
  SELECT
    event_date,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'session_start'
),

ai_sessions AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(page_referrer, r'chatgpt\.com|chat\.openai\.com') THEN 'ChatGPT'
      WHEN REGEXP_CONTAINS(page_referrer, r'perplexity\.ai') THEN 'Perplexity'
      WHEN REGEXP_CONTAINS(page_referrer, r'gemini\.google\.com') THEN 'Gemini'
      WHEN REGEXP_CONTAINS(page_referrer, r'copilot\.microsoft\.com') THEN 'Copilot'
      WHEN REGEXP_CONTAINS(page_referrer, r'claude\.ai') THEN 'Claude'
      ELSE NULL
    END AS ai_source
  FROM session_referrers
)

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  ai_source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions
FROM ai_sessions
WHERE ai_source IS NOT NULL
GROUP BY date, ai_source
ORDER BY date DESC, sessions DESC;
```

## AI検索 vs オーガニック vs ダイレクトの行動比較

AI検索からの流入ユーザーがどのような行動をしているかを、他のトラフィックソースと比較します。

```sql
-- チャネル別のセッション行動指標を比較
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_name,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

session_channel AS (
  SELECT
    user_pseudo_id,
    session_id,
    CASE
      WHEN REGEXP_CONTAINS(
        MAX(IF(event_name = 'session_start', page_referrer, NULL)),
        r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
      ) THEN 'AI Search'
      WHEN MAX(IF(event_name = 'session_start', medium, NULL)) = 'organic' THEN 'Organic Search'
      WHEN MAX(IF(event_name = 'session_start', page_referrer, NULL)) IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    COUNT(DISTINCT IF(event_name = 'page_view', page_location, NULL)) AS pages_per_session,
    TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(MAX(event_timestamp)),
      TIMESTAMP_MICROS(MIN(event_timestamp)),
      SECOND
    ) AS session_duration_sec,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_conversion
  FROM session_base
  GROUP BY user_pseudo_id, session_id
)

SELECT
  channel,
  COUNT(*) AS sessions,
  ROUND(AVG(pages_per_session), 1) AS avg_pages_per_session,
  ROUND(AVG(session_duration_sec), 0) AS avg_session_duration_sec,
  ROUND(SAFE_DIVIDE(SUM(has_conversion), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_channel
WHERE channel IN ('AI Search', 'Organic Search', 'Direct')
GROUP BY channel
ORDER BY sessions DESC;
```

このクエリを実行すると、AI検索流入のページ/セッション、滞在時間、CVRをオーガニックやダイレクトと並べて比較できます。

:::message alert
AI検索からの流入はまだ絶対数が少ないケースが多いため、CVRなどの指標は統計的に有意でない可能性があります。傾向の把握にとどめ、サンプル数が十分に集まってから意思決定に使うことを推奨します。
:::

## UTMパラメータとリファラグルーピングの設定

BigQueryで事後的に分類するだけでなく、GA4側でも認識できるように準備しておくと運用が楽になります。

### 方法1：カスタムチャネルグループの作成

GA4の管理画面で、カスタムチャネルグループを作成できます。

1. GA4管理画面 > 「データの表示」 > 「チャネルグループ」
2. 新しいチャネルグループを作成
3. 「AI Search」チャネルを追加し、条件に `セッションのソース` が `chatgpt.com`, `perplexity.ai` などを含む、と設定

### 方法2：自社コンテンツにUTMパラメータを仕込む

AI検索エンジンに引用されやすいページのURLに、サイト内リンクでUTMを付与することは現実的ではありませんが、**自社が管理するプロフィールやリンク集**に以下のようなUTMを付けておくと、一部の流入を正確に捕捉できます。

```text
https://example.com/?utm_source=chatgpt&utm_medium=ai-search
```

## BigQueryでカスタムチャネルグループを定義する

GA4の管理画面でカスタムチャネルを作成しても、BigQuery側のデータには自動で反映されません。BigQueryでも同じロジックを適用するには、SQLでチャネル分類を定義します。

```sql
-- AI Searchを含むカスタムチャネル分類関数（再利用可能）
CREATE TEMP FUNCTION classify_channel(
  source STRING, medium STRING, page_referrer STRING
) AS (
  CASE
    WHEN REGEXP_CONTAINS(COALESCE(page_referrer, ''),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai')
      THEN 'AI Search'
    WHEN source = 'chatgpt' AND medium = 'ai-search' THEN 'AI Search'
    WHEN medium = 'organic' THEN 'Organic Search'
    WHEN medium = 'cpc' THEN 'Paid Search'
    WHEN medium = 'referral' THEN 'Referral'
    WHEN medium = '(none)' AND source = '(direct)' THEN 'Direct'
    ELSE 'Other'
  END
);
```

この関数をビューやスケジュールドクエリに組み込むことで、一貫したチャネル分類を維持できます。

## SEO・コンテンツ戦略への示唆

AI検索からの流入を追跡することで、以下のような示唆が得られます。

- **どのページがAIに引用されやすいか**: AI検索流入のランディングページを分析することで、AIが参照しやすいコンテンツの傾向がわかる
- **AIユーザーの行動パターン**: AI検索経由のユーザーはすでに回答を得た上で訪問している可能性があり、従来のオーガニック流入とは異なる行動をとることがある
- **コンテンツ最適化の方向性**: 構造化されたデータ、明確なFAQ形式、信頼性の高い数値データなど、AIが引用しやすい要素を意識したコンテンツ設計が有効になる

## AI検索流入のトレンド監視

最後に、AI検索流入の推移を週次で監視するクエリを用意しておくと、トレンドの変化を素早くキャッチできます。

```sql
-- AI検索流入の週次トレンド
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
  COUNTIF(REGEXP_CONTAINS(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
    r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
  )) AS ai_search_sessions,
  COUNT(*) AS total_sessions,
  ROUND(SAFE_DIVIDE(
    COUNTIF(REGEXP_CONTAINS(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
    )),
    COUNT(*)
  ) * 100, 2) AS ai_search_pct
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY week_start
ORDER BY week_start;
```

このクエリをLooker Studioに接続すれば、AI検索流入の推移をダッシュボードで常時監視できます。

## まとめ

AI検索エンジンからのトラフィックは、GA4の標準レポートでは見落としやすい流入源です。BigQueryを使えば、リファラ情報からAI検索流入を正確に特定し、行動データやCVRを他チャネルと比較分析できます。

早い段階でカスタムチャネルグループを定義し、週次のトレンド監視を始めておくことで、今後のSEO・コンテンツ戦略に活かせるデータが蓄積されていきます。

---

GA4のBigQuery連携やカスタムチャネル設計について、自社に合った形で構築したい方はお気軽にご相談ください。

https://coconala.com/services/1791205
