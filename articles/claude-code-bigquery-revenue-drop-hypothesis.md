---
title: "Claude Codeで売上が下がった原因をBigQueryから自動で仮説生成させる"
emoji: "🔍"
type: "tech"
topics: ["claudecode", "bigquery", "dataanalysis", "ga4", "ec"]
published: true
---

## はじめに

「先月より売上が落ちている気がするけど、原因がわからない」

EC運営や事業責任者であれば、こんな場面に何度も直面しているはずです。GA4の管理画面を開き、チャネルを切り替え、デバイスを切り替え、ページごとの数字を見比べて……。手作業の調査には数時間かかることも珍しくありません。

しかも、時間をかけて調べても「たぶんこれが原因かも」という曖昧な結論で終わることが多い。

この記事では、**Claude Code × BigQuery MCP** を使って、売上低下の原因調査と仮説生成を自動化する方法を紹介します。SQLを手で書く必要はなく、Claude Codeに「売上が下がった原因を調べて」と伝えるだけで、ディメンションごとの分解と仮説の提示まで行えます。

:::message
**BigQuery MCPとは：** Claude CodeからBigQueryに直接クエリを実行できるMCP（Model Context Protocol）サーバーです。設定方法は[公式ドキュメント](https://github.com/anthropics/claude-code)を参照してください。Claude Codeの設定ファイル（`.claude/settings.json`）にBigQuery MCPサーバーを追加することで利用できます。
:::

---

## 全体のアプローチ

手動の調査プロセスをClaude Codeで再現し、自動化します。

1. **変化の検出** — 前期と今期の売上を比較して差分を把握する
2. **ディメンション分解** — チャネル・デバイス・地域・ページなどの軸で内訳を確認する
3. **仮説生成** — 数値の変化パターンからビジネス上の仮説をClaude Codeが提示する

この3ステップを一連のプロンプトで実行します。

---

## Step 1：売上変化の検出

まずはClaude Codeに期間比較を依頼します。

```text
BigQueryのyour_project.your_dataset.mart_channel_performanceから、
今月と先月の売上合計を比較してください。
差額と変化率も計算してください。
```

Claude Codeが生成するクエリの例：

```sql
WITH current_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `your_project.your_dataset.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND CURRENT_DATE()
),
previous_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `your_project.your_dataset.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH)
    AND LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
)
SELECT
  c.revenue AS current_revenue,
  p.revenue AS previous_revenue,
  c.revenue - p.revenue AS diff,
  ROUND((c.revenue - p.revenue) / p.revenue * 100, 1) AS change_pct
FROM current_period c, previous_period p
```

ここで「売上が15%減少」のような結果が返ってきたら、次のステップに進みます。

---

## Step 2：ディメンションごとの分解

変化の全体像がわかったら、どの軸で落ちているかを分解します。

```text
売上の減少がどのディメンションで起きているか調べてください。
以下の軸それぞれで、前月比の変化率を出してください。
- チャネル別（organic, paid, direct, referral, social）
- デバイス別（desktop, mobile, tablet）
- 上位10ページ別
mart_traffic と mart_channel_performance を使ってください。
```

Claude Codeは複数のクエリを順番に実行し、各軸での変化率を一覧にまとめてくれます。

:::message
ポイント：ディメンションを事前に指定しておくと、Claude Codeが迷わず分析できます。何も指定しないと「何を分解しますか？」と聞き返される場合があります。
:::

---

## Step 3：仮説の自動生成

ここがClaude Codeの最大の強みです。数値の分解結果をもとに、ビジネス上の仮説を生成させます。

```text
上記の分析結果をもとに、売上低下の原因として考えられる仮説を
3〜5個挙げてください。各仮説には以下を含めてください。
- 仮説の内容
- 根拠となる数値
- 確認すべき次のアクション
```

### 出力例1：オーガニック流入の減少

> **仮説：検索アルゴリズムのアップデートまたはインデックスの問題**
> - 根拠：Organicセッションが前月比-30%。他チャネルは横ばい。
> - 次のアクション：Google Search Consoleでインデックス状況とクリック数の推移を確認する。

### 出力例2：モバイルCVRの低下

> **仮説：モバイル版サイトのUI変更またはページ速度の悪化**
> - 根拠：モバイルのCVRが2.1%→1.3%に低下。デスクトップCVRは変化なし。
> - 次のアクション：直近のデプロイ履歴を確認し、モバイル向けの変更がなかったか調べる。PageSpeed Insightsでモバイルスコアもチェック。

### 出力例3：特定ページの流入減

> **仮説：主力商品ページへの流入経路が断たれた**
> - 根拠：商品Aのページビューが前月比-45%。他ページは微減程度。
> - 次のアクション：商品Aへの流入元を確認し、外部リンクの消失やSNS投稿の減少がないか調べる。

---

## プロンプト設計のコツ

仮説の精度を上げるために、プロンプトに以下の要素を含めると効果的です。

```text
あなたはEC事業のデータアナリストです。
以下のルールで売上低下の原因を分析してください。

1. まず全体の売上変化を数値で確認する
2. チャネル・デバイス・ページの3軸で分解する
3. 変化が大きい軸を特定し、仮説を生成する
4. 各仮説に「根拠となる数値」と「次のアクション」を必ず含める
5. 仮説は具体的に書く（「何かが悪い」ではなく「○○が△△した可能性」）
6. 季節要因やイベント影響も考慮する
```

:::message alert
注意：Claude Codeはデータに基づいた仮説を生成しますが、確定的な原因特定ではありません。仮説はあくまで調査の出発点として扱い、実際の確認作業は必ず行ってください。
:::

---

## 繰り返し使えるワークフローにする

毎回プロンプトを書き直すのは手間なので、Claude Codeのカスタムスラッシュコマンドとして保存しておくと便利です。

プロジェクトの `.claude/commands/` にMarkdownファイルを作成します。

ファイルパス: `.claude/commands/revenue-diagnosis.md`

```markdown
BigQueryのyour_dataset（mart層）から以下の分析を実行してください。

1. 直近7日間と前の7日間で売上合計を比較
2. チャネル別・デバイス別・上位ページ別に変化率を算出
3. 変化が大きい箇所を特定し、原因仮説を3〜5個生成
4. 各仮説に根拠数値と次のアクションを含める

mart_traffic, mart_channel_performance, mart_funnel を使用してください。
```

これで、Claude Code上で `/revenue-diagnosis` と入力するだけで分析が走ります。週次のルーティンに組み込めば、売上変動の早期発見と原因特定が仕組み化できます。

---

## まとめ

売上が下がったとき、原因を手作業で調べるのは時間がかかるうえに属人的です。Claude Code × BigQuery MCPを使えば、期間比較からディメンション分解、仮説生成までの時間を大幅に短縮できます。

ポイントをまとめると：

- BigQueryのデータマートを整備しておくことで、分析の精度と速度が上がる
- プロンプトにディメンションと出力フォーマットを指定すると、仮説の質が安定する
- カスタムコマンド化すれば、誰でも繰り返し実行できるワークフローになる

「データはあるのに活用できていない」という状態から一歩進みたい方は、まずBigQueryのデータマート構築から始めてみてください。

GA4×BigQueryの基盤構築やデータマート設計のご相談は、以下のサービスで承っています。

https://coconala.com/services/554778
