---
title: "Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する"
emoji: "🗂️"
type: "tech"
topics: ["bigquery","gemini","googlecloud","sql","ai"]
published: false
---

## はじめに

「Googleアナリティクス（GA4）のデータを BigQuery に飛ばしているのに、どのプロジェクトにどのテーブルがあるかわからなくなってしまった」——そんな経験はありませんか？

複数のブランドやサービスを展開しているEC事業者やWebコンサルタントの場合、GCPプロジェクトがいくつにも分かれていることは珍しくありません。分析のたびにプロジェクトを切り替え、テーブル名を手動で確認し、SQLを書き直す……この繰り返し作業は、本来の「データから示唆を得る」という目的に集中する時間を奪ってしまいます。

2024年後半から Google Cloud が強化している **Gemini in BigQuery Studio** には、こうしたマルチプロジェクト環境の課題を軽減する「リソース検出（Resource Discovery）」機能が搭載されています。本記事では、この機能の概要と実際の活用イメージを、非エンジニアの方にもわかるように解説します。

---

## リソース検出機能とは何か

Gemini in BigQuery Studio のリソース検出機能とは、**自然言語で質問するだけで、アクセス権を持つ複数プロジェクトにまたがるデータセットやテーブルを自動的に候補として提示してくれる機能**です。

従来であれば、分析担当者はあらかじめ「どのプロジェクトに何のテーブルがある」かを把握しておく必要がありました。しかし、リソース検出機能を使うと、たとえば「GA4の購入イベントデータはどこにある？」と入力するだけで、Geminiがアクセス可能なプロジェクト内のGA4エクスポートテーブルを探し出し、候補として提示してくれます。

この機能が特に役立つのは、以下のような状況です。

- 複数ブランドを別プロジェクトで管理しているEC企業
- 顧客ごとにGCPプロジェクトが分かれているWebコンサルタント
- 新しいメンバーがどのプロジェクトに何があるかを把握しきれていないチーム

データ基盤の「地図」を自動で生成してくれるようなイメージで捉えると理解しやすいでしょう。

---

## 機能を使うための前提条件

リソース検出機能を利用するには、いくつかの前提条件があります。事前に確認しておきましょう。

**1. Gemini in BigQuery の有効化**
利用するGCPプロジェクトで「Gemini for Google Cloud API」を有効にする必要があります。Google Cloud コンソールの「APIとサービス」から有効化できます。

**2. 適切なIAM権限**
テーブルを検出するには、対象プロジェクトまたはデータセットに対して `bigquery.dataViewer` 以上の権限が必要です。権限がないプロジェクトのリソースは、Geminiも検出できません。

**3. BigQuery Studio の利用**
この機能は BigQuery の旧来のUIではなく、**BigQuery Studio**（`console.cloud.google.com/bigquery` からアクセスできる新しいインターフェース）で利用可能です。

**4. データカタログとの連携（推奨）**
Dataplex や Data Catalog でメタデータ（テーブルの説明や列の意味）を整備しておくと、Geminiの検出精度と提示内容の質が向上します。テーブルに説明文を付けておくことを検討してみてください。

---

## マルチプロジェクト環境での活用シナリオ

ここでは、GA4データを複数プロジェクトで管理しているECサイト運営会社を例に、具体的な活用シナリオを見ていきます。

### シナリオ: 2ブランドのコンバージョンを横断集計したい

たとえば「ブランドA用プロジェクト」と「ブランドB用プロジェクト」にそれぞれGA4のBigQueryエクスポートデータが存在するとします。Gemini に「両ブランドの先月の購入件数を比較したい」と伝えると、リソース検出機能が両プロジェクトの該当テーブルを特定し、クロスプロジェクトクエリの雛形を生成してくれます。

生成されるSQLのイメージは以下のようなものになります。

```sql
-- ブランドA: 先月の購入件数
SELECT
  'brand_a' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))

UNION ALL

-- ブランドB: 先月の購入件数
SELECT
  'brand_b' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-b.analytics_YYYYYYYYY.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)));
```

:::message
`ga_session_id` は `event_params` の中に格納されているため、`UNNEST(event_params)` を経由して取り出す必要があります。GA4のBigQueryエクスポートでは、セッションIDをトップレベルの列として直接参照することはできません。
:::

このクエリを手書きする場合、プロジェクトIDやデータセットIDをあらかじめ調べておく必要がありますが、リソース検出機能があれば、Geminiがその手間を省いてくれます。

---

## 流入元分析への応用

マルチプロジェクトでのリソース検出と組み合わせて、流入元別の分析も行えます。GA4のBigQueryエクスポートで流入元を参照する際は、`collected_traffic_source` フィールドを使います。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchases DESC
LIMIT 20;
```

:::message
`collected_traffic_source.manual_medium` および `manual_source` は、UTMパラメータで付与した流入元情報を格納するフィールドです。GA4のUI上では「セッションのデフォルトチャネルグループ」に相当する情報の元データになります。
:::

Geminiのリソース検出機能を使えば、「先月のオーガニック流入からの購入数を調べたい」という自然言語の指示から、上記のようなクエリの骨格を自動生成できるようになっています。プロジェクトをまたいで複数ブランドを比較する際も、同様のアプローチが取れます。

---

## 非エンジニアが押さえておきたいポイント

リソース検出機能はSQLの知識がなくても活用の入り口に立てますが、いくつかの点を理解しておくとより安心して使えます。

**コストへの意識を持つ**
BigQueryはスキャンしたデータ量に応じて課金されます（オンデマンドの場合、1TB あたり約6.25ドル）。Geminiが生成したクエリをそのまま実行する前に、クエリエディタ右上の「実行前の推定バイト数」を確認する習慣をつけましょう。大量のデータをスキャンしそうな場合は、`_TABLE_SUFFIX` で日付を絞り込む条件を加えることでコストを抑えられます。

**権限管理は慎重に**
リソース検出機能のメリットを最大化するには、Geminiに多くのプロジェクトを「見せる」ことが必要ですが、それはすなわち利用者がそのプロジェクトへのアクセス権を持つということです。社内の権限設計と照らし合わせながら、必要最小限のアクセス権を付与するようにしましょう。

**Geminiの出力は必ず確認する**
Geminiが提示するクエリはあくまで補助的な出力です。テーブル名やプロジェクトIDが正確かどうか、分析の目的に合った集計になっているかどうかを確認してから実行することをお勧めします。

---

## まとめ

Gemini in BigQuery Studio のリソース検出機能は、マルチプロジェクト環境でのデータ分析における「どこに何があるかわからない」という問題を大幅に軽減してくれる機能です。

本記事でご紹介したポイントを整理します。

- リソース検出機能により、複数プロジェクトにまたがるテーブルを自然言語で発見できる
- GA4のBigQueryエクスポートデータの分析にも活用でき、クロスプロジェクトクエリの生成を補助してくれる
- `ga_session_id` は `UNNEST(event_params)` 経由、流入元は `collected_traffic_source.manual_medium/manual_source` を使う点は変わらない
- 権限管理とコスト意識を持ちながら運用することが大切

データ分析の民主化が進む中、AIアシスタントによるリソース検出機能はその入り口を広げるものです。まずは手元のプロジェクトでGemini in BigQuery Studioを試してみることから始めてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
