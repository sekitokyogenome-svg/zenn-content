# ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する

## はじめに

「カートに商品を入れたのに、ページが重くて購入をあきらめた」——そんな経験をしたことはないでしょうか。ECサイトを運営する立場では、このような離脱が日々発生していても、なかなか数字として可視化できていないケースが多いようです。

サイト速度とコンバージョン率（CVR）の関係については、GoogleやAmazonが長年にわたって調査を続けており、「ページ読み込みが遅いほどユーザーが離脱しやすい」という傾向は広く知られています。しかし「自分のサイトでは実際にどの程度影響があるのか」を定量的に把握している事業者はまだ少ない印象です。

本記事では、Googleが提供する**CrUX（Chrome User Experience Report）**のBigQuery公開データセットと、GA4のBigQueryエクスポートデータを組み合わせ、自社ECサイトのサイト速度とCVRの相関を検証する方法をご紹介します。SQLの知識が多少あれば実践できる内容ですので、Webコンサルタントの方や、データ分析に取り組み始めたEC担当者の方にも参考にしていただけると思います。

<!-- ここから有料 -->

## CrUXデータとは何か

CrUX（Chrome User Experience Report）は、Chromeブラウザを通じて実際のユーザーが体験したページ読み込み速度などのパフォーマンス指標を集計した、Googleの公開データセットです。ラボ環境で計測するツール（LighthouseやPageSpeed Insightsのシミュレーション値）とは異なり、実際のユーザーが使用したデバイスやネットワーク環境でのリアルな体験値（フィールドデータ）である点が大きな特徴です。

BigQueryでは以下のプロジェクトで無料公開されています。

```sql
-- 日本向けCrUXデータ（月次集計）
`chrome-ux-report.country_jp.YYYYMM`

-- グローバルデータ
`chrome-ux-report.all.YYYYMM`
```

主な指標として、以下のCore Web Vitalsが含まれています。

**LCP**
- 正式名称: Largest Contentful Paint
- 概要: 最大コンテンツの描画時間

**INP**
- 正式名称: Interaction to Next Paint
- 概要: 操作への応答速度

**CLS**
- 正式名称: Cumulative Layout Shift
- 概要: 視覚的な安定性

**FCP**
- 正式名称: First Contentful Paint
- 概要: 最初のコンテンツ描画

**TTFB**
- 正式名称: Time to First Byte
- 概要: サーバー応答時間

> CrUXのデータはドメイン単位で集計されており、十分なトラフィックがあるURLのみが収録対象となります。月間アクセスが少ないページは収録されないケースもありますのでご注意ください。

## BigQueryでCrUXデータを取得するSQL

まず、自社ドメインのLCPおよびFCPの分布を取得するSQLを示します。`YYYYMM`部分は対象月（例: `202407`）に置き換えてください。

```sql
SELECT
  origin,
  -- LCP（良好・要改善・不良の割合）
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start < 2500 LIMIT 1), 4
  ) AS lcp_good_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 2500 AND start < 4000 LIMIT 1), 4
  ) AS lcp_needs_improvement_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 4000 LIMIT 1), 4
  ) AS lcp_poor_ratio,
  -- LCP中央値
  largest_contentful_paint.percentiles.p75 AS lcp_p75_ms,
  -- FCP中央値
  first_contentful_paint.percentiles.p75 AS fcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'  -- 自社ドメインに変更
```

このクエリを実行すると、LCPが「良好（2.5秒未満）」「要改善（2.5〜4秒）」「不良（4秒超）」に分類されたユーザーの割合と、75パーセンタイル値（p75）が取得できます。

p75の値はPageSpeed Insightsの「フィールドデータ」欄と同じ数値になるため、ツールとの照合が容易です。

## GA4のBigQueryエクスポートでCVRを算出するSQL

次に、GA4のBigQueryエクスポートデータからセッション単位のCVR（購入完了セッション数 / 総セッション数）を算出します。

以下のSQLでは、`purchase`イベントが発生したセッションを「CV済みセッション」としてカウントしています。`ga_session_id`はイベントパラメータ内に格納されているため、`UNNEST(event_params)`を使って展開する点がポイントです。

