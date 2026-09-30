---
title: "Cloudflare Pages 移行後、独自ドメインの MX が _dc-mx 経由で Pages を向いていた — 検証手順と Google Workspace への切り替え"
emoji: "📭"
type: "tech"
topics: ["cloudflare", "dns", "googleworkspace", "email"]
published: false
publish_queue: true
published_at: "2026-10-03 13:00"
---

## はじめに

自分の運営サイト（logical-web.jp）は、2026年9月に Xserver から Cloudflare Pages へ移行しました。ネームサーバーは Cloudflare（edward.ns.cloudflare.com / gracie.ns.cloudflare.com）です。

2026-09-29 に独自ドメインのメールを Google Workspace で開設しようとして DNS を確認したところ、MX の宛先が Cloudflare Pages の IP に解決されていました。つまり @logical-web.jp 宛てのメールは、どこにも届いていなかったことになります。エラーは一切出ていません。お問い合わせフォームは Formspree 経由で、メール設定とは独立しているため影響はありませんでした。

この記事では、発見に使った検証手順、`_dc-mx` の仕組み、Google Workspace への切り替えで実際に追加・削除されたレコード、DKIM と DMARC までを記録します。いつから届いていなかったかは特定できていません。

## 症状: 壊れても何も通知されない

送信側にエラーが戻るかどうか、いつ戻るかは送信側のメールサーバー次第です。受信側（こちら）には何も起きず、自分の環境では受信の記録を確認する手段もありませんでした。

自分の場合は Workspace 開設の下調べで MX を引くまで気づきませんでした。ホスティング移行は「サイトが表示されること」で完了を判断しがちで、MX は見ていなかったのが原因です。

## 検証手順: MX → 宛先の A/CNAME → 行き先がメールサーバーか

dig が無い環境でも、DoH（DNS over HTTPS）を curl で叩けば同じことができます。以下は Cloudflare の DoH エンドポイントを使う例です。

```bash
# 1. MX を引く
curl -s "https://cloudflare-dns.com/dns-query?name=example.com&type=MX" \
  -H "accept: application/dns-json"

# 2. MX の宛先ホスト名を A で引く
curl -s "https://cloudflare-dns.com/dns-query?name=mail.example.com&type=A" \
  -H "accept: application/dns-json"

# 3. SPF（TXT）を引く
curl -s "https://cloudflare-dns.com/dns-query?name=example.com&type=TXT" \
  -H "accept: application/dns-json"
```

見るのは3段です。

1. MX の `data` に何が入っているか（優先度と宛先ホスト名）
2. その宛先ホスト名が何に解決されるか（A、または CNAME → A）
3. 解決先の IP がメールサーバー（SMTP を受けるホスト）か

今回の実測値（2026-09-29、cloudflare-dns.com）は次のとおりです。

```
MX   0 _dc-mx.xxxxxxxxxxxx.logical-web.jp.
A    _dc-mx.xxxxxxxxxxxx.logical-web.jp
       → CNAME logical-web-jp.pages.dev.
       → 172.66.44.247 / 172.66.47.9
```

3段目で破綻しています。解決先は `pages.dev` への CNAME、つまり Pages のホスティング先で、メール受信用ではないと判断しました（25番ポートへの接続は試していません）。

もう1点、存在しないサブドメイン（例: zzz-test.logical-web.jp）に A を問い合わせても応答が返りました。ワイルドカードレコードがある状態です。「名前が引ける」ことは「その名前が意図どおりに設定されている」証拠にならないので、存在しないはずの名前を引いて比較する確認は有効でした。

SPF の現状は次のとおりです。

```
v=spf1 +a:svXXXXX.xserver.jp +a:logical-web.jp +mx include:spf.sender.xserver.jp ~all
```

Xserver 時代の記述がそのまま残っています。

## `_dc-mx` とは何か

Cloudflare の公式ドキュメント（Unexpected DNS records）には、次の説明があります。

> When your MX or SRV record resolves to a domain configured to proxy through Cloudflare, Cloudflare dynamically inserts a record into DNS responses.
> This record is added at query time to ensure that mail or service traffic bypasses the Cloudflare proxy and reaches your server directly.

https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/unexpected-dns-records/

つまり本来は、プロキシ配下のドメインを MX が指していても、メールのトラフィックだけはプロキシを迂回して元サーバーへ直接届けるための仕組みです。公式の説明では、このレコードはクエリ時に動的に挿入されます。

