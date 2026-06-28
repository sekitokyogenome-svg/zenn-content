---
title: "ココナラ154件、3時間で構造化した実装ログ（Playwright × 構造的ダミー化）"
emoji: "📦"
type: "tech"
topics: ["playwright", "typescript", "scraping", "claudecode", "gcp"]
published: true
---

## 自分のプラットフォーム履歴を、丸ごと取り出す話

ココナラで7年間に積み上げた取引履歴154件を、3時間で全件構造化データにした。

やったことを並べると、

- Playwright で認証突破
- 154件のトークルーム HTML をバルク取得（48分・エラーゼロ）
- 構造的判定でダミー化（顧客名リストに依存しない）
- HTML から JSON への正規化

きっかけは、自社サイト（logical-web.jp）の事例ページに「ご相談パターンを 154件分のデータから可視化したい」と思ったこと。
管理画面を開いて目視で集計するのは現実的じゃないし、過去の取引パターンを構造化しておけば、サービス改善や記事素材にも転用できる。

この記事では、認証付き SPA（ココナラは Vue.js ベース）からどうやって取り出したか、ダミー化をどう機械的に詰めたかを実装寄りに書いていく。

## 課題：ココナラには CSV エクスポートがない

ココナラを使っている人で、「自分の取引履歴を分析したい」と思ったことがある人は意外と多いんじゃないかと思う。
ただ、ココナラ側には2026年5月時点で、取引履歴の CSV エクスポート機能がない。管理画面はすべて WebUI で、データを構造化された形では取り出せない。

最初に検討した選択肢を並べると、

- ❌ `requests` / `scrapy` でスクレイピング → ココナラは Vue.js SPA で、HTML だけ取っても中身は空
- ❌ 1件ずつ手作業でコピペ → 154件で確実に破綻する
- ❌ 顧客名リストを作って GREP 置換 → リストの漏れで個人情報が残るリスク
- ✅ Playwright + `storage_state`（ログイン状態を JSON 保存）
- ✅ 構造的判定（DOM セレクタ起点で顧客名を抽出して全置換）
- ✅ 監査スクリプトで残存検知 → 漏れゼロまで詰める

最終的に右側の3つで実装した。`storage_state` 方式は、API ログインが reCAPTCHA 等で詰まっている SaaS にも有効な気がしている。

## 設計：3つの判断

### 1. 認証は手動 + `storage_state` 方式

API ログインを実装しようとすると、reCAPTCHA・2FA・session token の更新ロジックなどで複雑化する。
今回は「自分が使うツール」だったので、Playwright で**一度だけ手動ログイン**して、状態を `auth/storage_state.json` に保存する方針にした。

```typescript
// src/auth.ts の核
import { chromium } from 'playwright';

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({
  locale: 'ja-JP',
  timezoneId: 'Asia/Tokyo',
});
const page = await context.newPage();

await page.goto('https://coconala.com/login');
console.log('ブラウザで手動ログインを完了させてから Enter を押してください');
await waitForEnter();

await context.storageState({ path: 'auth/storage_state.json' });
await browser.close();
```

以降のスクリプトはこの JSON を `storageState` オプションで読み込むだけで、ログイン済みの状態を再利用できる。Cookie の有効期限が切れたら再実行すればいいだけなので運用も楽。

### 2. 取捨選択は分析時にやる、取得は全件

154件 × 約30MB ≒ 5GB。ストレージ的には全く問題ない。
**全件をローカルに生 HTML で持つ方針**にしておくと、

- 後でダミー化スクリプトを改良したくなった時に、再取得せずに再ダミー化できる
- 顧客名カタログ育成の過程で漏れに気づいても、生 HTML から修正できる

逆に「フィルタしながら取得」を選ぶと、設計を間違えた時に再取得が必要になり、5〜15秒のランダム待機を含めて48分を再走することになる。これは避けたい。

### 3. ダミー化は構造的判定 + 監査ループ

ダミー化で一番怖いのは「漏れ」だ。リスト依存だと、新しい顧客が増えるたびに人間がリストを更新する必要があり、必ず漏れる。

そこで、**DOM セレクタを起点に顧客名を機械抽出する方式**にした。HTML パーサは `jsdom` を採用（Vue.js が描画した DOM をそのまま扱えるため）。

```typescript
// tools/sanitize_v2.ts の核
import { JSDOM } from 'jsdom';

const dom = new JSDOM(html);
const doc = dom.window.document;
const customerNames = new Set<string>();

// 自分の自称（置換から除外する）
const OWN_ALIASES = ['自分', /* ... */];

// メッセージ送信者名のセレクタから顧客名候補を抽出
const elements = doc.querySelectorAll('.d-messageInfo_userName');
for (const el of Array.from(elements)) {
  const name = el.textContent?.trim() || '';
  if (name && !OWN_ALIASES.includes(name)) {
    customerNames.add(name);
    el.textContent = '[CLIENT_NAME]';
  }
}

// 全 HTML に対しても保険として一括置換
let output = dom.serialize();
for (const name of customerNames) {
  output = output.replace(new RegExp(escapeRegex(name), 'g'), '[CLIENT_NAME]');
}
```

実際の `sanitize_v2.ts` ではこれを発展させて、8カテゴリの構造的置換を入れている。

