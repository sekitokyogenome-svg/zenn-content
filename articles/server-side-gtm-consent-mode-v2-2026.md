---
title: "サーバーサイドGTM × Consent Mode v2で広告計測精度を維持する【2026年版】"
emoji: "🔐"
type: "tech"
topics: ["gtm","googleanalytics","advertising","javascript","googlecloud"]
published: false
---

## はじめに

「最近、コンバージョン数が急に減ったように見えるのですが、実際の売上は変わっていないんです」——こうした相談が、ECサイトを運営するオーナー様やWebコンサルタントの方々からたびたび寄せられるようになりました。原因の多くは、ブラウザのサードパーティCookie制限やユーザーのConsent（同意）拒否にあります。計測タグが発火しても、同意が得られていなければデータが送られない。その結果、Google広告やGA4のコンバージョンレポートに空白が生まれ、入札最適化が狂い始めます。

2024年のGDPR強化対応を機に、Googleは「Consent Mode v2」を事実上の必須要件として位置づけました。さらに、サードパーティCookieの段階的廃止が各ブラウザで進む2026年現在、クライアントサイドのタグだけに頼る計測体制は限界を迎えつつあります。こうした状況で注目されているのが、**サーバーサイドGTM（sGTM）とConsent Mode v2の組み合わせ**です。

本記事では、「Consent Mode v2とは何か」から始め、サーバーサイドGTMとの連携構成、実装時のポイント、そしてGA4・BigQueryを活用した同意率の可視化まで、実務に直結する形で解説します。非エンジニアの方にも読んでいただけるよう、概念図や具体例を交えながら進めていきます。

---

## Consent Mode v2とは何か、そしてなぜ重要なのか

Consent Mode（コンセントモード）とは、ユーザーがCookieの利用に同意しなかった場合でも、Googleのタグが「同意なし」という情報を受け取り、モデリングによってコンバージョンデータを補完する仕組みです。v2では新たに `ad_user_data`（広告向けユーザーデータの送信同意）と `ad_personalization`（広告のパーソナライズ同意）の2つのパラメータが追加されました。

つまり、Consent Mode v2を正しく実装することで、以下の恩恵を受けられます。

- **同意が得られなかった場合でも、Googleが行動モデリングでコンバージョンを推定**
- `ad_user_data` を `granted` にすることで、エンハンスドコンバージョンへのデータ提供が可能
- `ad_personalization` を適切に管理することで、リマーケティングの有効性を維持

重要なのは、Consent Mode v2は「同意を回避する手段」ではなく、「同意が得られた範囲でデータを最大活用し、不足分を統計的に補う」アプローチだという点です。GDPR・個人情報保護法の精神とも整合的であり、信頼性の高い計測基盤の一部として位置づけられます。

---

## サーバーサイドGTMが解決する3つの課題

クライアントサイドGTM（従来型）では、ブラウザ上でタグが動作するため、広告ブロッカーやITPによってデータが欠落するケースが増えています。サーバーサイドGTMはこの問題に対して、以下の3点で貢献します。

### 1. ファーストパーティCookieとしての発行

sGTMを自社ドメインのサブドメイン（例: `metrics.yourdomain.com`）で動作させると、GAクライアントIDなどのCookieをファーストパーティとして発行できます。SafariのITPによる有効期限短縮（7日→1日）を回避でき、ユーザーの再訪問をより正確に計測できるようになります。

### 2. 広告ブロッカーの迂回

広告ブロッカーの多くは `gtm.js` や `analytics.js` などの既知のURLパターンをブロックします。sGTMはリクエストを自社サーバー経由で中継するため、これらのブロックを受けにくくなります。ただし、これはCookieの同意とは別の問題であり、ブロッカーの迂回が倫理的・法的に許容されるかは利用規約や地域の法律に依存します。

### 3. Consent Mode v2シグナルのサーバー側での統合管理

クライアントサイドでConsent Mode v2のシグナル（`analytics_storage`, `ad_storage`, `ad_user_data`, `ad_personalization`）を設定した後、そのシグナルをsGTMが受け取り、サーバー側のタグ（Google広告コンバージョン、GA4など）に引き継ぎます。これにより、クライアント側の処理が軽量になり、同意状態の一元管理が実現します。

---

## sGTM × Consent Mode v2の実装フロー

実装は大きく4つのステップで構成されます。

### ステップ1: CMPの設置と同意シグナルの送出

まず、CMP（同意管理プラットフォーム）を導入します。OneTrust、Cookiebot、Usercentrics、あるいは国産のCMPなどが選択肢です。CMPがユーザーの同意・拒否を受け取ったタイミングで、GTMのdataLayerに同意状態を送出します。

```javascript
// 同意が得られた場合の例（CMPのコールバック内で呼び出す）
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: 'consent_update',
  consent: {
    analytics_storage: 'granted',
    ad_storage: 'granted',
    ad_user_data: 'granted',
    ad_personalization: 'granted'
  }
});
```

同意が拒否された場合は、すべてのパラメータを `denied` にします。Consent Mode v2では、ページ読み込み時に**デフォルト値を必ず設定**しておくことが求められます。

```javascript
// ページ読み込み直後（GTMスニペットより前）に設置
window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }
gtag('consent', 'default', {
  analytics_storage: 'denied',
  ad_storage: 'denied',
  ad_user_data: 'denied',
  ad_personalization: 'denied',
  wait_for_update: 500
});
```

### ステップ2: クライアントサイドGTMでsGTMへ転送