問題は、今回それが Pages の IP を向いていた理由です。ここからは**推測**です。Pages の apex ドメインへのカスタムドメイン設定は CNAME を作り、apex では CNAME flattening で解決されると理解しています（[Pages custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/)、[CNAME flattening](https://developers.cloudflare.com/dns/cname-flattening/)）。Xserver から Pages へ apex を切り替えた際に、MX が apex 由来の宛先を引き継ぎ、`_dc-mx` の行き先が Pages になった可能性があります。ただし、移行時の DNS 変更履歴を追っていないため、断定はできません。

## 修正: Google Workspace の自動設定

メールは Google Workspace（Business Starter）にしました。Cloudflare Email Routing は無料ですが、受信と転送のための機能で、人が日常のメールとして独自アドレスから送る用途には使えないため採用しませんでした（[公式](https://developers.cloudflare.com/email-routing/)）。アプリから送る Email Sending は別にありますが、Beta で有料プランが前提です（[公式](https://developers.cloudflare.com/email-service/)）。

Google の設定画面で「Cloudflare にログイン」を選ぶと、Cloudflare 側に Authorize 画面が出て、DNS レコードを自動設定できます。流れは2段階でした。

**ドメイン確認**: google-site-verification の TXT が追加されます。

**Gmail 有効化**: 同様の承認画面が再度出て、次の変更が入りました。

| 操作 | 内容 |
|---|---|
| 追加 | MX 5本（1 ASPMX.L.GOOGLE.COM / 5 ALT1 / 5 ALT2 / 10 ALT3 / 10 ALT4） |
| 置換 | SPF を `v=spf1 +a:svXXXXX.xserver.jp +a:logical-web.jp +mx include:spf.sender.xserver.jp include:_spf.google.com ~all` に |
| 削除 | 旧 MX と旧 SPF |

削除は「Authorize and Delete conflicts」の画面で、ドメイン名を入力して確定する形でした。誤操作防止の確認だと思います。

補足が2点あります。まず MX について、Google の現行推奨は `smtp.google.com` 1本です（[公式](https://knowledge.workspace.google.com/admin/domains/set-up-mx-records-for-google-workspace)）。aspmx 系の旧値も引き続きサポートされると書かれています。今回の自動設定では旧方式の5本が入った、という観察結果です。動作に問題は出ていません。

次に SPF です。SPF レコードが2本あると permerror になります（[RFC 7208 §4.5](https://www.rfc-editor.org/rfc/rfc7208#section-4.5)）。手で足す場合は「TXT を追加」してしまいがちですが、今回の自動設定は追加ではなく**置換**だったので、2本になる状態は避けられました。手動で設定する場合は、追記ではなく既存の1本へ `include:` を足す必要があります。

切り替え後、cloudflare-dns.com と dns.google の両方で、MX は Google の5本のみ、SPF は1本になっていることを確認しました。

## DKIM と DMARC

### DKIM

管理コンソールの「アプリ > Google Workspace > Gmail > メールの認証」で、2048bit・セレクタ `google` の鍵を生成しました。表示された値を Cloudflare に TXT `google._domainkey` として手で追加し、「認証を開始」を押します。Google の公式には、Gmail 有効化後に 24〜72 時間待つ必要がある場合があるとあります（[公式](https://knowledge.workspace.google.com/admin/security/set-up-dkim)）。

### DMARC

`_dmarc` の TXT は、最初はレポート収集だけの `p=none` で始めました。

```
v=DMARC1; p=none; rua=mailto:dmarc@example.com
```

`rua` の宛先は記事用のダミーです。数週間レポートを見て、正規の送信元がすべて認証を通っていると確認できてから `quarantine` へ上げる予定です。

なお Gmail の送信者ガイドラインでは、全送信者に SPF または DKIM、1日5,000通以上送る場合は SPF・DKIM・DMARC がすべて求められます（[公式](https://support.google.com/a/answer/81126)）。少量送信でも、先に揃えておいて損はないと考えています。

## 移行チェックリスト

ホスティング移行のとき、自分は次を確認する運用に変えました。

1. 移行前に MX / SPF / DKIM / DMARC の現状を DoH で保存しておく
2. 移行後に同じコマンドを再実行し、差分を見る
3. MX の宛先を A で引き、解決先がメールサーバーであることを確認する
4. `_dc-mx` のように動的に挿入されるレコードは、ダッシュボードでは見えないので、必ずクエリ結果で見る
5. ワイルドカードの有無を、存在しない名前を引いて確認する
6. 可能なら、外部の別アドレスから実際にテストメールを送り、着信まで確認する

## まとめ

移行後に確認するのは「サイトが表示されること」だけでは足りず、MX が最終的にメールサーバーへ届く名前になっているかまで見る必要がありました。`_dc-mx` は本来プロキシを迂回するための仕組みですが、宛先がホスティング側を向いていれば役に立ちません。

残課題は、SPF に残る Xserver の記述です。Xserver から送信していないと確認できたら外します。

経営判断としての側面（なぜ気づけなかったのか、どこまで影響があり得るのか）は、自サイトの記事に書きました。
https://logical-web.jp/blog/site-hikkoshi-mail-todokanai/
