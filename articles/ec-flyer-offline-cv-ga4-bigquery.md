---
title: "ECの同梱チラシ施策効果をGA4のオフラインCV連携×BigQueryで測定する"
emoji: "📄"
type: "idea"
topics: ["bigquery","googleanalytics","ec","sql","advertising"]
published: false
---

## はじめに

ECサイトを運営していると、注文商品に同梱するチラシや折込クーポンを活用している事業者様は多いかと思います。「次回購入時に10%オフ」「QRコードからアクセスで特典プレゼント」といった施策は、既存顧客のリピート促進に有効な手段です。しかし、「チラシを同梱してみたが、実際にどれだけ効果があったのか分からない」というお声もよく耳にします。

オンライン広告であればクリック数やコンバージョン数が自動で計測されますが、紙のチラシは一歩間違えると"どんぶり勘定"になりがちです。QRコードやクーポンコードを使っても、それがGA4のデータとどう紐づくか分からず、Excelで集計して終わり——という状況になっていませんでしょうか。

この記事では、GA4のオフラインコンバージョン連携機能とBigQueryエクスポートを組み合わせて、同梱チラシの効果を定量的に可視化する方法を解説します。中小規模のECサイトでも実践しやすいよう、ステップを丁寧にご説明しますので、ぜひ参考にしていただければと思います。

## 同梱チラシ計測の基本設計：QRコードとUTMパラメータ

まず計測の基本となるのが、チラシに印刷するQRコードへのUTMパラメータの付与です。UTMパラメータとは、URLに付け加えるタグのようなもので、GA4がどのルートからユーザーが来たかを識別するために使います。

チラシ用のURLは以下のような形式で作成します。

```
https://your-ec-site.jp/coupon?utm_source=flyer&utm_medium=print&utm_campaign=flyer_2025summer
```

各パラメータの意味は次の通りです。

| パラメータ | 設定値（例） | 意味 |
|---|---|---|
| utm_source | flyer | 流入元（チラシ） |
| utm_medium | print | メディア種別（印刷物） |
| utm_campaign | flyer_2025summer | キャンペーン名 |

クーポンコードも忘れずに設定しておきましょう。注文時に入力されたクーポンコードをGA4のカスタムイベントとして送信するか、後述のオフラインCV連携で注文データとして取り込むことで、チラシ経由の購入を明確に識別できます。

:::message
UTMパラメータはGoogleのCampaign URL Builderを使うと入力ミスを防げます。チラシごとにcampaign値を変えておくと、時期や同梱商品別の比較も可能になります。
:::

## GA4のオフラインコンバージョン連携の仕組み

GA4には「オフラインコンバージョンのインポート」という機能があります。これは、ECの注文管理システムや基幹システムに蓄積された購入データを、後からGA4に取り込む仕組みです。

チラシ計測での活用シナリオは以下の通りです。

1. ユーザーがチラシのQRコードからサイトにアクセス（UTMパラメータ付き）
2. GA4がセッション情報（ga_session_idなど）をユーザーのブラウザに記録
3. ユーザーが購入完了。注文管理システムに「クーポンコード」「注文ID」などが保存される
4. ECシステム側でga_session_idを取得し、注文データと紐づけてCSVを作成
5. GA4にCSVをインポートし、オフラインCVとして計上

重要なのは、ステップ4でga_session_idをECシステム側に渡す処理です。購入完了時にJavaScriptでga_session_idを取得し、フォームの隠しフィールドや注文APIのパラメータとして送信する実装が必要になります。

```javascript
// 購入完了ページやカートページに実装するサンプル
gtag('get', 'G-XXXXXXXXXX', 'session_id', (sessionId) => {
  // hidden inputや注文APIへの送信処理
  document.getElementById('ga_session_id').value = sessionId;
});
```

この仕組みを整えることで、「チラシを見てアクセスし、3日後に購入した」というクロスセッションの行動も捕捉できるようになります。

## BigQueryでチラシ経由CV数・売上を集計するSQLの書き方

GA4のBigQueryエクスポートを有効にしていると、毎日のイベントデータが自動でBigQueryに蓄積されます。このデータを使って、チラシ経由のコンバージョンを集計してみましょう。

以下のSQLは、指定期間内のチラシ流入（utm_medium = 'print'）セッションからのpurchaseイベントを集計するものです。