```sql
WITH sessions AS (
  SELECT
    -- ga_session_idはUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source,
    -- 購入フラグ（purchaseイベントが存在するセッションを1とする）
    MAX(IF(event_name = 'purchase', 1, 0)) AS is_converted,
    COUNT(DISTINCT event_name)             AS event_count
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  GROUP BY
    session_id,
    user_pseudo_id,
    medium,
    source
),

cvr_by_channel AS (
  SELECT
    medium,
    source,
    COUNT(*)                                  AS total_sessions,
    SUM(is_converted)                         AS converted_sessions,
    ROUND(SUM(is_converted) / COUNT(*), 4)    AS cvr
  FROM sessions
  WHERE session_id IS NOT NULL
  GROUP BY medium, source
  ORDER BY total_sessions DESC
)

SELECT * FROM cvr_by_channel;
```

> `your_project.analytics_XXXXXXXXX`の部分は、BigQueryのGA4エクスポート先プロジェクトとデータセット名に置き換えてください。データセットIDはGA4の管理画面「BigQueryのリンク」から確認できます。

## CrUXとGA4データを組み合わせた分析アプローチ

CrUXとGA4のデータを直接JOINしてCVRとの相関を見ることは、粒度の違い（CrUXはドメイン単位、GA4はセッション単位）から技術的に難しい面があります。そのため、以下のアプローチで分析を進めるのが実務的です。

**ステップ1：CrUXデータで月次の速度トレンドを把握する**

まず複数月のCrUXデータを取得し、LCP p75の推移を時系列で確認します。

```sql
SELECT
  PARSE_DATE('%Y%m', CAST(yyyymm AS STRING)) AS month,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM (
  SELECT 202405 AS yyyymm, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202405`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202406, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202406`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202407, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202407`
  WHERE origin = 'https://your-ec-site.com'
)
ORDER BY month;
```

**ステップ2：GA4データで同期間のCVRを月次集計する**

上記と同じ期間でGA4側のCVRを月次集計し、速度の変化とCVRの変化を並べて比較します。速度改善を実施した月の前後でCVRが変化しているかどうかが確認の焦点です。

**ステップ3：デバイス別・流入別の細分化**

CrUXはデバイスカテゴリ（phone / tablet / desktop）別に絞り込みが可能です。スマートフォン経由のLCPが悪化した時期にモバイルからのCVRが落ちていないか、などを掛け合わせることで、より解像度の高い仮説を立てられます。

```sql
-- スマートフォンのみのLCP中央値
SELECT
  form_factor.name                           AS device_type,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'
  AND form_factor.name = 'phone'
```

## 速度改善の優先箇所を特定する考え方

CrUXとCVRの相関が確認できたら、次は改善の優先箇所を絞り込む段階です。ECサイトにおいてLCP悪化の主な原因として挙げられやすいのは、以下のような点です。

- **商品画像の最適化不足**：高解像度画像をそのまま表示しており、WebP変換や`loading="lazy"`が未設定
- **ファーストビューのレンダリングブロック**：未使用CSSや大きなJavaScriptがHTMLのhead内に同期読み込みされている
- **サーバー応答時間（TTFB）の遅延**：ホスティング環境の性能不足やキャッシュ未設定

GA4のBigQueryデータでは、ページ別のエンゲージメント率や離脱率も集計できます。LCPが特に悪いと推測されるページ（商品一覧ページやカートページなど）を重点的に調査することで、改善インパクトの大きい箇所から着手できます。

> PageSpeed Insightsのフィールドデータ（CrUXベース）とラボデータ（Lighthouseシミュレーション）は別物です。サイト改善の効果確認にはフィールドデータの推移を継続的に追うことが重要です。数値が改善するまでに1〜2ヶ月程度かかる場合もあります。

## まとめ

本記事のポイントを整理します。

- **CrUX**はGoogleが提供するリアルユーザーの速度体験データであり、BigQueryで無料アクセスできる
- LCPのp75値とGA4のCVRを月次で並べて比較することで、速度とCVRの相関を定量的に観察できる
- GA4のBigQueryエクスポートでは`UNNEST(event_params)`経由で`ga_session_id`を取得し、`collected_traffic_source`で流入元を参照する
- デバイス別・チャネル別の細分化により、「どのユーザー層に速度問題が影響しているか」を特定しやすくなる

サイト速度の改善は一度対応すれば終わりではなく、商品追加やテーマ変更のたびに再劣化するリスクがあります。BigQueryとLooker Studioを組み合わせたモニタリング基盤を整備しておくと、変化に気づくタイミングを早めることができます。まずはCrUXデータで現状のLCP水準を把握するところから始めてみてください。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
