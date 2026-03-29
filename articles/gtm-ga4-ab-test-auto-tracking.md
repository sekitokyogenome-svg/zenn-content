---
title: "GTM × GA4でA/Bテスト結果を自動計測する仕組みを作る"
emoji: "🧪"
type: "tech"
topics: ["gtm", "googleanalytics", "abtesting"]
published: false
---

## A/Bテストの結果を手作業で集計していませんか

A/Bテストを実施しているものの、結果の集計に手間がかかっている。
テスト結果をGA4のレポートで横断的に確認できない。

こうした課題を持つマーケターやエンジニアは多いのではないでしょうか。

Google OptimizeがサービスZennした後、A/Bテストの計測基盤を自前で構築する必要が出てきました。
GTMとGA4を組み合わせれば、テストのバリアント振り分けからコンバージョン計測まで、自動で記録する仕組みを構築できます。

この記事では、GTMのカスタムJavaScriptでランダム振り分けを行い、GA4のカスタムディメンションでテスト結果を自動計測する方法を解説します。

## 全体のアーキテクチャ

```
[GTM カスタムJS]
  ↓ ランダムにA/Bを割り当て
  ↓ Cookieに保存（再訪時も同じバリアント）
[dataLayer.push()]
  ↓ バリアント情報をGA4に送信
[GA4 カスタムディメンション]
  ↓ レポートでバリアント別に集計
[BigQuery]
  ↓ SQLで統計的有意差を検証
```

## 手順1：ランダム振り分けJavaScriptの作成

GTMのカスタムJavaScript変数で、ユーザーをランダムにバリアントAまたはBに振り分けます。

### GTM変数の作成

**変数タイプ：** カスタムJavaScript
**変数名：** CJS - AB Test Variant

```javascript
function() {
  var testName = 'cta_color_test_202603';
  var cookieName = 'ab_' + testName;

  // 既存のCookieを確認（再訪時は同じバリアントを返す）
  var cookies = document.cookie.split(';');
  for (var i = 0; i < cookies.length; i++) {
    var cookie = cookies[i].trim();
    if (cookie.indexOf(cookieName + '=') === 0) {
      return cookie.substring(cookieName.length + 1);
    }
  }

  // 新規ユーザーの場合、ランダムに振り分け
  var variant = Math.random() < 0.5 ? 'A' : 'B';

  // Cookieに保存（30日間有効）
  var date = new Date();
  date.setTime(date.getTime() + (30 * 24 * 60 * 60 * 1000));
  var expires = 'expires=' + date.toUTCString();
  document.cookie = cookieName + '=' + variant + ';' + expires + ';path=/;SameSite=Lax';

  return variant;
}
```

このスクリプトのポイントは以下の3つです。

1. **Cookie保存** — 同じユーザーには毎回同じバリアントを表示する（一貫性の確保）
2. **テスト名をCookie名に含める** — 複数のA/Bテストを同時に実行できる
3. **有効期限30日** — テスト期間中はバリアントが維持される

### 3パターン以上の振り分け

A/B/Cの3パターンに振り分ける場合は、以下のように変更します。

```javascript
function() {
  // ... Cookie確認処理は同じ ...

  var rand = Math.random();
  var variant;
  if (rand < 0.33) {
    variant = 'A';
  } else if (rand < 0.66) {
    variant = 'B';
  } else {
    variant = 'C';
  }

  // ... Cookie保存処理は同じ ...
  return variant;
}
```

## 手順2：バリアントに応じたDOM変更

振り分けたバリアントに基づいて、ページの表示を変更します。

### GTMカスタムHTMLタグの作成

**タグ名：** AB Test - CTA Color Change
**トリガー：** 対象ページのDOM Ready

```html
<script>
(function() {
  var variant = {{CJS - AB Test Variant}};

  // テスト対象のページでのみ実行
  if (window.location.pathname !== '/lp/campaign') return;

  var ctaButton = document.querySelector('.cta-button');
  if (!ctaButton) return;

  if (variant === 'B') {
    // バリアントB：CTAボタンの色を変更
    ctaButton.style.backgroundColor = '#FF6B35';
    ctaButton.style.color = '#FFFFFF';
    ctaButton.textContent = '今すぐ無料で始める';
  }
  // バリアントAはデフォルト表示のまま

  // データレイヤーにテスト情報をpush
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({
    event: 'ab_test_impression',
    ab_test_name: 'cta_color_test_202603',
    ab_test_variant: variant
  });
})();
</script>
```

