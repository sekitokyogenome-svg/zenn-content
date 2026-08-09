---
title: "ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した"
emoji: "📸"
type: "idea"
topics: ["bigquery","googleanalytics","ec","sql","datanalysis"]
published: false
---

## はじめに

「商品写真を増やせばCVRが上がる」——そう聞いたことはありませんか。ECサイト運営において、商品画像の重要性はよく語られます。しかし「何枚あれば十分なのか」「本当に枚数とCVRには関係があるのか」を、自社データで実際に確認している方は意外と少ないのではないでしょうか。

感覚や他社事例に頼るだけでは、限られたリソースの中で最適な意思決定はできません。特に中小ECの場合、商品ページを1ページずつ更新するコストは軽くはありません。写真撮影・加工・アップロードにかかる時間と費用を正当化できるだけの根拠が必要です。

本記事では、GA4のBigQueryエクスポートデータを使って「商品ページの写真枚数とCVR（購入転換率）の相関」を実際に分析する方法をSQLを交えて紹介します。非エンジニアの方でも流れをつかめるよう、考え方から順を追って説明しますので、ぜひ最後までご覧ください。

---

## 分析の設計：何を測るかを先に決める

分析を始める前に、「何を持って写真枚数とするか」「CVRをどう定義するか」を明確にする必要があります。ここがあいまいなままSQLを書くと、後から結果の解釈に迷うことになります。

**写真枚数の定義**
商品ページに表示されている画像の枚数を、ページのURLやイベントログから取得します。理想的には商品マスタにその情報があり、URLや商品IDと紐づけられている状態が望ましいです。GA4側でカスタムディメンション（例：`photo_count`）としてデータレイヤーから送信しておくと、BigQueryでの分析がシンプルになります。

**CVRの定義**
本記事では「商品ページへの訪問セッション数のうち、購入（`purchase`イベント）が発生したセッション数の割合」をCVRとして定義します。セッション単位で計算することで、同一ユーザーの複数訪問を考慮した指標になります。

:::message
カスタムディメンション `photo_count` がまだ実装されていない場合でも、商品URLの命名規則や別途管理しているスプレッドシートを使って近似的に分析することは可能です。その場合はBigQueryのJOINで外部データを結合する方法を取ります。
:::

---

## BigQueryでのセッションCVR集計SQL

GA4のBigQueryエクスポートデータでは、セッションIDを直接フィールドとして参照することができません。`event_params` をUNNESTして取得する必要があります。以下のSQLでは、商品ページへのセッション数と購入セッション数をそれぞれ集計し、商品URLごとのCVRを算出しています。

```sql
WITH
-- セッションIDをUNNESTで取得し、商品ページのセッションを抽出
product_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'page_view'
    AND (SELECT value.string_value
         FROM UNNEST(event_params)
         WHERE key = 'page_location') LIKE '%/products/%'
),

-- 購入が発生したセッションを抽出
purchase_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'purchase'
)

-- 商品URLごとにセッションCVRを算出
SELECT
  ps.page_location,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))) AS total_sessions,
  COUNT(DISTINCT
    CASE WHEN pur.session_id IS NOT NULL
    THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
    END
  ) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT
        CASE WHEN pur.session_id IS NOT NULL
        THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
        END
      ),
      COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING)))
    ) * 100, 2
  ) AS cvr_pct
FROM
  product_sessions ps
LEFT JOIN
  purchase_sessions pur
  ON ps.user_pseudo_id = pur.user_pseudo_id
  AND ps.session_id = pur.session_id
GROUP BY
  ps.page_location
ORDER BY
  total_sessions DESC
```

このクエリの結果として、商品URLごとのセッション数とCVR（%）が得られます。次のステップで、この結果に写真枚数を紐づけます。

---

## 写真枚数データとのJOIN：相関を可視化する

商品URLと写真枚数の対応表を別途用意し（スプレッドシートからBigQueryの外部テーブル、またはインポートで対応可能）、先ほどのCVR集計結果と結合します。

先ほどのCVR集計をそのまま `cvr_base` として取り込んでいるので、以下はコピーすればそのまま実行できます。

