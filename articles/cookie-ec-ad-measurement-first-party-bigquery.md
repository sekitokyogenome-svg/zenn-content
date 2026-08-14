---
title: "Cookie規制後のEC広告効果測定をファーストパーティデータ×BigQueryで再構築する"
emoji: "🍪"
type: "idea"
topics: ["bigquery","googleanalytics","advertising","ec","gtm"]
published: true
---

## はじめに

「広告費をかけているのに、どのキャンペーンが売上に貢献しているかよくわからない」——そのような悩みをお持ちの中小EC事業者の方は少なくないと思います。Google AnalyticsやMeta広告の管理画面を眺めていても、数字がバラバラで何を信じればいいのか判断がつかない、という声もよく耳にします。

この状況に追い打ちをかけているのが、昨今のCookie規制の強化です。Safari・FirefoxはすでにサードパーティCookieをブロックしており、Googleも段階的な対応を進めています。広告プラットフォームが計測に使ってきたサードパーティCookieが機能しなくなることで、コンバージョンが正確に追跡できなくなり、「広告の費用対効果が見えなくなった」という事業者が増えています。

では、このような環境変化に対してどう対応すればよいのでしょうか。答えの一つが、**ファーストパーティデータを軸に据えた計測基盤の再構築**です。自社サイトで直接取得したデータをGA4に集め、BigQueryへエクスポートして分析する仕組みを整えることで、サードパーティCookieに依存しない、精度の高い広告効果測定が可能になります。

本記事では、中小ECサイトを運営されている方やWebコンサルタントの方を対象に、ファーストパーティデータとBigQueryを組み合わせた広告効果測定の再構築方法を、実際のSQLを交えながら解説します。

---

## Cookie規制で何が変わったのか

サードパーティCookieとは、広告配信事業者などが自社ドメイン以外のサイトに設置するCookieのことです。これを使ってユーザーの行動を複数サイトにわたって追跡し、広告のクリックからコンバージョンまでを紐付けていました。

この仕組みが使えなくなると、例えば「Meta広告をクリックして3日後にサイトを再訪して購入したユーザー」を正確に計測することができなくなります。広告管理画面上のコンバージョン数が実態より少なく表示されたり、逆にモデリングによって過大計上されたりと、データの信頼性が揺らぐのです。

一方でファーストパーティデータ、つまり**自社ドメイン上で取得したデータ**はこの影響を受けません。GA4のgtag.jsやGTM経由で取得したセッション情報、メールアドレスや会員IDなどの顧客情報は、すべて自社の資産として活用できます。Cookie規制の時代においては、このファーストパーティデータをいかに豊かに蓄積・活用するかが、計測精度を左右します。

---

## GA4のBigQueryエクスポートを活用する理由

GA4には、計測したイベントデータをBigQueryへ自動でエクスポートする機能が用意されています（Google Analytics 360は有料ですが、無料版でも1日あたり100万イベントまで対応しています）。このエクスポートを有効にすることで、GA4の管理画面では見えなかったローデータへアクセスできるようになります。

BigQueryの大きなメリットは、**セッション単位・ユーザー単位での柔軟な集計**が可能な点です。GA4のUI上では「チャネル別コンバージョン数」は確認できても、「特定の流入元から来たユーザーが何日後に購入したか」「どのキャンペーンが新規顧客獲得に強いか」といった分析はできません。BigQueryではSQLを使ってこれらを自由に掘り下げることができます。

また、GA4のレポートはサンプリングが入ることがありますが、BigQueryのエクスポートデータはサンプリングなしの全件データです。正確なコンバージョン数を把握したい場面でも、BigQueryが信頼できる唯一の情報源になります。

---

## GTMとGA4でファーストパーティ計測を整備する

BigQuery分析の精度を高めるには、GA4への計測設計が重要です。以下のポイントを整備しておくことをお勧めします。

**1. GTMでの購入イベント実装**

ECサイトの「購入完了」ページや「サンクスページ」で `purchase` イベントを発火させ、`transaction_id`・`value`・`items` を正確に渡す設定をGTMで行います。これがコンバージョン計測の土台になります。

**2. ファーストパーティCookieによるセッション管理**

GA4はデフォルトで `_ga` Cookie（ファーストパーティ）をサブドメインを含む自社ドメイン全体で発行します。これにより、サードパーティCookieなしでもセッションとユーザーを継続追跡できます。GTMの「Google タグ」設定で `cookie_domain: 'auto'` が設定されていることを確認してください。

