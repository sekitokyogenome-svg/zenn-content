---
title: "Node.js のセキュリティ修正版に Cloudflare Pages で固定したらビルドが落ちた — 原因と再固定まで"
emoji: "🛡️"
type: "tech"
topics: ["nodejs", "cloudflare", "githubactions", "astro", "security"]
published: false
publish_queue: true
---

## この記事でわかること

- 2026-10-21 の Node.js セキュリティリリースで、静的サイトの運用のどこに Node.js が残っているかを洗い出した手順
- GitHub Actions と Cloudflare Pages のビルドで、Node.js のバージョンを固定したやり方
- バージョンを上げても、ビルド結果が変わっていないことを確かめた方法

## 前提

- 対象: 自分のサイト（Astro の静的サイト、Cloudflare Pages で配信、GitHub Actions で定期処理）
- 確認日: 2026-10-21
- この記事のバージョン番号や日付は、Node.js と Cloudflare の公式ページで確認したものです。Cloudflare Pages 側で実際に新しいバージョンが使われたかは、記事の最後に書くとおり、管理画面のビルドログで確認する必要があります

## リリースの中身

[Node.js の告知](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)（2026-10-21 付け）によると、26.x / 24.x / 22.x 向けに修正版が出ました。

| 系統 | 修正版 |
|---|---|
| 22.x | v22.23.4 |
| 24.x | v24.22.1 |
| 26.x | v26.12.1 |

修正は10件で、最も重いものは high です。Brotli デコーダーの範囲外書き込みによる遠隔コード実行のおそれ（CVE-2026-111497）や、TLS 証明書のホスト名検証をすり抜けられる問題（CVE-2026-105483、CVE-2026-106069）などが含まれます。系統によって対象外のものもあり、たとえば CVE-2026-105483 は 26.x と 24.x だけが対象です。告知には「サポートが終了したバージョンは、セキュリティリリースのたびに常に影響を受ける」とも書かれています。

## どこで Node.js が動いているかを棚卸しする

静的サイトなので、本番では Node.js は動いていない、と最初は考えました。実際に洗い出すと、4か所に分かれました。

| 場所 | 中身 | 判断 |
|---|---|---|
| 本番の配信 | ビルド済みの HTML を Cloudflare Pages が配信 | Node.js は動いていない |
| Pages Functions | 旧 URL に 410 を返す小さな関数 | Cloudflare Workers の実行環境で動く。リポジトリに Node 互換（`nodejs_compat`）の設定はなく、関数も Node の API を使っていない |
| GitHub Actions | 定期処理2本が `actions/setup-node` で **Node 20** を指定 | Node 20 はサポート終了済み |
| Pages のビルド | リポジトリでバージョンを指定していない | Cloudflare の既定のバージョン任せ |

ワークフローは次の grep で見つかりました。

```bash
# ワークフローで指定している Node.js のバージョンを洗い出す
grep -rn "node-version" .github/workflows/
```