```sql
-- 写真枚数マスタ（別テーブルやサブクエリとして用意）
WITH photo_master AS (
  SELECT
    product_url,
    photo_count
  FROM
    `your_project.your_dataset.photo_master`
),

-- ここから cvr_base：前セクションのCVR集計をそのまま取り込む
product_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'page_view'
    AND (SELECT value.string_value
         FROM UNNEST(event_params)
         WHERE key = 'page_location') LIKE '%/products/%'
),

purchase_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'purchase'
),

cvr_base AS (
  SELECT
    ps.page_location,
    COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))) AS total_sessions,
    COUNT(DISTINCT
      CASE WHEN pur.session_id IS NOT NULL
      THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
      END
    ) AS purchase_sessions,
    ROUND(
      SAFE_DIVIDE(
        COUNT(DISTINCT
          CASE WHEN pur.session_id IS NOT NULL
          THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
          END
        ),
        COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING)))
      ) * 100, 2
    ) AS cvr_pct
  FROM
    product_sessions ps
  LEFT JOIN
    purchase_sessions pur
    ON ps.user_pseudo_id = pur.user_pseudo_id
    AND ps.session_id = pur.session_id
  GROUP BY
    ps.page_location
)

SELECT
  pm.photo_count,
  COUNT(*) AS product_count,
  ROUND(AVG(cb.cvr_pct), 2) AS avg_cvr_pct,
  ROUND(MIN(cb.cvr_pct), 2) AS min_cvr_pct,
  ROUND(MAX(cb.cvr_pct), 2) AS max_cvr_pct
FROM
  cvr_base cb
LEFT JOIN
  photo_master pm
  ON cb.page_location LIKE CONCAT('%', pm.product_url, '%')
WHERE
  pm.photo_count IS NOT NULL
  AND cb.total_sessions >= 30  -- 統計的に意味のある最低セッション数
GROUP BY
  pm.photo_count
ORDER BY
  pm.photo_count ASC
```

`total_sessions >= 30` の条件は重要です。訪問が数件しかない商品のCVRは変動が大きく、傾向を見るには不適切です。自社のトラフィック規模に応じて閾値を調整してください。

:::message
写真枚数マスタがない場合は、Googleスプレッドシートで商品URLと枚数を管理し、BigQueryの「外部テーブル」機能で直接SQLから参照することができます。都度インポートする手間が省けるのでおすすめです。
:::

---

## 流入元別に見る：オーガニックとSNSでCVRは変わるか

写真枚数の効果は、流入経路によっても異なる可能性があります。たとえばSNS広告経由のユーザーはすでに商品画像を見て来訪しているため、ページ内の写真枚数の影響が薄いケースも考えられます。一方でオーガニック検索経由のユーザーには、詳細な画像が意思決定を後押しするかもしれません。

GA4のBigQueryエクスポートでは、流入元は `collected_traffic_source` フィールドを使って取得できます。

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
  AND event_name = 'session_start'
```

このセッション開始イベントから流入元を取得し、先ほどのCVR集計と `user_pseudo_id` + `session_id` で結合することで、流入元×写真枚数×CVRの三次元での分析が可能になります。分析結果をLooker Studioで可視化すると、経営判断に使いやすいダッシュボードを作れます。

---

## 分析結果の読み方と注意点

実際に分析を回すと、たとえば「写真3〜5枚の商品のCVRが最も高い」「10枚以上は逆に下がる傾向がある」といった傾向が見えてくることがあります。ただし、結果を解釈する際にはいくつか注意が必要です。

**相関と因果は別物です**
写真枚数が多い商品のCVRが高い場合でも、それは「写真を増やしたからCVRが上がった」とは限りません。もともと人気の商品は撮影に力を入れていて写真枚数も多い、という逆の因果が働いている可能性もあります。

**商品カテゴリの違いを考慮する**
アパレルとインテリアでは、画像枚数が購買意欲に与える影響が異なります。全商品を一括で分析するより、カテゴリごとに分けて傾向を見ることをお勧めします。

**A/Bテストで因果を検証する**
相関が確認できたら、次のステップとして特定商品の写真枚数を意図的に変えて、CVRへの影響をA/Bテストで検証することが理想的です。データの傾向を仮説に変え、実験で確認するというサイクルが、データ活用の本質です。

---

## まとめ

本記事では、GA4のBigQueryエクスポートデータを使って「商品ページの写真枚数×CVR」の相関を分析する方法を紹介しました。要点を整理します。

- **セッションIDはUNNEST(event_params)経由**で取得する（GA4 BigQueryの基本ルール）
- **流入元は `collected_traffic_source.manual_medium/source`** で取得できる
- 写真枚数マスタを別途用意し、BigQueryでJOINして相関を可視化する
- 結果は「相関」であり「因果」ではない点に注意。A/Bテストで検証することが望ましい
- 最低セッション数（例：30件以上）でフィルタリングし、統計的に意味のある商品のみを対象にする

次のアクションとしては、まずは自社の商品データと写真枚数の対応表を整備することから始めてみてください。データが揃えば、本記事のSQLをそのまま活用して分析を進めることができます。データドリブンな商品ページ改善の第一歩として、ぜひ取り組んでみてください。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