1. メッセージ送信者名（`.d-messageInfo_userName`）
2. 購入者情報セクション（`.d-talkroomBuyerInfo`）
3. グループチャット参加者の英字ID（`.d-talkroomGroupChatMembers_membersText`）
4. システムメッセージ内の英字ID（`.d-defaultMessage`）
5. `<title>` / `<meta>` タグ
6. 画像 URL（`example.com/dummy.png` に置換）
7. メッセージ本文の長文（`.d-normalMessage` 内・20字以上の日本語）
8. 取引タイトルヘッダ（`.p-talkrooms_mainHeader`）

加えて、HTML 全体に対する正規表現置換で、金額（`¥XX,XXX`）・メールアドレス（`[EMAIL]`）・電話番号（`[PHONE]`）も潰す。

そのうえで、`audit_sanitized.ts` という監査スクリプトを走らせ、上記が残っていないか全 154件をチェックする。検出があれば patch スクリプトを書いて適用する。フィードバックループを4周ほど回した結果、最終的に**154件すべて検出ゼロ**まで到達した。

## 実装の手順

実際の作業フローを順番に並べると次のようになる。

### ① ログイン状態を保存

```bash
npm run auth
# → ブラウザ起動 → 手動でログイン → Enter で auth/storage_state.json に保存
```

### ② 全タブ URL の構造を特定

ココナラには「要対応 / 見積り / 取引中 / 完了 / キャンセル / 保存済み / ゴミ箱」の7タブがあり、それぞれにページネーション構造がある。`discover_tabs.ts` で各タブのページネーション URL を機械的に把握しておく。

### ③ 取引 ID を全件リスト化

```bash
npm run list
# → 全タブを巡回して取引 ID を data/normalized/transaction_ids.json に保存
# 結果: 154件（取引中 1 / 完了 151 / キャンセル 2）
```

### ④ トークルーム HTML をバルク取得

```bash
npm run extract:all
# → 154件すべての HTML を data/raw/talkrooms/<id>.html に保存
```

5〜15秒のランダム待機を遵守して、所要48分。途中エラーゼロ、リトライ不要だった。

### ⑤ 構造的ダミー化

```bash
npx tsx tools/sanitize_v2.ts
```

8カテゴリの構造的置換 + 正規表現置換を全 154件に適用 → `data/sanitized/talkrooms/<id>.html` に出力。

### ⑥ 監査と patch

```bash
npx tsx tools/audit_sanitized.ts
# → 検知された残存パターンを data/normalized/audit_report.json に出力

# 検知に応じて patch を当てる
npx tsx tools/patch_amounts.ts       # 金額の取りこぼし
npx tsx tools/patch_extra_names.ts   # 個別名の取りこぼし

# 再監査
npx tsx tools/audit_sanitized.ts
# → 検出ゼロになるまで繰り返し
```

監査側には `isLikelyUiText()` フィルタを実装してあり、「プラン」「サポート」「お知らせ」のようなサービス UI テキストを誤検知しないようにしている。
4周目で 154件すべて検出ゼロに到達した。

### ⑦ HTML → JSON 正規化

```bash
npm run normalize
# → 154件の JSON を data/normalized/transactions/<id>.json に出力
```

抽出した項目は以下の通り。

- 取引基本情報（ID / status_tab / fetched_at）
- 取引ステップの現在地（5段階）
- 購入者情報（評価値・評価数・ビジネス利用フラグ）
- メッセージ配列（送信者種別・時刻・本文・添付数）
- 集計値（メッセージ数・継続日数）

メッセージの投稿時刻に「年」が含まれていない仕様だったので、**月日が後退したら年が変わる**ロジックで年を補完した。これは取引中の時系列が前から後ろに流れる前提で成立する。

## まとめ

154件、所要は着手から正規化完了まで約3時間。
バルク取得の48分は5〜15秒待機を遵守したからで、純粋な作業時間は1時間ちょっとだった気がしている。

成果物として手元に残ったのは、

- ダミー化済みの HTML 154件
- 構造化 JSON 154件
- 認証〜ダミー化〜正規化までの再実行可能なスクリプト群

このデータを起点に、自社サイト（[logical-web.jp](https://logical-web.jp/cases/)）の事例ページで「ご相談パターン 9類型 / 業態構成 / 平均取引期間」を公開している。
ダミー化を機械的に詰めておいたおかげで、外部公開しても顧客情報が漏れる心配がない状態になっている。

自分としては、ココナラに限らず**プラットフォーム上の自分の活動データは、全部こちらに引き取って資産化したほうがいい**という気がしている。
プラットフォームに依存している期間、データは「借りた家の家具」のようなもので、サービスが変わったり退会したりすれば、まるごと消える。

みなさんは、自分が使っているプラットフォーム（ココナラ・Lancers・クラウドワークス等）の取引データ、どこまで自分の手元に持っていますか？
構造化までいかなくても、「とりあえず HTML で全件保管」だけでも、後で何かに使える気がしています。

---

### 関連サービス

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

似たような「自分のプラットフォームデータを取り出して構造化したい」「ダミー化を機械的に詰めたい」というご相談は、ココナラのスポットプランでも承っています。
ココナラからのご依頼はこちら → [GA4・BigQuery・データ基盤のスポット相談（ココナラ）](https://coconala.com/services/554778)

