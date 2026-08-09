---
title: "TikTok広告のコンバージョンAPIをサーバーサイドGTMで実装する手順"
emoji: "🎵"
type: "tech"
topics: ["gtm","advertising","googleanalytics","ec","javascript"]
published: false
---

## はじめに

TikTok広告を運用していて、「コンバージョンが正しく計測できていない」「広告の最適化がうまくいかない」と感じたことはありませんか？ iOSのトラッキング制限やブラウザのCookie制限が強化された現在、ピクセル（ブラウザ側）だけのコンバージョン計測では取りこぼしが増えており、広告の最適化精度が下がりやすい状況になっています。

そこで注目されているのが、TikTok Events API（コンバージョンAPI）と呼ばれるサーバーサイドの計測手法です。ブラウザを介さずにサーバーから直接TikTokへコンバージョンデータを送信するため、ブラウザのブロックや遅延の影響を受けにくく、より正確なデータをTikTokの広告最適化エンジンに届けることができます。

本記事では、Google タグ マネージャーのサーバーサイドコンテナ（Server-Side GTM）を使って、TikTok Events APIを実装する手順を解説します。完全にエンジニア不要とはいきませんが、GTMの基本操作に慣れている方であれば、この記事を参考に実装を進めることができます。中小ECサイトを運営しているオーナーの方や、クライアントのTikTok広告を支援しているWebコンサルタントの方を主な読者として想定しています。

---

## TikTok Events APIとサーバーサイドGTMの概要

### TikTok Events APIとは

TikTok Events API（旧称：TikTok Conversions API）は、ウェブサイトのサーバーとTikTokのサーバーが直接通信することでコンバージョンデータを送る仕組みです。従来のTikTok Pixelはブラウザ上のJavaScriptで動作するため、広告ブロッカーやSafariのITP（Intelligent Tracking Prevention）によって計測が妨げられることがあります。Events APIはその問題を回避し、購入・カート追加・リード獲得などのイベントをより正確に送信できます。

### サーバーサイドGTMとは

サーバーサイドGTM（以下、sGTM）は、Google タグ マネージャーのコンテナをブラウザではなくクラウドサーバー上で動作させる機能です。通常のGTM（クライアントサイド）はブラウザ上でタグを実行しますが、sGTMはGoogle Cloud Platform（GCP）などのサーバーで動作し、ブラウザから受け取ったイベントデータを加工して各種広告プラットフォームやアナリティクスへ転送します。

sGTMを使うメリットとして以下の点が挙げられます。

- ブラウザ側のJavaScript実行量が減り、ページ表示速度が改善される
- Cookieをサーバー側で発行できるため、ファーストパーティCookieとして長期間保持できる
- 複数のプラットフォームへのデータ送信を一元管理できる

---

## 事前準備：必要なアカウントと設定

実装を始める前に、以下のものを用意しておきましょう。

### 必要なもの一覧

| 項目 | 内容 |
|---|---|
| TikTok for Business アカウント | 広告アカウントが有効な状態であること |
| TikTok Pixel | 広告マネージャーで作成済みであること |
| Events API アクセストークン | TikTok広告マネージャーで発行 |
| Google Cloud Platformアカウント | sGTMのホスティングに使用 |
| サーバーサイドGTMコンテナ | GTMで新規作成 |
| クライアントサイドGTM | 既存サイトに導入済み |

### TikTok Events APIのアクセストークン取得手順

1. TikTok広告マネージャー（ads.tiktok.com）にログインします。
2. 左メニューから「資産」→「イベント」を開きます。
3. 対象のPixelを選択し、「Events API」タブをクリックします。
4. 「アクセストークンの生成」をクリックしてトークンを発行します。
5. 発行されたトークンを安全な場所に控えておきます。

このアクセストークンは後ほどsGTM側の設定で使用します。外部に漏れないよう、GTMの変数として管理することをお勧めします。

---

## サーバーサイドGTMコンテナのセットアップ

### GCPでの環境構築