```sql
-- チラシ経由の購入コンバージョンを集計する
WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign_name AS campaign,
    event_name,
    event_timestamp,
    -- purchase金額
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),
flyer_sessions AS (
  -- チラシ（print）経由のセッションを特定
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM session_params
  WHERE
    medium = 'print'
    AND source = 'flyer'
    AND event_name = 'session_start'
)
SELECT
  s.campaign,
  COUNT(DISTINCT CONCAT(sp.user_pseudo_id, CAST(sp.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN sp.event_name = 'purchase' THEN sp.user_pseudo_id END) AS purchasers,
  SUM(CASE WHEN sp.event_name = 'purchase' THEN sp.purchase_value ELSE 0 END) AS total_revenue
FROM
  session_params sp
INNER JOIN
  flyer_sessions s
  ON sp.user_pseudo_id = s.user_pseudo_id
  AND sp.ga_session_id = s.ga_session_id
GROUP BY
  s.campaign
ORDER BY
  total_revenue DESC;
```

:::message
`collected_traffic_source.manual_medium` および `manual_source` はGA4のBigQueryエクスポートスキーマ（2023年以降）で利用可能なフィールドです。旧来の `traffic_source.medium` はセッション単位ではなく初回流入を指すため、キャンペーン計測には前者をお使いください。
:::

このクエリを実行すると、キャンペーン名ごとのセッション数・購入者数・売上合計が一覧で確認できます。複数チラシを展開している場合はcampaignの値を変えておくことで、施策ごとの比較が容易になります。

## Looker StudioでチラシROIダッシュボードを作る

BigQueryのクエリ結果はLooker Studio（旧Googleデータポータル）に接続することで、グラフや表として可視化できます。毎月のチラシ施策レポートをLooker Studioで自動生成することで、手作業のExcel集計から脱却できます。

Looker Studioでのセットアップ手順は以下の通りです。

1. Looker Studioにログインし、「データソースを追加」からBigQueryを選択
2. 先ほど作成したSQLをカスタムクエリとして入力
3. ディメンションに「campaign」、指標に「total_revenue」「purchasers」を設定
4. 棒グラフや表ウィジェットを配置してダッシュボードを完成させる

ROI（投資対効果）を算出したい場合は、チラシの印刷・同梱コストを手動で入力できる計算フィールドを追加するか、Googleスプレッドシートにコスト表を用意してLooker Studioに結合すると便利です。

```
ROI = (チラシ経由売上合計 - チラシコスト) / チラシコスト × 100 (%)
```

毎月のチラシ施策後にBigQueryクエリを更新するだけで最新データが反映されるため、レポート作成の工数を大幅に削減できます。

## 計測精度を高めるための注意点

同梱チラシの計測を進めるうえで、いくつか留意すべき点があります。

**QRコードの読み取り率について**

チラシを受け取ったすべてのユーザーがQRコードを読み取るわけではありません。また、スマートフォンで読み取ってもサイトにアクセスせず終わるケースも存在します。そのため「チラシ同梱数」と「QRアクセス数」の比較も定点観測しておくと、チラシ自体の訴求力を評価する指標になります。

**クッキーの有効期限とクロスデバイス問題**

チラシを見た日にすぐ購入するユーザーばかりではありません。数日後にPCで改めて購入するケースでは、UTMパラメータのセッション情報がデバイスをまたいで引き継がれないことがあります。GA4のユーザーIDを活用したクロスデバイス計測を導入することで、この問題を緩和できます。

**iOSのSafariとITPの影響**

AppleのITP（Intelligent Tracking Prevention）により、SafariではCookieの有効期限が短縮される場合があります。チラシからのQRアクセスがSafariに集中している場合、セッション情報が消える前に購入まで至らないと計測から漏れるリスクがあります。サーバーサイドでのga_session_id取得・保存を検討することで、この影響を抑えられます。

:::message
計測の精度は「100%の捕捉」を目指すよりも、「一定の方法論で継続的に比較できる状態」を作ることが重要です。施策ごとに同じ条件で計測することで、相対的な改善効果を判断できます。
:::

## まとめ

同梱チラシの効果測定は、UTMパラメータの設計→GA4オフラインCV連携→BigQuery集計→Looker Studioダッシュボードの流れで実現できます。本記事のポイントをまとめます。

- **UTMパラメータ**: チラシごとにsource・medium・campaignを設定し、流入を識別する
- **オフラインCV連携**: ECシステムのga_session_idを注文データと紐づけ、GA4にインポートする
- **BigQueryクエリ**: `UNNEST(event_params)` でga_session_idを取得し、`collected_traffic_source` で流入元を判定する
- **Looker Studioダッシュボード**: BigQueryと接続してROIを自動集計・可視化する

最初の一歩として、次回のチラシ同梱前にQRコードのUTMパラメータを設定するだけでも、計測の精度は大きく変わります。段階的に仕組みを整えながら、データに基づいたチラシ施策の最適化を進めていただければと思います。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