:::message
DOM変更はページの読み込み後に実行されるため、一瞬オリジナルの表示がちらつく「フリッカー」が発生する場合があります。
対策として、テスト対象要素に`visibility: hidden`を初期設定し、GTMタグ内で`visibility: visible`に変更する方法があります。
:::

### フリッカー対策の実装

```html
<!-- HTMLの<head>内にインラインスタイルを追加 -->
<style>
  .ab-test-target { visibility: hidden; }
</style>
```

GTMタグ内で表示を復元します。

```html
<script>
(function() {
  var variant = {{CJS - AB Test Variant}};
  var target = document.querySelector('.ab-test-target');
  if (!target) return;

  if (variant === 'B') {
    target.style.backgroundColor = '#FF6B35';
    target.textContent = '今すぐ無料で始める';
  }

  // 表示を復元
  target.style.visibility = 'visible';
})();
</script>
```

## 手順3：GA4カスタムディメンションの設定

### GTM側：GA4イベントタグの作成

バリアント情報をGA4に送信するタグを作成します。

**方法A：全ページビューにバリアント情報を付与**

GA4設定タグのユーザープロパティにバリアントを設定します。

| ユーザープロパティ名 | 値 |
|---------------------|-----|
| ab_test_variant | {{CJS - AB Test Variant}} |

この方法だと、テスト対象ページ以外のイベントにもバリアント情報が付くため、サイト全体での行動をバリアント別に分析できます。

**方法B：テスト表示イベントとして送信**

```json
{
  "タグの種類": "Googleアナリティクス：GA4イベント",
  "イベント名": "ab_test_impression",
  "イベントパラメータ": {
    "ab_test_name": "cta_color_test_202603",
    "ab_test_variant": "{{CJS - AB Test Variant}}"
  },
  "トリガー": "CE - ab_test_impression"
}
```

### GA4管理画面：カスタムディメンションの登録

| ディメンション名 | パラメータ名 | 範囲 |
|------------------|-------------|------|
| ABテスト名 | ab_test_name | イベント |
| ABテストバリアント | ab_test_variant | ユーザー |

範囲を「ユーザー」にすると、そのユーザーのすべてのイベントにバリアント情報が紐づきます。

## 手順4：コンバージョンイベントとの紐づけ

テストのゴール（コンバージョン）は、既存のGA4イベントを利用します。

例えば`purchase`イベントや`generate_lead`イベントがすでに計測されている場合、GA4のレポートでカスタムディメンション「ABテストバリアント」を使ってフィルタリングするだけで、バリアント別のコンバージョン率が算出できます。

追加のタグ設定は不要です。

## 手順5：BigQueryでの結果集計

GA4のBigQueryエクスポートを使うと、統計的有意差の検証まで行えます。

### バリアント別のコンバージョン率を算出

```sql
WITH test_users AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params) WHERE key = 'ab_test_variant') AS variant
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE event_name = 'ab_test_impression'
    AND (SELECT value.string_value
         FROM UNNEST(event_params) WHERE key = 'ab_test_name') = 'cta_color_test_202603'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY user_pseudo_id, variant
),
conversions AS (
  SELECT DISTINCT user_pseudo_id
  FROM `your_project.analytics_XXXXXXX.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)
SELECT
  t.variant,
  COUNT(DISTINCT t.user_pseudo_id) AS total_users,
  COUNT(DISTINCT c.user_pseudo_id) AS converted_users,
  ROUND(
    COUNT(DISTINCT c.user_pseudo_id) / COUNT(DISTINCT t.user_pseudo_id) * 100, 2
  ) AS conversion_rate_pct
