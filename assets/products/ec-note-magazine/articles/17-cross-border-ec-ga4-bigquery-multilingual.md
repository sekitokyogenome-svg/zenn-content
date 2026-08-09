# 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法

## はじめに

越境ECを運営していると、「どの国のユーザーが売上に貢献しているのか」「英語・日本語・中国語のどの言語ページが成果を生んでいるのか」を正確に把握したいという場面が必ず出てきます。Google Analytics 4（GA4）の標準レポートでも国別データは確認できますが、言語・通貨・流入元を組み合わせた複合的な分析になると、レポートUIだけでは限界があります。

特に中小規模の越境ECでは、広告費の配分や翻訳コンテンツへの投資判断を感覚ではなくデータに基づいて行いたいという要望が高まっています。しかしGA4の管理画面では「国別 × 言語別 × 流入元別」という3軸以上の集計は難しく、エクスポートしたデータを手作業で加工している方も少なくありません。

本記事では、GA4をBigQueryに連携し、SQLを用いて国別・言語別の計測データを正確に集計する方法を解説します。エンジニア以外の方にも理解しやすいよう、クエリの意味と実務上の活用ポイントも合わせて説明します。

## GA4のBigQueryエクスポートとは？越境EC計測の基礎知識

GA4には「BigQueryエクスポート」という機能があり、Google Cloud上のデータウェアハウス（BigQuery）へ計測データを自動で出力できます。この機能はGA4の管理画面からリンクするだけで有効化でき、毎日または連続的にイベントデータが蓄積されていきます。

BigQueryに出力されるデータは、`events_YYYYMMDD`という形式のテーブルに格納されます。1行が1イベント（ページビュー、購入、クリックなど）に対応しており、ユーザーの国情報・ブラウザ言語・流入元・デバイス種別などが含まれています。

越境ECにとって特に重要なフィールドは以下の通りです。

- **`geo.country`**：ユーザーの接続国
- **`device.language`**：ブラウザの言語設定
- **`collected_traffic_source.manual_source`**：UTMのsource（流入元）
- **`collected_traffic_source.manual_medium`**：UTMのmedium（メディア区分）
- **`ecommerce.purchase_revenue`**：購入金額

> `geo.country`はIPアドレスから推定される国情報です。VPNの利用などにより実際の所在国と異なるケースがありますが、大量データの傾向把握としては十分に機能します。

<!-- ここから有料 -->

## 国別・言語別のセッション数をBigQueryで集計する

まずはシンプルに「どの国のユーザーが何セッション発生しているか」を、ブラウザ言語別に分けて集計するクエリを見ていきましょう。

GA4のBigQueryエクスポートでは `ga_session_id` は直接参照できないため、`UNNEST(event_params)` を使って取り出す必要があります。

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'session_start'
)

SELECT
  country,
  browser_language,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS session_count
FROM
  session_base
GROUP BY
  country,
  browser_language
ORDER BY
  session_count DESC
LIMIT 50;
```

このクエリでは `session_start` イベントのみを対象に、ユーザーIDとセッションIDを組み合わせてユニークセッション数を算出しています。`your_project.analytics_XXXXXXXXX` の部分は、実際のGCPプロジェクトIDとGA4のプロパティIDに合わせて変更してください。

結果を見ると、たとえば「アメリカからのアクセスでもブラウザ言語が日本語（ja）になっているケース」や「台湾からのアクセスで繁体字中国語（zh-tw）を使用しているユーザー」など、IPベースの国情報とブラウザ言語が乖離しているパターンが見えてきます。これは海外在住の日本人や、海外購入代行を利用するユーザーの存在を示しており、コンテンツ戦略に活かせる洞察です。

## 流入元と購買行動を国別に分析するSQL

次に、「どの国のユーザーが、どの流入経路から来て、いくら購入したか」という販売視点のクエリです。流入元の取得には `collected_traffic_source.manual_medium` および `manual_source` を使用します。

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_medium AS utm_medium,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'purchase'
)

SELECT
  country,
  browser_language,
  COALESCE(utm_medium, '(none)') AS medium,
  COALESCE(utm_source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 2) AS total_revenue,
  ROUND(AVG(revenue), 2) AS avg_order_value
FROM
  purchase_events
GROUP BY
  country,
  browser_language,
  medium,
  source
HAVING
  purchase_count >= 3
ORDER BY
  total_revenue DESC;
```

