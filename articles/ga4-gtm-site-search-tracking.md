---
title: "GA4×GTMでサイト内検索キーワードを正しく計測する設定"
emoji: "🔍"
type: "tech"
topics: ["gtm", "googleanalytics", "ec"]
published: false
---

## サイト内検索データが宝の山だと気づいていますか

ECサイトを運営していて「ユーザーが何を探しているか」を把握できていない、という声をよく聞きます。

サイト内検索キーワードは、ユーザーの購買意図がもっとも明確に表れるデータです。
「ユーザーが何を求めてサイトに来たのか」がキーワードとして直接記録されるため、品揃えの改善やコンテンツ拡充の優先順位を決める判断材料になります。

GA4には`view_search_results`という推奨イベントがありますが、多くのサイトでは正しく設定されていません。
この記事では、GTMを使ってサイト内検索キーワードを正確に計測する方法を解説します。

## GA4のサイト内検索計測の仕組み

GA4でサイト内検索を計測するには、`view_search_results`イベントに`search_term`パラメータを送信します。

GA4の拡張計測機能にもサイト内検索の自動計測がありますが、これはURLのクエリパラメータが`q`、`s`、`search`、`query`、`keyword`のいずれかに合致する場合のみ動作します。

サイトによっては以下のようなケースがあり、標準設定では対応できません。

- クエリパラメータ名が独自（例：`kw`、`term`、`searchWord`）
- 検索結果がJavaScriptで動的に描画される（URLが変わらない）
- 検索キーワードがURLではなくPOSTリクエストで送信される

こうしたケースでは、GTMでのカスタム設定が必要です。

## パターン1：URLクエリパラメータから取得する

もっとも一般的なパターンです。
検索時のURLが`https://example.com/search?q=Tシャツ`のような形式の場合に使えます。

### 手順1：URL変数を作成

GTMの「変数」→「ユーザー定義変数」→「新規」で以下を作成します。

| 設定項目 | 値 |
|----------|-----|
| 変数タイプ | URL |
| コンポーネントタイプ | クエリ |
| クエリキー | q（サイトに合わせて変更） |
| 変数名 | URL Query - search_term |

サイトのクエリパラメータ名を確認してください。
実際に検索を実行し、ブラウザのアドレスバーでURLの`?`以降を確認するのが確実です。

### 手順2：トリガーを作成

検索結果ページが表示されたタイミングでイベントを発火させます。

**方法A：ページビュートリガーを使う**

```
トリガータイプ: ページビュー
発生場所: 一部のページビュー
条件: Page Path — 含む — /search
```

**方法B：検索パラメータの存在を条件にする**

```
トリガータイプ: ページビュー
発生場所: 一部のページビュー
条件: URL Query - search_term — 正規表現に一致 — .+
```

方法Bは、検索パラメータが存在するすべてのページで発火するため、検索結果のURLパスが一定でないサイトに適しています。

### 手順3：GA4イベントタグを作成

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "イベント名": "view_search_results",
  "イベントパラメータ": {
    "search_term": "{{URL Query - search_term}}"
  },
  "トリガー": "Page View - Search Results"
}
```

## パターン2：データレイヤーから取得する

検索結果がJavaScriptで動的に描画され、URLが変わらないサイトの場合です。
開発チームと連携し、検索実行時にデータレイヤーへpushする実装を依頼します。

### フロントエンド側の実装

```javascript
// 検索が実行されたタイミングで呼び出す
function trackSiteSearch(keyword, resultCount) {
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({
    event: "site_search",
    search_term: keyword,
    search_result_count: resultCount
  });
}

// 使用例
document.querySelector('#search-form').addEventListener('submit', function(e) {
  const keyword = document.querySelector('#search-input').value;
  // 検索APIのレスポンス後に実行
  fetchSearchResults(keyword).then(function(results) {
    trackSiteSearch(keyword, results.length);
  });
});
```

### GTM側の設定

**データレイヤー変数：**

| 変数名 | データレイヤーの変数名 |
|--------|----------------------|
| DLV - search_term | search_term |
| DLV - search_result_count | search_result_count |

**カスタムイベントトリガー：**

```
トリガータイプ: カスタムイベント
イベント名: site_search
```

**GA4イベントタグ：**

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "イベント名": "view_search_results",
  "イベントパラメータ": {
    "search_term": "{{DLV - search_term}}",
    "search_result_count": "{{DLV - search_result_count}}"
  },
  "トリガー": "CE - site_search"
}
```

