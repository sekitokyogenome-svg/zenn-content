

```markdown
---
title: "GA4×GTMでフォーム送信の計測が取れないときのデバッグ手順"
emoji: "🔍"
type: "tech"
topics: ["GA4", "GTM", "GoogleTagManager", "フォーム計測", "デバッグ"]
published: false
---

## 「フォーム送信イベントが計測されない…」その原因、5分で特定できます

「GTMでフォーム送信トリガーを設定したのに、GA4のレポートに一向にデータが上がってこない」

ECサイトやBtoBサイトを運営していると、一度はこの壁にぶつかるのではないでしょうか。お問い合わせフォームや会員登録フォームの送信計測は、コンバージョン分析の根幹です。ここが取れていないと、広告のROAS計算もチャネル評価も成り立ちません。

本記事では、GA4×GTMでフォーム送信が計測できない場合の**体系的なデバッグ手順**を、チェックリスト形式で解説します。

---

## ステップ1：GTMプレビューモードで「トリガーが発火しているか」確認

まず最初に確認すべきは、**そもそもトリガーが発火しているかどうか**です。

1. GTMの管理画面で「プレビュー」ボタンをクリック
2. 対象ページでフォームを実際に送信
3. Tag Assistantの左パネルに `Form Submit` イベントが表示されるか確認

:::message
**よくある落とし穴：** `Form Submit` ではなく `gtm.formSubmit` というイベント名で表示されます。左パネルに一切表示されない場合は、フォームが `<form>` タグを使っていない可能性があります。
:::

### `<form>` タグがない場合の対処

SPAやReactベースのフォーム、またはJavaScriptで `fetch` / `XMLHttpRequest` を直接叩いているケースでは、GTMのフォーム送信トリガーは反応しません。

この場合は**dataLayerプッシュ**で対応します。開発者に以下のコードをフォーム送信成功時に埋めてもらいましょう。

```javascript
// フォーム送信成功時のコールバックに追加
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: 'form_submit_success',
  form_name: 'contact',        // フォームを識別する名前
  form_destination: '/thanks'   // 遷移先のパス
});
```

GTM側では「カスタムイベント」トリガーで `form_submit_success` を受け取ります。

---

## ステップ2：トリガーは発火しているのにタグが動かない場合

Tag Assistantで `gtm.formSubmit` は出ているのに、GA4イベントタグが「Tags Not Fired」に入っている——このパターンも多いです。

**確認ポイント：**

| チェック項目 | よくあるミス |
|---|---|
| トリガーの条件 | `Page URL` に正規表現ミス、`Form ID` の指定間違い |
| フォーム送信トリガーの「タグの配信を待つ」 | 未チェックだとページ遷移が先に発生してタグが発火しない |
| 「妥当性をチェック」 | HTML5バリデーション非対応フォームでONにしていると発火しない |

特に重要なのが**「タグの配信を待つ」**オプションです。

:::message alert
フォーム送信後にサンクスページへリダイレクトされるサイトでは、「タグの配信を待つ」を**有効**にし、待ち時間を `2000`（ミリ秒）以上に設定してください。これがOFFだと、GA4へのリクエストが飛ぶ前にページ遷移してしまいます。
:::

---

## ステップ3：タグは発火しているのにGA4に反映されない場合

GTMプレビューでタグが「Tags Fired」に入っているのに、GA4のリアルタイムレポートに表示されない。これが最も見落としやすいケースです。

### 3-1. GA4のDebugViewで確認

1. GTMプレビューモードが有効な状態でフォームを送信
2. GA4管理画面 → 「管理」→「DebugView」を開く
3. 対象イベントが表示されるか確認

### 3-2. イベント名・パラメータ名の表記ミスを確認

GA4タグの設定値を再確認します。

```
// ありがちなミス例
× イベント名: formSubmit      （キャメルケース）
○ イベント名: form_submit     （スネークケース・GA4推奨）

× パラメータ名: formName
○ パラメータ名: form_name
```

GA4のイベント名は**スネークケース（小文字＋アンダースコア）**が推奨です。キャメルケースでも動きますが、予約イベント名との衝突リスクがあります。

### 3-3. 測定IDの確認

意外と多いのが、**測定IDが本番とテストで違う**パターンです。GTMのGA4設定タグで指定している測定ID（`G-XXXXXXX`）が、確認しているGA4プロパティと一致しているか必ずチェックしましょう。

---

## ステップ4：BigQueryエクスポートで最終確認

GA4のUIでは反映が遅れることがあります。BigQueryエクスポートを有効にしている場合、以下のSQLで直接データを確認できます。

```sql
SELECT
  event_name,
  event_timestamp,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'form_name') AS form_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'form_submit'
ORDER BY
  event_timestamp DESC
LIMIT 50;
```

ここにデータがあればGA4への送信自体は成功しています。UIに反映されるまで24〜48時間かかることもあるため、焦らず待ちましょう。

---

## デバッグ手順まとめフローチャート

```
トリガー発火してる？
  ├─ NO → <form>タグの有無を確認 → dataLayerプッシュで対応
  └─ YES → タグ発火してる？
              ├─ NO → トリガー条件・「タグの配信を待つ」を確認
              └─ YES → GA4 DebugViewに表示される？
                          ├─ NO → 測定ID・イベント名の表記を確認
                          └─ YES → 反映待ち or BigQueryで直接確認
```

フォーム計測のトラブルは、この4ステップで原因の9割以上を特定できます。

---

## GA4×GTMの計測設計でお困りの方へ

「どのイベントを取るべきか分からない」「設定したはずなのに数字が合わない」——そんなお悩みを抱えていませんか？

GA4・GTM・BigQueryの計測設計から分析環境の構築まで、ココナラでご相談を承っています。フォーム計測に限らず、EC特有のイベント設計（カート追加・購入・会員登録など）もまとめて対応可能です。

👉 **[GA4・BigQuery活用のご相談はこちら](https://coconala.com/services/1791205)**
```