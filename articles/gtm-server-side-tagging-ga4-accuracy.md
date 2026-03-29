---
title: "GTMのサーバーサイドタギングでGA4データの精度を上げる入門"
emoji: "🖥️"
type: "tech"
topics: ["gtm", "googleanalytics", "serverside"]
published: false
---

## ブラウザの広告ブロッカーがGA4データを欠損させている

GA4のデータ精度に疑問を感じたことはありませんか。

実際のところ、広告ブロッカーやITP（Intelligent Tracking Prevention）の影響で、クライアントサイドのGA4計測ではデータの10〜30%が欠損しているケースがあります。

その原因は、従来のGTM（クライアントサイド）がブラウザ上でJavaScriptを実行し、`google-analytics.com`や`googletagmanager.com`へ直接リクエストを送る仕組みにあります。
広告ブロッカーはこれらのドメインへのリクエストをブロックします。

サーバーサイドタギングは、この問題を解決するアプローチです。
ブラウザからのリクエストを自社ドメインのサーバー経由でGoogleのサーバーへ転送することで、ブロッカーの影響を受けにくくなります。

## サーバーサイドGTMの全体像

サーバーサイドGTMの構成は以下の通りです。

```
[ブラウザ]
  ↓ 自社ドメイン(sgtm.example.com)へリクエスト
[サーバーサイドGTMコンテナ]（Cloud Run / App Engine）
  ↓ サーバー側でタグを実行
[GA4] [Google Ads] [Facebook] など各サービス
```

ポイントは以下の3つです。

1. ブラウザは自社サブドメインに対してリクエストを送る
2. サーバーサイドGTMがリクエストを受け取り、各計測サービスへ転送する
3. Cookieが自社ドメインの1st partyとして設定される

## クライアントサイドとの違い

| 項目 | クライアントサイド | サーバーサイド |
|------|-------------------|---------------|
| 実行場所 | ブラウザ | サーバー |
| 広告ブロッカーの影響 | 受ける | 受けにくい |
| Cookie種別 | 3rd party（将来廃止） | 1st party |
| ITP対応 | Cookie有効期限7日〜24時間 | サーバーで設定可能 |
| ページ読み込み速度 | タグ数に比例して遅くなる | ブラウザ負荷が減る |
| コスト | 無料 | サーバー運用費が発生 |

## 構築方法1：Cloud Runで構築する

Google Cloudの公式ドキュメントでは、Cloud Runを推奨しています。

### 前提条件

- Google Cloudプロジェクトが作成済み
- 課金が有効になっている
- GTMのサーバーサイドコンテナが作成済み

### 手順1：サーバーサイドコンテナの作成

