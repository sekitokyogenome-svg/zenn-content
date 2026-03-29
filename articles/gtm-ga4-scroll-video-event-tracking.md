---
title: "GTMでGA4のスクロール率・動画再生をイベント計測する方法"
emoji: "🎬"
type: "tech"
topics: ["gtm", "googleanalytics", "tracking"]
published: false
---

## GA4の標準スクロール計測では不十分な理由

GA4の拡張計測機能には「スクロール」イベントが含まれていますが、計測されるのは90%スクロールのみです。

「ユーザーがページのどこまで読んでいるか」を詳細に知りたい場合、これでは情報が足りません。
25%、50%、75%など段階的なスクロール深度を取得するには、GTMでのカスタム設定が必要です。

同様に、YouTube動画の再生状況も標準の拡張計測だけでは粒度が粗く、「どこで離脱したか」「最後まで見たか」を正しく把握できません。

この記事では、GTMを使ってスクロール深度と動画再生イベントを詳細に計測する方法を解説します。

## 事前準備：GA4の拡張計測を確認する

GTMでカスタム設定を行う場合、GA4側の拡張計測と競合しないように注意が必要です。

### スクロール計測の場合

GA4の拡張計測で「スクロール」がオンになっていると、GTMから送信するイベントと重複します。
GTMで詳細なスクロール計測を行う場合は、GA4側のスクロール拡張計測をオフにしてください。

**設定場所：** GA4管理 → データストリーム → 拡張計測機能 → スクロール数をオフ

### 動画再生の場合

同様に、GA4の拡張計測で「動画エンゲージメント」がオンの場合はオフにします。

**設定場所：** GA4管理 → データストリーム → 拡張計測機能 → 動画エンゲージメントをオフ

## スクロール深度トリガーの設定

### 手順1：組み込み変数を有効化

GTMの「変数」→「設定」から、以下の組み込み変数を有効にします。

- **Scroll Depth Threshold** — スクロール率の数値（25, 50, 75, 100など）
- **Scroll Depth Units** — 計測単位（パーセントまたはピクセル）
- **Scroll Direction** — スクロール方向（vertical / horizontal）

### 手順2：スクロール深度トリガーを作成

1. GTMの「トリガー」→「新規」
2. トリガータイプ：「スクロール距離」を選択
3. 以下のように設定

| 設定項目 | 値 |
|----------|-----|
| 縦方向のスクロール距離 | チェックあり |
| 割合 | 25, 50, 75, 100 |
| トリガーの発生場所 | すべてのページ |

トリガー名は`Scroll Depth - 25, 50, 75, 100`などわかりやすい名前にしておきましょう。

### 手順3：GA4イベントタグを作成

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "イベント名": "scroll_depth",
  "イベントパラメータ": {
    "scroll_percentage": "{{Scroll Depth Threshold}}",
    "page_path": "{{Page Path}}"
  },
  "トリガー": "Scroll Depth - 25, 50, 75, 100"
}
```

:::message
GA4のイベント名を`scroll`にすると拡張計測の標準イベントと混同するため、`scroll_depth`のような別名を推奨します。
:::

### 手順4：GA4カスタムディメンションの登録

GA4管理画面で以下のカスタムディメンションを登録します。

| ディメンション名 | イベントパラメータ | 範囲 |
|------------------|-------------------|------|
| スクロール率 | scroll_percentage | イベント |

## YouTube動画トリガーの設定

GTMにはYouTube動画専用のトリガーが組み込まれています。
ページに埋め込まれたYouTube動画の再生イベントを自動で検知できます。

### 手順1：組み込み変数を有効化

GTMの「変数」→「設定」から、以下を有効にします。

- **Video Provider** — 動画プロバイダー（YouTube）
- **Video Title** — 動画タイトル
- **Video URL** — 動画URL
- **Video Duration** — 動画の長さ（秒）
- **Video Current Time** — 現在の再生位置（秒）
- **Video Percent** — 再生進捗率（%）
- **Video Visible** — 動画が画面内に表示されているか
- **Video Status** — 再生状態（start / pause / complete など）

### 手順2：YouTube動画トリガーを作成

1. GTMの「トリガー」→「新規」
2. トリガータイプ：「YouTube動画」を選択
3. 以下のように設定

| 設定項目 | 値 |
|----------|-----|
| 開始 | チェックあり |
| 完了 | チェックあり |
| 一時停止、シークバー操作、バッファリング | チェックあり |
| 進捗状況 | チェックあり → 割合: 25, 50, 75 |
| JavaScript APIサポートを全てのYouTube動画に追加する | チェックあり |

:::message
「JavaScript APIサポートを全てのYouTube動画に追加する」を有効にしないと、iframe埋め込みの動画を検知できません。
既存のYouTube embedに`enablejsapi=1`パラメータを自動付与する設定です。
:::

### 手順3：GA4イベントタグを作成

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "イベント名": "video_engagement",
  "イベントパラメータ": {
    "video_title": "{{Video Title}}",
    "video_url": "{{Video URL}}",
    "video_status": "{{Video Status}}",
    "video_percent": "{{Video Percent}}",
    "video_duration": "{{Video Duration}}",
    "video_current_time": "{{Video Current Time}}",
    "page_path": "{{Page Path}}"
  },
  "トリガー": "YouTube Video - All Events"
}
```