**3. user_idの送信（会員ECの場合）**

ログイン済みユーザーには `user_id` を送信する設定を追加することで、デバイスをまたいだユーザー同定が可能になります。GA4管理画面の「Googleシグナル」と組み合わせることで、クロスデバイスの行動を一人のユーザーとして分析できます。

:::message
GA4のBigQueryエクスポートは、GA4プロパティの管理画面「データの設定 > BigQueryリンク」から設定できます。GCPプロジェクトとBigQueryデータセットが必要です。初期設定には概ね30分程度かかります。
:::

---

## BigQueryでチャネル別コンバージョンを集計するSQL

以下は、GA4のBigQueryエクスポートデータを使って、流入チャネル別の購入件数・売上・ユーザー数を集計するSQLの例です。

```sql
-- チャネル別コンバージョン集計（GA4 BigQueryエクスポート）
WITH purchase_sessions AS (
  SELECT
    -- セッションIDはevent_paramsをUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_source       AS traffic_source,
    collected_traffic_source.manual_medium       AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value,
    event_date
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
)

SELECT
  traffic_medium,
  traffic_source,
  campaign_name,
  COUNT(*)                         AS purchase_count,
  COUNT(DISTINCT user_pseudo_id)   AS unique_buyers,
  ROUND(SUM(purchase_value), 0)    AS total_revenue
FROM
  purchase_sessions
GROUP BY
  traffic_medium,
  traffic_source,
  campaign_name
ORDER BY
  total_revenue DESC
;
```

:::message
`your_project.analytics_XXXXXXXXX` の部分は、ご自身のGCPプロジェクトID・GA4プロパティIDに置き換えてください。`_TABLE_SUFFIX` で集計期間を指定します。
:::

このSQLを実行することで、「どのチャネル・キャンペーンが何件の購入・いくらの売上をもたらしたか」をBigQueryのローデータから直接確認できます。GA4管理画面の数値と差異がある場合、サンプリングや帰属モデルの違いによるものがほとんどです。BigQueryの数値のほうが実態に近いとお考えください。

---

## LookerStudioで広告効果ダッシュボードを作成する

BigQueryで集計したデータは、LookerStudio（旧データポータル）と連携してダッシュボード化することができます。LookerStudioはGoogleアカウントがあれば無料で利用でき、BigQueryをデータソースとして接続する機能が標準搭載されています。

ダッシュボードに入れておきたい指標の例を以下に挙げます。

| 指標 | 説明 |
|------|------|
| チャネル別売上 | 流入元ごとの売上貢献度 |
| CPO（Cost Per Order） | 広告費 ÷ 購入件数 |
| 新規 vs リピート購入比率 | user_idの初回・再購入判定 |
| 購入までのセッション数 | コンバージョンパスの長さ |

LookerStudioでは、BigQueryに保存しておいたSQL集計ビューをデータソースとして利用すると、毎回SQLを書き直す手間がなくなります。BigQuery上にビューを作成しておき、LookerStudioからはそのビューを参照するのが運用しやすい構成です。

:::message
LookerStudioとBigQueryの接続は、LookerStudioの「データソースを追加」からBigQueryを選択し、プロジェクト・データセット・テーブル（またはビュー）を指定するだけです。GCPの権限設定（BigQueryデータ閲覧者ロール）が必要です。
:::

---

## まとめ

Cookie規制によって広告計測の環境は大きく変化していますが、ファーストパーティデータを中心に据えた計測基盤を整えることで、この変化に対応することができます。本記事で紹介したポイントを整理します。

- **サードパーティCookieへの依存を減らす**: GA4のファーストパーティCookieとGTMによる計測設計を整備する
- **BigQueryエクスポートを活用する**: サンプリングなしのローデータで正確なコンバージョン把握を行う
- **SQLで柔軟に分析する**: チャネル別・キャンペーン別の売上・CPOを自社の定義で集計する
- **LookerStudioで可視化する**: 経営層にも伝わるダッシュボードで意思決定を支援する

はじめから完璧な基盤を目指す必要はありません。まずはGA4のBigQueryエクスポートを有効にし、購入イベントが正しく計測されているかを確認するところから始めてみてください。データが蓄積されれば、分析の幅は自然と広がっていきます。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