sGTMはGoogle Cloud Platform上のCloud Runを使って動作します。初めての方は以下の手順で環境を構築してください。

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセスし、新しいプロジェクトを作成します。
2. GTMの管理画面（tagmanager.google.com）を開き、「アカウントを作成」→「コンテナを作成」を選択します。
3. ターゲットプラットフォームで「サーバー」を選択します。
4. コンテナ作成後に表示される「サーバーコンテナをプロビジョニング」の手順に従い、GCPのCloud Runにデプロイします。

デプロイが完了すると、`https://xxxx.run.app` のようなサーバーURLが発行されます。このURLがsGTMのエンドポイントになります。

### カスタムドメインの設定（推奨）

サーバーURLをそのまま使うこともできますが、ファーストパーティCookieの観点からは自社ドメインのサブドメイン（例：`gtm.example.com`）を割り当てることを強くお勧めします。DNSの設定とCloud RunのカスタムドメインマッピングでCNAMEを登録することで対応できます。

---

## sGTMにTikTok Events APIタグを追加する

### TikTokタグテンプレートの導入

sGTMにはデフォルトでTikTok用のタグが用意されていない場合があります。GTMコミュニティテンプレートギャラリーから「TikTok Events API」テンプレートを追加しましょう。

1. sGTMのコンテナを開きます。
2. 左メニューの「テンプレート」→「タグテンプレート」を開きます。
3. 「ギャラリーで検索」をクリックし、「TikTok」と検索します。
4. TikTok公式またはコミュニティ提供のEvents APIテンプレートを追加します。

:::message
テンプレートの提供元を確認してください。TikTok公式が提供するテンプレートを優先的に使用することをお勧めします。コミュニティテンプレートを使用する場合は、コードの内容を確認した上で導入してください。
:::

### タグの設定

タグテンプレートを追加したら、以下の項目を設定します。

| 設定項目 | 内容 |
|---|---|
| Pixel ID | TikTok広告マネージャーで確認できるPixelのID |
| Access Token | 先ほど発行したEvents APIアクセストークン |
| Event Name | 送信するイベント名（例：`Purchase`、`AddToCart`） |
| Event Source URL | コンバージョンが発生したページのURL |
| User Data（メールアドレス等） | ハッシュ化して送信するユーザー識別情報 |

#### イベント名の対応表

TikTok Events APIで使用できる主なイベント名は以下の通りです。

| ビジネスイベント | Events APIのイベント名 |
|---|---|
| 購入完了 | `Purchase` |
| カートに追加 | `AddToCart` |
| お気に入り登録 | `AddToWishlist` |
| 会員登録完了 | `CompleteRegistration` |
| リード獲得（フォーム送信） | `SubmitForm` |
| ページビュー | `ViewContent` |

### ユーザーデータのハッシュ化について

TikTok Events APIでは、メールアドレスや電話番号などの個人情報をSHA-256でハッシュ化して送信する仕様になっています。sGTMのタグテンプレートによっては自動的にハッシュ化してくれるものもありますが、そうでない場合はGTMの変数としてハッシュ化処理を実装する必要があります。

```javascript
// sGTMのカスタム変数テンプレート（ハッシュ化の例）
const sendHttpGet = require('sendHttpGet');
const sha256 = require('sha256');

const email = data.email ? data.email.toLowerCase().trim() : '';
const hashedEmail = email ? sha256(email) : '';

return hashedEmail;
```

:::message
個人情報の取り扱いには注意が必要です。ハッシュ化前の生データをログに出力したり、不必要なサードパーティに送信したりしないよう設計してください。プライバシーポリシーへの記載も合わせて確認しましょう。
:::

---

## クライアントサイドGTMとの連携設定

### データ送信の流れ

sGTMを使ったTikTok Events APIの実装では、以下のようなデータフローになります。

```
ユーザーのブラウザ
  ↓（クライアントサイドGTMからHTTPリクエスト）
sGTMサーバー（GCP上）
  ↓（TikTok Events API呼び出し）
TikTokのサーバー
```