### イベントパラメータの使い分け

GTMの`{{Video Status}}`変数に入る値は以下の通りです。

| Video Status | 発生タイミング |
|-------------|---------------|
| start | 動画の再生開始時 |
| pause | 一時停止時 |
| buffering | バッファリング開始時 |
| progress | 指定した進捗率に到達時 |
| complete | 動画の再生完了時 |

GA4のレポートでは`video_status`パラメータでフィルタリングし、各段階のユーザー数を比較できます。

## 特定ページだけで計測する応用設定

すべてのページでスクロールや動画を計測すると、イベント数が膨大になる場合があります。
特定のページに絞りたい場合は、トリガーの発生条件を追加します。

### スクロール計測を記事ページだけに限定

トリガーの「このトリガーの発生場所」で「一部のページ」を選択し、条件を追加します。

```
Page Path — 正規表現に一致 — /blog/.*
```

### 動画計測を特定ディレクトリに限定

```
Page Path — 含む — /video-gallery/
```

## BigQueryでのスクロールデータ分析例

GA4からBigQueryにエクスポートしている場合、以下のSQLでページごとのスクロール完読率を算出できます。

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'page_path') AS page_path,
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'scroll_percentage') AS scroll_pct,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  event_name = 'scroll_depth'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  page_path, scroll_pct
ORDER BY
  page_path, CAST(scroll_pct AS INT64)
```

この結果から、「50%で離脱が多いページ」などを特定し、コンテンツ改善の優先順位を決められます。

## デバッグとテスト

### GTMプレビューモードでの確認ポイント

1. **スクロールイベント** — ページをスクロールしながら、25%・50%・75%・100%の各閾値でトリガーが発火するか確認
2. **動画イベント** — YouTube動画を再生・一時停止・完了し、各ステータスでイベントが記録されるか確認
3. **パラメータ値** — Tag Assistantの「Variables」タブで各変数の値が正しく取得されているか確認

### GA4 DebugViewでの確認

GTMプレビューモードと併用してGA4のDebugViewを開くと、リアルタイムでイベントの受信状況を確認できます。

## まとめ

GTMを活用したスクロール深度と動画再生の計測ポイントを整理します。

- GA4の拡張計測をオフにしてからGTMでカスタム設定を行う
- スクロールは25%刻みで段階的に計測する
- YouTube動画はGTM組み込みトリガーで開始・進捗・完了を取得する
- 計測対象ページを絞ることでイベント数の増加を抑える
- BigQueryと組み合わせることで詳細なコンテンツ分析が可能になる

これらのデータがあると、「どのコンテンツが読まれているか」「動画がどこまで見られているか」を定量的に把握でき、改善施策の精度が上がります。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