`COALESCE` 関数を使っているのは、UTMパラメータが未設定のアクセス（直接流入など）が NULL になるためです。NULL のままだと集計が分かりにくくなるため、わかりやすいラベルに変換しています。

> `collected_traffic_source` は GA4 の最新のトラフィックソース保存形式です。古いドキュメントでは `traffic_source.source` 等が紹介されていることがありますが、セッションをまたぐ参照の扱いが異なるため、イベント単位の分析には `collected_traffic_source` の使用を推奨します。

このクエリの結果から、「韓国からのInstagram経由の購入単価が高い」「英語圏ユーザーはオーガニック検索よりもリスティング広告から流入しやすい」といった傾向を読み取ることができます。国別の平均注文額（AOV）がわかれば、広告入札単価や送料無料ラインの設定を国別に最適化する判断材料になります。

## 多言語サイトにおける注意点とデータ品質の改善方法

越境ECの計測でよくある問題として、「言語別ページのURLが正しく区別されていない」「hreflangタグの設定ミスで同一ページが複数言語で計測されている」「通貨が混在して購入金額の集計がずれる」などが挙げられます。

BigQueryでデータを確認する際に、ページのURLに含まれる言語パスを抽出して集計すると、こうした問題を早期に発見できます。

```sql
SELECT
  geo.country AS country,
  REGEXP_EXTRACT(
    (SELECT ep.value.string_value FROM UNNEST(event_params) AS ep WHERE ep.key = 'page_location'),
    r'https?://[^/]+/([a-z]{2})(?:-[a-z]{2})?/'
  ) AS lang_path,
  device.language AS browser_language,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
  AND event_name = 'page_view'
GROUP BY
  country,
  lang_path,
  browser_language
ORDER BY
  event_count DESC;
```

このクエリでは `page_location` パラメータから正規表現でURLの言語パス（`/en/`、`/ja/`、`/zh/` 等）を抽出しています。`geo.country` と `lang_path`、`device.language` を突き合わせることで、「中国語圏のユーザーが英語ページを閲覧している」「日本語ページへのアクセスが台湾から多い」といった傾向を把握できます。

データ品質を向上させるためのポイントは以下の通りです。

- **カスタムディメンションの活用**: GA4のカスタムディメンションで「表示言語」「通貨コード」をイベントパラメータとして送信すると、BigQueryでの分析がさらに正確になります。
- **eコマースの通貨統一**: 購入金額をUSDやJPYに統一した値をカスタムパラメータで送るか、BigQuery側でECBの為替レートテーブルと結合するとクロス通貨の比較が可能になります。
- **ボットフィルタリング**: GA4は自動的にボットを除外しますが、BigQuery上ではさらに `privacy_info.ads_storage` や `is_active_user` フラグを活用した追加フィルタも検討する価値があります。

## まとめ

本記事では、越境ECにおけるGA4の多言語計測データをBigQueryで集計する方法を解説しました。要点を整理します。

- GA4のBigQueryエクスポートを活用すると、国別・言語別・流入元別の複合分析が可能になります
- `ga_session_id` は `UNNEST(event_params)` 経由で取得する必要があります
- 流入元の分析には `collected_traffic_source.manual_source` / `manual_medium` を使用します
- URLの言語パスを正規表現で抽出することで、多言語サイトの計測精度を確認できます
- データ品質の向上にはカスタムディメンションの設計が重要です

次のアクションとして、まずはGA4とBigQueryの連携設定を確認し、`events_*` テーブルへのアクセス権限を整備してください。連携後は本記事のクエリを自社のプロジェクトID・プロパティIDに置き換えて実行してみることをお勧めします。クエリ結果はLooker Studioと接続することで、国別ダッシュボードとして定期的なモニタリングにも活用できます。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