1. [GTM管理画面](https://tagmanager.google.com/)にログイン
2. 「コンテナを作成」→ ターゲットプラットフォームで「Server」を選択
3. コンテナが作成されたら「コンテナの設定」を開く
4. 「手動でプロビジョニング」を選択し、コンテナ設定の値を控える

### 手順2：Cloud Runへのデプロイ

Google CloudのCloud Shellまたはローカルの`gcloud` CLIで実行します。

```bash
# プロジェクトを設定
gcloud config set project YOUR_PROJECT_ID

# サーバーサイドGTMのDockerイメージをデプロイ
gcloud run deploy sgtm \
  --image gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable \
  --region asia-northeast1 \
  --platform managed \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 10 \
  --set-env-vars "CONTAINER_CONFIG=YOUR_CONTAINER_CONFIG"
```

`YOUR_CONTAINER_CONFIG`は、GTM管理画面の手順1で控えた値を設定します。

:::message
`--min-instances 1`を設定することで、コールドスタートによるレイテンシを回避できます。
ただしその分、最低限のCloud Run費用が常に発生します。
トラフィックが少ないサイトでは`0`にしてコスト最適化を検討してください。
:::

### 手順3：カスタムドメインの設定

Cloud Runにデプロイした後、自社サブドメインを紐づけます。

1. Cloud Runの管理画面で「カスタムドメインを管理」を開く
2. `sgtm.example.com`のようなサブドメインを設定
3. DNSレコードにCNAMEを追加

```
sgtm.example.com  CNAME  YOUR_CLOUD_RUN_URL.run.app
```

DNSの反映後、`https://sgtm.example.com`でアクセスできることを確認します。

## 構築方法2：App Engineで構築する

App Engineはインフラ管理が少なく済むため、小規模サイトでの導入に適しています。

### デプロイコマンド

```bash
# app.yamlを作成
cat > app.yaml << 'YAML'
runtime: custom
env: flex

env_variables:
  CONTAINER_CONFIG: "YOUR_CONTAINER_CONFIG"

automatic_scaling:
  min_num_instances: 1
  max_num_instances: 5
  cool_down_period_sec: 120
  cpu_utilization:
    target_utilization: 0.6

resources:
  cpu: 1
  memory_gb: 0.5
  disk_size_gb: 10
YAML

# デプロイ
gcloud app deploy
```

App Engineの場合、カスタムドメインはGoogle Cloud Consoleの「App Engine」→「設定」→「カスタムドメイン」から設定します。

## クライアントサイドGTMの設定変更

サーバーサイドGTMを構築した後、クライアントサイドGTMの設定を変更してリクエスト先を自社サーバーに向けます。

### GA4設定タグのサーバーコンテナURL設定

クライアントサイドGTMのGA4設定タグで、以下を設定します。

1. GA4設定タグを開く
2. 「タグの設定」→「サーバーコンテナに送信」にチェック
3. サーバーコンテナのURLを入力：`https://sgtm.example.com`

これにより、GA4のリクエストが`google-analytics.com`ではなく`sgtm.example.com`へ送信されるようになります。

## サーバーサイドGTMコンテナの設定

### GA4クライアントの確認

サーバーサイドGTMコンテナには、デフォルトでGA4クライアントが含まれています。
「クライアント」メニューで「GA4」クライアントが有効になっていることを確認します。

### GA4タグの作成

サーバーサイドコンテナにもGA4タグを作成します。

```json
{
  "タグの種類": "Google Analytics: GA4",
  "トリガー": "GA4クライアントからのリクエスト（All Pages）"
}
```

サーバーサイドのGA4タグでは、クライアントから受け取ったデータをそのままGA4へ転送します。

## 1st Party Cookieの設定

サーバーサイドGTMの大きなメリットの一つが、1st party cookieとしてGA4のクライアントIDを設定できる点です。

### HTTPレスポンスヘッダーでCookieを設定

サーバーサイドGTMのGA4クライアント設定で、以下を有効にします。

1. クライアントの設定を開く
2. 「HTTP Cookieを使用してクライアントIDを設定」を有効化
3. Cookie名：`_ga`（デフォルト）
4. Cookie有効期間：730日（2年）

これにより、Safariの ITP制限（7日〜24時間）を回避し、長期間のユーザー識別が可能になります。

:::message
ITPの制限はJavaScriptで設定されたCookieに適用されます。
サーバーサイドからHTTPレスポンスヘッダーで設定したCookieには、この制限が適用されません。
ただし、Appleの仕様変更により今後影響を受ける場合もあります。
:::

## コスト感

サーバーサイドGTMの運用コストは、サーバーのリクエスト処理量に依存します。

### Cloud Runの場合（目安）

| 月間PV | 概算月額費用 |
|--------|-------------|
| 10万PV | 約3,000〜5,000円 |
| 50万PV | 約8,000〜15,000円 |
| 100万PV | 約15,000〜30,000円 |

`--min-instances 0`にするとアイドル時のコストは抑えられますが、コールドスタートが発生します。

## 動作確認

### サーバーサイドGTMのプレビューモード

1. サーバーサイドGTMコンテナの「プレビュー」をクリック
2. デバッグURLが表示される
3. クライアントサイドGTMのプレビューと同時に使い、リクエストの流れを確認

### 確認すべきポイント

- リクエストがサーバーサイドGTMに到達しているか
- GA4クライアントがリクエストを正しく処理しているか
- サーバーサイドのGA4タグが発火しているか
- GA4のリアルタイムレポートでデータが確認できるか

## まとめ

サーバーサイドGTMの導入ポイントを整理します。

- 広告ブロッカーやITPによるデータ欠損を軽減できる
- 自社サブドメインを経由することで1st party cookieが利用可能になる
- Cloud RunまたはApp Engineで構築し、カスタムドメインを設定する
- 運用コストはPVに応じて月額数千円〜数万円
- クライアントサイドGTMとの併用で段階的に導入できる

データの精度向上は、分析結果の信頼性に直結します。
広告ブロッカーの普及率が上がり続けている現在、サーバーサイドタギングの導入は検討に値する施策です。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