FROM test_users t
LEFT JOIN conversions c ON t.user_pseudo_id = c.user_pseudo_id
GROUP BY t.variant
ORDER BY t.variant
```

### 出力例

| variant | total_users | converted_users | conversion_rate_pct |
|---------|-------------|-----------------|---------------------|
| A | 5234 | 157 | 3.00 |
| B | 5189 | 198 | 3.82 |

### 統計的有意差の検証（Z検定）

```sql
WITH stats AS (
  -- 上記のクエリ結果を使用
  SELECT
    variant,
    COUNT(DISTINCT t.user_pseudo_id) AS n,
    COUNT(DISTINCT c.user_pseudo_id) AS x
  FROM test_users t
  LEFT JOIN conversions c ON t.user_pseudo_id = c.user_pseudo_id
  GROUP BY variant
),
ab AS (
  SELECT
    MAX(IF(variant = 'A', n, 0)) AS n_a,
    MAX(IF(variant = 'A', x, 0)) AS x_a,
    MAX(IF(variant = 'B', n, 0)) AS n_b,
    MAX(IF(variant = 'B', x, 0)) AS x_b
  FROM stats
)
SELECT
  x_a / n_a AS rate_a,
  x_b / n_b AS rate_b,
  (x_a + x_b) / (n_a + n_b) AS pooled_rate,
  (x_b / n_b - x_a / n_a) /
    SQRT(
      ((x_a + x_b) / (n_a + n_b)) *
      (1 - (x_a + x_b) / (n_a + n_b)) *
      (1.0 / n_a + 1.0 / n_b)
    ) AS z_score
FROM ab
```

Z scoreの絶対値が1.96以上であれば、95%信頼水準で有意差ありと判断できます。

## 複数テストの同時実行

複数のA/Bテストを同時に実行する場合は、テスト名を変数化します。

### テスト設定をルックアップテーブルで管理

GTMの「ルックアップテーブル」変数を使って、ページごとにテスト名を定義できます。

| 入力（Page Path） | 出力（テスト名） |
|-------------------|----------------|
| /lp/campaign | cta_color_test_202603 |
| /product/detail | product_image_test_202603 |

### テストの終了処理

テスト終了後は以下の手順で片付けます。

1. GTMのDOM変更タグを一時停止する
2. 勝者バリアントの変更をサイトのソースコードに反映する
3. 一定期間後にGTMのタグ・トリガー・変数を削除する
4. バージョン説明に「テスト終了：バリアントBを採用」と記録する

## 注意事項

### サンプルサイズの確保

統計的に有意な結果を得るには、十分なサンプルサイズが必要です。
テスト開始前に、必要なサンプルサイズを見積もっておきましょう。

目安として、コンバージョン率3%のページで0.5%の差を検出するには、各バリアントに約4,500ユーザーが必要です。

### テスト期間

最低でも1〜2週間は実行してください。
曜日による変動を吸収するため、7日の倍数で期間を設定するのが望ましいです。

### Cookie同意との整合

Cookieを使った振り分けを行う場合、Cookie同意バナーとの整合が必要です。
ユーザーがCookieを拒否した場合、振り分けが機能しない可能性があります。

その場合は、Cookieの代わりにローカルストレージを使う方法もあります。

```javascript
// localStorage版の振り分け
function() {
  var testName = 'cta_color_test_202603';
  var key = 'ab_' + testName;

  var stored = localStorage.getItem(key);
  if (stored) return stored;

  var variant = Math.random() < 0.5 ? 'A' : 'B';
  localStorage.setItem(key, variant);
  return variant;
}
```

## まとめ

GTM × GA4でA/Bテストを自動計測する仕組みのポイントを整理します。

- GTMのカスタムJavaScript変数でランダム振り分けを実装する
- Cookieに保存して再訪時も同じバリアントを表示する
- GA4のカスタムディメンションでバリアント別のデータを蓄積する
- BigQueryのSQLでコンバージョン率の差とZ検定による有意差検証を行う
- テスト終了後はGTMのタグを片付け、勝者バリアントをソースに反映する

Google Optimizeの代替として、GTMとGA4だけで実用的なA/Bテスト基盤を構築できます。

:::message
「GA4×GTMの計測設定を見直したい」という方は、お気軽にご相談ください。
👉 [GA4×GTM設定サービス](https://coconala.com/services/3332133)
:::