クライアントサイドGTMの設定で、GA4タグやGoogle広告タグのサーバーURL（Transport URL）を自社のsGTMエンドポイントに変更します。これにより、ブラウザからの計測データはいったんsGTMサーバーに送られ、そこから各広告・計測プラットフォームへ転送されます。

```bash
# Google Cloud RunでsGTMをデプロイする例（概略）
gcloud run deploy gtm-server \
  --image gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable \
  --region asia-northeast1 \
  --set-env-vars CONTAINER_CONFIG=<コンテナ設定文字列> \
  --allow-unauthenticated
```

### ステップ3: sGTM側でConsent Stateを受け取るタグを設定

sGTMのGTMコンテナ（サーバー用）でGA4クライアントを設定し、受け取ったコンセントシグナルをGA4タグ・Google広告タグに反映します。sGTMのGA4タグには「Consent State Observation」の設定があり、クライアント側から送られた同意状態をそのままGoogleのサーバーへ送信します。

### ステップ4: ファーストパーティCookieの設定

sGTMのCookie設定変数を使い、`_ga` CookieをHTTPOnly・SameSite=Strictで発行します。こうすることで、JavaScriptからのアクセスを遮断しつつ、ファーストパーティとして長期間保持できます。

---

## GA4 × BigQueryで同意率を可視化する

実装後は、「どの程度のユーザーが同意しているか」を定期的にモニタリングすることが重要です。GA4のBigQueryエクスポートを活用すると、同意イベントの発生状況をSQLで集計できます。

以下のクエリは、`consent_update` カスタムイベントの発生数と、各同意パラメータの値を日次で集計する例です。

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'analytics_storage'
  ) AS analytics_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_storage'
  ) AS ad_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_user_data'
  ) AS ad_user_data,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'consent_update'
GROUP BY
  1, 2, 3, 4, 5, 6
ORDER BY
  event_date DESC
```

このクエリで取得したデータをLooker Studioに接続すると、「流入チャネル別の同意率」「同意拒否ユーザーの割合推移」などを視覚化できます。同意率が低いチャネルには、CMPのUI改善やメッセージの見直しを検討する判断材料になります。

:::message
BigQueryエクスポートを利用するには、GA4プロパティとBigQueryプロジェクトのリンク設定が必要です。また、`events_*` テーブルのパーティションは日次で作成されるため、当日分のデータは `events_intraday_*` テーブルを参照してください。
:::

---

## 実装前に確認しておきたい注意点

### コストの見積もり

sGTMはGoogle Cloud Run上で動作し、リクエスト数に応じた従量課金が発生します。月間100万PVのECサイトで試算すると、月額数千円〜数万円程度になるケースが多いですが、トラフィック規模や構成によって大きく異なります。事前にGoogle Cloudの料金計算ツールで見積もることをお勧めします。

### 法的対応はCMPとセットで

sGTMやConsent Modeを導入するだけでGDPR・日本の個人情報保護法への対応が完結するわけではありません。プライバシーポリシーの更新、Cookieポリシーの整備、CMPによる同意記録の保存など、法務面の整備は別途必要です。専門家（弁護士・行政書士）への相談を組み合わせることを推奨します。

### モデリングデータの扱い

Consent Modeのモデリングによって補完されたコンバージョンは、Google広告のレポート上で実測値と合算表示されます。BigQueryへのエクスポートでは、モデリングデータは含まれません。両者の乖離を理解したうえでレポートを読む必要があります。

:::message
Google広告のコンバージョンレポートに表示される数値は、実測値＋モデリング推定値の合計です。BigQueryのGA4データのみを参照すると、実測値ベースの数字になるため、必ず両者を使い分けて解釈してください。
:::

---

## まとめ

2026年現在、広告計測の精度を維持するには、単一の技術で解決しようとするのではなく、**CMP・Consent Mode v2・サーバーサイドGTM・ファーストパーティCookie**を組み合わせた多層的な構成が求められています。

本記事で解説したポイントを整理します。

- **Consent Mode v2** は、同意なしユーザーのデータをモデリングで補完し、Google広告・GA4の計測精度を維持する仕組みです。`ad_user_data` と `ad_personalization` の2パラメータが必須となっています。
- **サーバーサイドGTM** は、ファーストパーティCookieの発行・広告ブロッカーへの耐性・同意シグナルのサーバー側統合という3つの価値をもたらします。
- **GA4 × BigQuery** を活用することで、同意率の推移や流入チャネル別の分布を定量的にモニタリングし、CMP改善のPDCAを回せます。

次のアクションとして、まず自社サイトで「Consent Modeのデフォルト値が設定されているか」「CMPが正しくdataLayerに同意状態を送出しているか」を確認してみてください。Google Tag Assistantの「Consent」タブでリアルタイムに検証できます。

## 関連記事

- [GA4×GTMでLINE広告・TikTok広告のコンバージョン計測を設定する](https://zenn.dev/web_benriya/articles/ga4-gtm-line-tiktok-conversion-tracking)
- [GTMのデータレイヤーを使ったGA4カスタムイベント設計のベストプラクティス](https://zenn.dev/web_benriya/articles/gtm-data-layer-ga4-custom-event-design)
- [GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する](https://zenn.dev/web_benriya/articles/ga4-bigquery-cac-by-channel)
- [GA4のBigQueryエクスポート完全設定ガイド【2026年版】](https://zenn.dev/web_benriya/articles/ga4-bigquery-export-setup-guide-2026)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
