---
title: "Claude Code × Google Workspace を認証なしで試せるところまで試した — gws と公式リモート MCP の現状（2026-10）"
emoji: "🧰"
type: "tech"
topics: ["claudecode", "googleworkspace", "mcp", "cli", "gmail"]
published: false
publish_queue: true
---

## この記事でわかること

- Google Workspace 向けの `gws` CLI と、Google 公式のリモート MCP サーバーの現状（2026-10-10 時点で自分が確認できた範囲）
- 認証（OAuth）をしなくても試せること、できなかったこと
- 本番のアカウントにつなぐ前に決めておくとよいこと

## 前提と、この記事の範囲

先に範囲を書きます。**自分は Google アカウントの認証を一切していません。** 実際のメール・ファイル・予定には触れておらず、この記事のキャプチャはすべて「認証なしで動いた部分」の出力です。

- 実行環境: クラウド上の使い捨てのコンテナ（Node.js 22、Claude Code 2.1.296）
- 確認日: 2026-10-10
- 試していないこと: OAuth の完了、実データの読み書き、スコープごとの挙動、claude.ai の Google コネクタ、プロンプトインジェクションへの耐性

「認証して動いた」とは書けない部分は、そう明記します。

## 話題になっている組み合わせは2系統ある

| 系統 | 中身 | 提供状況（確認できた範囲） |
|---|---|---|
| gws（Google Workspace CLI） | `gws drive files list` のように、Workspace の API をコマンドから呼ぶ | GitHub の公式 org（googleworkspace/cli）。README に "not an officially supported Google product"、v1.0 までは破壊的変更があり得ると書かれている |
| Google Workspace リモート MCP サーバー | Gmail・Drive・Docs・Sheets・Calendar などを MCP で公開 | Google の公式ページ（[Configure the Google Workspace MCP servers](https://developers.google.com/workspace/guides/configure-mcp-servers)）で Developer Preview。ページの最終更新表示は 2026-09-18 |

別に、claude.ai の Gmail / Drive / Calendar コネクタ（[公式ヘルプ](https://support.claude.com/en/articles/10166901-use-google-workspace-connectors)）があります。これは claude.ai 側の機能で、この記事では扱いません。

## gws: 認証なしで動いたもの

`npm install @googleworkspace/cli` で入りました。npm 上の最新は 0.22.5 で、最終更新は 2026-03-31 です（2026-10-10 に確認）。

### サービス一覧

```bash
# バージョンとサービス一覧を表示する
gws --version
gws --help
```

![gws --help の出力](/images/claude-code-google-workspace-gws-trial/01_help.png)

Drive・Sheets・Gmail・Calendar・Docs・Slides など 18 のサービスが並びます。認証用の環境変数（`GOOGLE_WORKSPACE_CLI_TOKEN` や `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE` など）も、ここで確認できます。

### `--dry-run`: 送らずにリクエストを見る

```bash
# 実際には送らず、どんなリクエストになるかだけを表示する
gws drive files list --params '{"pageSize":3}' --dry-run
```

![dry-run の出力](/images/claude-code-google-workspace-gws-trial/03_dryrun.png)

認証なしでも、リクエストの URL・メソッド・パラメータが表示されました。Gmail の送信 API でも同じで、`POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send` と本文が表示されるだけで、送信はされません。

![Gmail 送信の dry-run](/images/claude-code-google-workspace-gws-trial/05_gmail_dryrun.png)

AI に操作を任せる前に、「どの API を呼ぶ構えになっているか」を人間が目で確かめる用途に使えます。

### 認証なしで本番の呼び出しをすると

```bash
# --dry-run なしで実行する（認証情報は未設定）
gws drive files list --params '{"pageSize":3}'
```

![認証なしの実行結果](/images/claude-code-google-workspace-gws-trial/04_noauth.png)

`401`（`No credentials provided`）で止まります。資格情報なしでは API に何も届きません。

### 記事や README と食い違った点

- 二次情報では `gws mcp` という MCP モード（`gws mcp -s drive,gmail,calendar` など）が紹介されています。0.22.5 では `gws mcp` を実行すると `Unknown service 'mcp'` になりました。**この版には MCP モードはありません。**

![gws mcp の出力](/images/claude-code-google-workspace-gws-trial/08_gws_mcp.png)
 古い記事の手順をそのまま試さないよう注意してください

## 公式リモート MCP: 認証なしで見えたもの

Google の公式ページには、サービスごとのエンドポイント（`https://<service>/mcp/v1`、例: `gmailmcp.googleapis.com`）が載っています。2026-10-10 に、自分のコンテナから `initialize` と `tools/list` を送ると、認証なしで応答がありました。

![tools/list の結果](/images/claude-code-google-workspace-gws-trial/07_mcp_tools.png)

数と顔ぶれは次のとおりです（2026-10-10 時点の応答。Developer Preview なので変わり得ます）。

| サーバー | ツール数 | 書き込み・削除に当たるもの |
|---|---:|---|
| Gmail | 23 | 下書き作成、ラベル操作、ゴミ箱への移動、スパム指定 |
| Drive | 8 | ファイル作成、コピー |
| Calendar | 9 | 予定の作成・更新・削除、出欠の返信 |
| Docs | 2 | `update_doc` |
| Sheets | 6 | 値・数式の更新、行列の挿入 |

目についた点が2つあります。

- **2026-10-10 の応答では、Gmail にメール送信のツールがありません。** 下書き（`create_draft`）までです。`tools/list` の結果に `send` を含む名前がなく、送信の最終操作は人が行う設計に見えます（意図の説明は公式にはありません。確認できたのはツール名の一覧だけです）。公式ページはスコープに `gmail.compose` も挙げているので、この状態が続くとは限りません。また、`gws` は API を直接呼ぶ別物で、送信 API の `--dry-run` は上のとおり表示できます。「Gmail は送れない」と一般化しないでください
- **Calendar には削除（`delete_event`）があります。** 読み取り専用のスコープで運用するか、削除を許す前に確認を挟むかを決めておく価値があります。ただし、公式ページの Calendar のスコープ一覧は読み取り・空き時間の系統だけで、`delete_event` がどのスコープで通るかは自分では確認していません
- **公式ページの一覧とは数が違います。** 公式ページに載っている Gmail のツールは10個で、自分の応答では23個でした（ゴミ箱・スパム指定・ラベル作成などは公式ページに載っていません）。Drive・Calendar・Docs・Sheets は公式ページの一覧と一致しました。Preview の間は、ページと実際の応答がずれ得ます

なお、ツールの一覧が見えても、実際に呼び出すには OAuth が必要です。この記事ではそこまで進めていません。

## Claude Code への登録

Claude Code のリモート MCP は、OAuth クライアントを指定して追加できます（[公式](https://code.claude.com/docs/en/mcp)）。登録そのものはローカルの設定変更です。

```bash
# Google のリモート MCP（Gmail）を、ダミーのクライアント ID で登録する（認証はしない）
claude mcp add --transport http --client-id DUMMY.apps.googleusercontent.com \
  --callback-port 8080 gmail https://gmailmcp.googleapis.com/mcp/v1
claude mcp get gmail
```

![claude mcp の登録と確認](/images/claude-code-google-workspace-gws-trial/06_claude_mcp.png)

`claude mcp get` は `Connected` と表示しましたが、**これは認証が通ったという意味ではありません。** 上のとおりサーバーが認証なしの `initialize` に応答するため、接続の確認だけが通っていると読んでいます（自分の解釈です）。OAuth を完了できるかは、未確認です。

もう一つ、未確認の点があります。Google の公式手順は、Claude 向けのリダイレクト URI として `https://claude.ai/api/mcp/auth_callback` を登録する形で、Claude Code の `localhost` のコールバックについては書かれていません。**Claude Code から Google のリモート MCP の OAuth が通るかは、自分では確かめていません。**

## 本番のアカウントにつなぐ前に決めること

ここからは試した結果ではなく、公式の記述から導ける注意点です。

1. **スコープは読み取りから**: Google の MCP のスコープ一覧には `gmail.readonly`・`drive.readonly` のような読み取り専用があります。まず読み取りだけで運用し、書き込みは必要になってから足します（推奨そのものが公式の文言という意味ではありません）
2. **間接プロンプトインジェクション**: Google の公式ページは、信頼できるツールだけを使うこと、AI の操作をすべて確認することを勧めています。メール本文や共有ドキュメントに仕込まれた指示を、AI が実行してしまう危険です
3. **検証用のアカウント**: 本番の業務アカウントではなく、テスト用のアカウントやテスト用のドメインから始める
4. **gws の安全機能**: README によると、`--dry-run` と、Model Armor によるレスポンスのスキャン（`GOOGLE_WORKSPACE_CLI_SANITIZE_MODE`）があります。後者の防御が実際にどれだけ効くかは、一次情報で確認できていません

## まとめ

- gws は認証なしで、サービス一覧・スキーマ確認・`--dry-run` までは動く。実行には認証が必要（`401` で止まる）。0.22.5 に MCP モードは無い
- 公式リモート MCP は Developer Preview。2026-10-10 の応答では、Gmail は下書きまでで送信ツールが無い
- 次にやること: テスト用アカウントで OAuth を通し、読み取りスコープだけで動かして、Claude Code からの認証（localhost コールバック）が通るかを確かめる

---

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