## パターン3：DOM要素から取得する

データレイヤーの実装が難しい場合の代替手段です。
検索結果ページのDOM要素から検索キーワードを直接取得します。

### カスタムJavaScript変数の作成

GTMの「変数」→「ユーザー定義変数」→「新規」で、カスタムJavaScriptを選択します。

```javascript
function() {
  var searchInput = document.querySelector('#search-input');
  if (searchInput && searchInput.value) {
    return searchInput.value.trim();
  }
  // 検索結果ページに表示されているキーワードから取得
  var searchLabel = document.querySelector('.search-result-keyword');
  if (searchLabel) {
    return searchLabel.textContent.trim();
  }
  return undefined;
}
```

:::message
DOM要素のセレクタはサイトのHTML構造に依存するため、サイトリニューアル時に計測が止まるリスクがあります。
可能であればパターン1またはパターン2を優先してください。
:::

## 検索結果0件の計測

「検索したが結果が0件だった」ケースは、商品ラインナップやコンテンツの不足を示す重要なシグナルです。

### データレイヤーで検索結果件数を送る

```javascript
window.dataLayer.push({
  event: "site_search",
  search_term: "グルテンフリービール",
  search_result_count: 0  // 0件の場合
});
```

GA4側でカスタムメトリック`search_result_count`を登録すると、「結果0件のキーワード」でフィルタリングしたレポートを作成できます。

## GA4カスタムディメンションの登録

GTM側の設定だけでは、GA4のレポートにパラメータが表示されません。
GA4管理画面でカスタムディメンションを登録します。

| ディメンション名 | イベントパラメータ | 範囲 |
|------------------|-------------------|------|
| 検索キーワード | search_term | イベント |

カスタムメトリックも登録する場合：

| メトリック名 | イベントパラメータ | 範囲 | 測定単位 |
|-------------|-------------------|------|----------|
| 検索結果件数 | search_result_count | イベント | 標準 |

## BigQueryでの検索キーワード分析

GA4のBigQueryエクスポートを使うと、より柔軟な分析が可能です。

### 検索キーワードランキング

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  event_name = 'view_search_results'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  search_term
ORDER BY
  search_count DESC
LIMIT 50
```

### 検索後のコンバージョン率

```sql
WITH search_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE event_name = 'view_search_results'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  COUNT(s.user_pseudo_id) AS search_users,
  COUNT(p.user_pseudo_id) AS search_and_purchase_users,
  ROUND(COUNT(p.user_pseudo_id) / COUNT(s.user_pseudo_id) * 100, 2) AS conversion_rate
FROM search_users s
LEFT JOIN purchase_users p ON s.user_pseudo_id = p.user_pseudo_id
```

サイト内検索を利用したユーザーのコンバージョン率は、利用しなかったユーザーより高い傾向があります。
この差分を定量的に把握すると、検索機能への投資判断がしやすくなります。

## デバッグ手順

1. GTMプレビューモードを起動
2. サイトで検索を実行
3. Tag Assistantで`view_search_results`タグの発火を確認
4. Variablesタブで`search_term`の値が正しいか確認
5. GA4 DebugViewでイベントの受信を確認

## まとめ

サイト内検索キーワードの計測ポイントを整理します。

- GA4の拡張計測はクエリパラメータ名が限定されるため、GTMでのカスタム設定が安全
- URL・データレイヤー・DOM要素の3パターンから、サイトに合った方法を選ぶ
- 検索結果0件のキーワードも重要なデータとして収集する
- GA4のカスタムディメンション登録を忘れない
- BigQueryと組み合わせて検索キーワードの詳細分析を行う

ユーザーの検索行動を把握することは、商品開発やコンテンツ改善の起点になります。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