Node 20 のサポート終了日は、Node.js の公式のスケジュール（[nodejs/Release の schedule.json](https://github.com/nodejs/Release/blob/main/schedule.json)）で 2026-04-30 です。今回の修正は Node 20 には出ません。

Cloudflare Pages の既定のバージョンは、[ビルドイメージのページ](https://developers.cloudflare.com/pages/configuration/build-image/)によると v3 のビルドシステムで 22.16.0 です（2026-10-21 確認）。自分のプロジェクトがどのビルドシステムかは確認していませんが、v3 なら、修正前の 22 系でビルドしていたことになります。同じページは、既定のバージョンが変わるのを避けたい場合はバージョンを指定するよう勧めています。

## バージョンを固定する

### GitHub Actions

```yaml
# .github/workflows/*.yml の setup-node（24 系の最新を取りにいく）
- uses: actions/setup-node@v4
  with:
    node-version: "24"
    check-latest: true
```

最初は `node-version: "24"` だけにしていましたが、それでは不十分でした。[setup-node の README](https://github.com/actions/setup-node/blob/main/README.md) によると、まずランナーに入っている版（キャッシュ）から条件に合うものを探し、`check-latest` は既定で false です。ランナーに古い 24.x が入っていれば、それが使われる可能性があります。`check-latest: true` を足すと、最新の 24.x を確認しにいきます。

なお、`actions/setup-node` 自体にも新しいメジャー版が出ています。ここでは既存のワークフローに合わせて `@v4` のままにしています。

### Cloudflare Pages のビルド

```bash
# Pages のビルドで使う Node.js を固定する（中身はバージョン番号だけ）
echo "24.22.1" > site/.nvmrc
```

Cloudflare のページには、`.nvmrc` か `.node-version` を「プロジェクトのルートディレクトリ」に置くとあります。自分のプロジェクトはルートディレクトリが `/site` なので、`site/.nvmrc` に置きます。環境変数 `NODE_VERSION` でも指定できます。

Actions と違い、こちらは版を固定しています。次のセキュリティリリースでは、`.nvmrc` の版を自分で上げる必要があります。

### ここでビルドが落ちた

リリース当日（2026-10-21）にこれを push したところ、Cloudflare Pages のビルドが2回続けて失敗しました。ログの要点です。

```text
Detected the following tools from environment: nodejs@24.22.1
Installing nodejs 24.22.1
Trying to update node-build... ok
node-build: definition not found: 24.22.1
CFPAGESLOG:ASDF_RETRY: nodejs 24.22.1 not found in image, updating plugin and retrying...
node-build: definition not found: 24.22.1
Failed: build command exited with code: 1
```

`.nvmrc` は正しく読まれていました。失敗したのは、そのあとのインストールです。Pages のビルド環境は、asdf の node-build プラグインで Node.js を入れています。その node-build に、**公開されたばかりの 24.22.1 の定義がまだ無かった**のが原因でした。

node-build の定義は GitHub で公開されているので、次のように確かめられます。

```bash
# node-build に指定の版の定義があるか（200 なら有る、404 なら無い）
curl -s -o /dev/null -w "%{http_code}\n" \
  https://raw.githubusercontent.com/nodenv/node-build/master/share/node-build/24.22.1
```

10/21 の時点では 24.22.0 は 200、24.22.1 は 404 でした。

本番のサイトは、最後に成功したデプロイがそのまま配信されるので、表示は止まりません。ただ、新しいデプロイが通らない間は、予約投稿も公開されません。そこで `.nvmrc` をいったん外して既定の版に戻し、定義が入るのを待ちました。

### 定義が入ってから再固定する

2026-10-23 の朝には、24.22.1（ほかに 22.23.4、26.12.1）の定義が 200 になっていました。`site/.nvmrc` を戻して push し、Pages のデプロイが成功したことを管理画面で確認しました。

公開直後の版に固定するときの手順は、次のとおりにしています。

1. 上の `curl` で、node-build に定義があることを確かめる
2. `.nvmrc` を push する
3. Pages の管理画面で、デプロイが成功したかを確かめる（push しただけで終わりにしない）

### 24 と 26 のどちらにするか

公式のスケジュールでは、24 系は 2026-10-20 にメンテナンス期間に入り、サポート終了は 2028-04-30 です。26 系は 2026-10-28 に LTS になる予定です。今回はすぐ使える LTS として 24 を選び、26 は LTS になってから検討することにしました。

## ビルド結果が変わっていないことを確かめる

バージョンを上げてサイトの出力が変わっていたら、見た目や計測が壊れるおそれがあります。Node 24.22.1 で `npm ci` からビルドし、Node 22 のビルド結果とファイルごとに比べました。

```bash
# Node 24.22.1 を公式から取得し、チェックサムを照合してから使う
curl -sS -O https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz
curl -sS -O https://nodejs.org/dist/v24.22.1/SHASUMS256.txt
grep linux-x64.tar.xz SHASUMS256.txt | sha256sum -c -
```

```bash
# 2つのビルド結果（dist）の全ファイルのハッシュを比べる
(cd dist-node22 && find . -type f | sort | xargs md5sum) > d22.txt
(cd dist-node24 && find . -type f | sort | xargs md5sum) > d24.txt
diff d22.txt d24.txt && echo "同一"
```

788 ファイルすべてで一致しました。少なくとも自分のサイトでは、Node のバージョンを上げても、配信される中身は1バイトも変わりませんでした。

## 手元で試したときの注意: npm がインストールスクリプトを実行しなかった

手元で Node 24.22.1 を公式から取得し、付いてくる npm（11.19.1）で `npm ci` をすると、次の警告が出ました。

```text
3 packages have install scripts not yet covered by allowScripts:
  esbuild@0.27.7 (postinstall: node install.js)
  sharp@0.34.5 (install: node install/check.js || npm run build)
  esbuild@0.25.12 (postinstall: node install.js)
```

esbuild と sharp のインストール時のスクリプトは、実行されなかったとみられます。それでもビルドは通り、出力も上のとおり Node 22 と同じでした。自分のサイトでは影響がありませんでしたが、インストール時のスクリプトに頼るパッケージを使っている場合は、ビルドが通るかを先に確かめておくべきです。この警告の仕様は、npm のドキュメントでは確認していません。上は自分の環境での出力です。なお、Cloudflare Pages のビルドログでは npm は 10.9.2 と表示されていて、手元とは版が違いました。Pages のビルドで同じことが起きるとは限りません。

## 確認したこと

- Cloudflare Pages: 2026-10-23 の再固定後、デプロイが成功した（管理画面で確認）
- GitHub Actions: Node 24 に変えた後の定期処理は、3回とも成功した

## まとめ

- 静的サイトでも、ビルドと CI には Node.js が残っている。今回は CI がサポート終了の Node 20、Pages のビルドがバージョン未指定だった
- 公開直後の版に Pages で固定すると、node-build に定義が入るまでビルドが落ちる。固定の前に定義の有無を確かめ、push の後はデプロイの成否まで見る
- Actions は `node-version: "24"` と `check-latest: true`、Pages は `site/.nvmrc` で 24.22.1 に固定した。ビルド結果がファイル単位で同一なことも確かめた
- 次のリリースでは `.nvmrc` を上げる。26 系は LTS になってから検討する

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
