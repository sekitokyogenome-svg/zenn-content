---
title: "非エンジニアEC経営者がClaude Code × BigQueryで自走できるようになるまで"
emoji: "🚀"
type: "idea"
topics: ["claudecode", "bigquery", "ec"]
published: false
---

## はじめに

「GA4を入れているのに、データを見るのはアクセス数くらい」

これは、あるEC事業者の方から聞いた言葉です。GA4は無料で高機能なアナリティクスツールですが、データを深掘りしようとすると途端にハードルが上がります。BigQueryにエクスポートすれば詳細な分析が可能になりますが、SQLを書けない人にとっては「宝の持ち腐れ」になりがちです。

この記事では、エンジニアではないEC経営者が、Claude Codeを使ってBigQueryのデータを自然言語で分析できるようになるまでの過程を、体験記風にまとめました。

---

## 最初の壁：「BigQueryって何？」

### BigQueryとの出会い

GA4の管理画面では「直近28日間のアクティブユーザー数」や「イベント数」は見られます。しかし「先月購入した人のうち、2回目の購入をした人は何%か」といった分析は、標準レポートでは難しいのが現実です。

BigQueryはGoogleが提供するデータウェアハウスサービスです。GA4のデータをBigQueryにエクスポートすると、SQLというデータベース言語を使って自由に分析ができます。

### 最初に感じたハードル

- SQLという言語を覚える必要がある
- GA4のデータ構造（ネスト構造、event_params）が複雑
- `UNNEST` という聞いたことのない構文が出てくる
- エラーが出ても何が間違っているのかわからない

正直なところ「これは自分には無理だ」と思いました。

---

## 転機：Claude Codeとの出会い

Claude Codeは、ターミナル上で動くAIアシスタントです。自然言語で指示を出すと、コードの生成や実行を行ってくれます。

```bash
# Claude Codeのインストール
npm install -g @anthropic-ai/claude-code

# 起動
claude
```

起動したら、日本語でやりたいことを伝えるだけです。

---

## 体験1：初めてのSQL生成

### やりたかったこと

「先月のセッション数と購入数を知りたい」

### Claude Codeへの指示

```text
GA4のBigQueryテーブル project.analytics_XXXXXX.events_* を使って、
先月のセッション数と購入数を集計するSQLを書いてください。
```

### 返ってきたSQL

```sql
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM `project.analytics_XXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)));
```

`UNNEST` や `_TABLE_SUFFIX` といった、自分では書けない構文が含まれていました。しかし、Claude Codeに「このSQLの各行の意味を教えてください」と聞くと、丁寧に解説してくれます。

---

## 体験2：質問を重ねて分析を深掘る

最初の結果を見て、次の疑問が湧きました。

### 「購入率が低い気がする。チャネル別に見たい」

```text
このSQLを修正して、チャネル別のセッション数と購入率を出してください。
チャネルは collected_traffic_source の source と medium を使って。
```

Claude Codeはすぐに修正版のSQLを出してくれます。さらに「購入率が低いチャネルに対して、どんな改善策が考えられますか？」と聞くと、マーケティングの観点からアドバイスも返してきます。

このように**対話を重ねることで、分析が自然と深まっていく**のがClaude Codeの強みです。

---

## 体験3：定期的に見たい数字を「型」にする

慣れてくると、毎週見たい指標が決まってきます。

```text
以下のKPIを毎週チェックしたいです。
一つのSQLにまとめてください：
- セッション数（全体とチャネル別Top5）
- 購入数と購入率
- 平均注文金額
- カート追加率
- 新規ユーザー率
```

Claude Codeが出してくれたSQLを保存しておけば、毎週BigQueryのコンソールにコピペして実行するだけで定点観測ができます。

```sql
-- 週次ダッシュボードSQL
WITH base AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_date,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    ecommerce.purchase_revenue AS revenue
  FROM `project.analytics_XXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS purchase_rate,
  ROUND(AVG(
    CASE WHEN event_name = 'purchase' AND revenue > 0
    THEN revenue END
  ), 0) AS avg_order_value,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'add_to_cart'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS cart_add_rate
FROM base;
```

---

## 自走できるようになるまでのステップ

振り返ると、以下のステップを踏みました。

### ステップ1：まず聞いてみる（1日目）

「先月のセッション数を教えて」くらいのシンプルな質問から始めました。SQLの知識はゼロでも問題ありません。

### ステップ2：結果を見て次の質問をする（1週目）

数字を見ると「なぜ？」が湧きます。その「なぜ？」をそのままClaude Codeに聞きます。

### ステップ3：繰り返し使うSQLを保存する（2週目）

毎回同じ質問をするのは非効率なので、よく使うSQLをファイルに保存するようになりました。

### ステップ4：SQLの意味が少しずつわかる（1ヶ月後）

Claude Codeが生成するSQLを何度も見ていると、`WHERE` や `GROUP BY` の意味が自然とわかるようになります。

### ステップ5：自分でSQLを微修正できるようになる（2ヶ月後）

「期間を変えたい」「カラムを追加したい」といった軽微な修正は、自分でできるようになりました。

---

## 非エンジニアがClaude Codeを使う際のコツ

### 1. テーブル名を必ず伝える

Claude Codeにはデフォルトでテーブル名がわかりません。最初に「`project.dataset.events_*` を使って」と明示してください。

### 2. 曖昧な表現を避ける

「売上を見たい」よりも「先月の日別売上合計を降順で出したい」の方が、期待通りのSQLが返ってきます。

### 3. エラーはそのまま貼り付ける

BigQueryでエラーが出たら、エラーメッセージをそのままClaude Codeに貼り付けてください。原因と修正案を教えてくれます。

### 4. 「なぜ？」をそのまま聞く

数字を見て感じた疑問は、そのまま自然言語で聞きましょう。分析の深掘りが自然に進みます。

---

## 注意点

### データの解釈はAI任せにしない

Claude Codeはデータの集計と仮説の提示はしてくれますが、最終的なビジネス判断は人間が行う必要があります。自社の状況を一番理解しているのは経営者自身です。

### BigQueryの利用料金に注意

BigQueryは従量課金制です。大きなテーブルに対して何度もクエリを実行すると、予想以上にコストがかかることがあります。

:::message
BigQueryの無料枠は毎月1TBのクエリ処理です。GA4のデータ量にもよりますが、中小ECサイトであれば無料枠内で収まることが多いです。
:::

---

## まとめ

非エンジニアでも、Claude Codeを使えばBigQueryのGA4データを自然言語で分析できるようになります。

大事なのは「完璧なSQLを書く」ことではなく、「知りたいことを言葉にする」ことです。Claude Codeはその言葉をSQLに変換し、データから答えを引き出す手助けをしてくれます。

「データを活用したいけど、何から始めればいいかわからない」という方は、まずClaude Codeに一つ質問を投げかけてみてください。

:::message
「Claude Codeを使ったデータ分析の自動化に興味がある」という方は、お気軽にご相談ください。
👉 [データ分析スポットプラン](https://coconala.com/services/554778)
:::