クライアントサイドGTMでは、GA4イベントタグを使ってsGTMへイベントデータを送信するのが一般的な構成です。

### クライアントサイドGTMの設定

クライアントサイドGTMに「GA4イベント」タグを設定し、送信先をsGTMのURLに変更します。

1. クライアントサイドGTMの「変数」→「組み込み変数の設定」でGA4関連の変数を有効にします。
2. 「タグ」から既存のGA4設定タグを開き、「サーバーコンテナのURL」にsGTMのURLを入力します。
3. これにより、GA4イベントデータがsGTMに転送されます。

### sGTM側のクライアント設定

sGTM側では「GA4クライアント」がデフォルトで利用可能です。このクライアントがクライアントサイドGTMから送られてきたGA4リクエストを受け取り、タグを起動します。TikTokタグのトリガーには「GA4イベント名が〇〇と一致する場合」という条件を設定しましょう。

---

## テストと動作確認

### GTMプレビューモードの活用

設定が完了したら、必ずテストを行いましょう。

1. クライアントサイドGTMのプレビューモードを起動し、対象ページにアクセスします。
2. 購入完了やカート追加などのコンバージョンアクションを実行します。
3. GTMプレビューのタグ一覧でGA4イベントタグが「発火済み」になっていることを確認します。

次に、sGTM側のプレビューも確認します。

1. sGTMのコンテナでもプレビューモードを起動します。
2. クライアントのGTMプレビューURLと接続します（プレビュー起動時に表示されるURLを使用）。
3. sGTM側でTikTokタグが発火し、イベントが送信されていることを確認します。

### TikTok Events Managerでの確認

TikTok広告マネージャーの「イベント」→「テストイベント」機能を使うと、Events APIから受信したデータをリアルタイムで確認できます。テストモードでイベントを送信し、正しく受信されているか確認しましょう。

:::message
本番環境への公開前に、テストイベントの受信を必ず確認してください。イベント名やパラメータに誤りがあると、TikTokの広告最適化に活用されないデータが送信され続けることになります。
:::

---

## まとめ

TikTok Events APIをサーバーサイドGTMで実装する主なステップをまとめると、以下のようになります。

1. **TikTok Events APIアクセストークンの発行** — TikTok広告マネージャーの「イベント」画面から取得します。
2. **sGTMコンテナのセットアップ** — GCPのCloud RunにsGTMをデプロイし、カスタムドメインを設定します。
3. **TikTokタグテンプレートの追加と設定** — Pixel IDとアクセストークンを入力し、イベント名とユーザーデータを設定します。
4. **クライアントサイドGTMとの連携** — GA4イベントタグの送信先をsGTMに変更し、データフローを構築します。
5. **テストと動作確認** — GTMプレビューとTikTok Events Managerで受信を確認してから公開します。

ブラウザ側の計測だけに頼っていた場合と比べて、コンバージョンの取りこぼしが減ることで、TikTok広告の自動最適化の精度向上が期待できます。特にiOSユーザーの購買行動が多いECサイトでは、導入の優先度が高い施策といえます。

実装には一定の技術的なハードルがありますが、GTMの操作に慣れている方であればステップごとに進めていくことができます。設定の際に不明な点があれば、TikTok for Business公式のヘルプページや本記事のようなガイドを参照しながら進めてみてください。

## 関連記事

- [GA4×GTMでLINE広告・TikTok広告のコンバージョン計測を設定する](https://zenn.dev/web_benriya/articles/ga4-gtm-line-tiktok-conversion-tracking)
- [GA4×GTMでサイト内検索キーワードを正しく計測する設定](https://zenn.dev/web_benriya/articles/ga4-gtm-site-search-tracking)
- [GTMのデータレイヤーを使ったGA4カスタムイベント設計のベストプラクティス](https://zenn.dev/web_benriya/articles/gtm-data-layer-ga4-custom-event-design)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
