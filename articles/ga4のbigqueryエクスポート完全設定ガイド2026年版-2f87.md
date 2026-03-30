

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2025年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

「GA4の標準レポートだけでは、欲しいデータが出せない…」
「BigQueryに連携すればいいらしいけど、設定手順がわからない…」

中小ECの経営者やマーケターから、こうした相談を本当によくいただきます。GA4のBigQueryエクスポートは**無料枠の範囲でも十分活用でき**、生データを自由にSQL分析できる強力な武器になります。

この記事では、2025年最新のUI・仕様に基づいて、GA4→BigQueryのエクスポート設定を画面付きでステップ解説します。

## なぜBigQueryエクスポートが必要なのか

GA4の探索レポートには以下の制限があります。

| 制限項目 | GA4探索レポート | BigQuery |
|---|---|---|
| データ保持期間 | 最大14ヶ月 | 無期限（自分で管理） |
| サンプリング | 発生する場合あり | なし（生データ） |
| カスタム分析の自由度 | テンプレート依存 | SQLで自由自在 |
| 他データとの結合 | 不可 | CRMや広告データと結合可能 |

特にECサイトでは、ユーザーの購買行動を**セッション単位・ユーザー単位で深掘り**したい場面が多く、BigQueryの活用価値は非常に高いです。

## 事前準備

### 1. Google Cloud プロジェクトの作成

まだプロジェクトがない場合は、[Google Cloud Console](https://console.cloud.google.com/) からプロジェクトを新規作成します。

:::message
プロジェクト名は後から変更できますが、**プロジェクトID**は変更不可です。わかりやすい命名（例: `myshop-analytics`）を推奨します。
:::

### 2. BigQuery APIの有効化

Google Cloud Console で対象プロジェクトを開き、「APIとサービス」→「ライブラリ」から **BigQuery API** を有効化してください。通常はデフォルトで有効ですが、念のため確認しましょう。

### 3. 請求先アカウントの紐づけ

無料枠だけで運用する場合でも、請求先アカウントの設定は必須です。BigQueryの無料枠は以下の通りです。

- **ストレージ**: 毎月10GB まで無料
- **クエリ**: 毎月1TB まで無料

中小ECサイト（月間数万〜数十万PV規模）であれば、多くの場合この無料枠に収まります。

## GA4からBigQueryへのエクスポート設定手順

### ステップ1: GA4管理画面を開く

GA4の管理画面 → 対象プロパティの「**プロパティ設定**」→「**製品リンク**」→「**BigQuery のリンク**」を選択します。

### ステップ2: リンクを作成

「**リンク**」ボタンをクリックし、先ほど作成した Google Cloud プロジェクトを選択します。

### ステップ3: エクスポート設定を選択

ここが最も重要な設定です。

| 設定項目 | 推奨設定 | 理由 |
|---|---|---|
| データロケーション | `asia-northeast1`（東京） | レイテンシとデータ主権の観点 |
| データストリーム | すべて選択 | 漏れなくデータを取得 |
| 頻度 - 毎日 | ✅ ON | 日次集計に使用 |
| 頻度 - ストリーミング | 必要に応じて | リアルタイム分析が不要なら OFF（コスト節約） |

:::message alert
**ストリーミングエクスポート**は BigQuery の無料枠対象外です。中小ECではまず「毎日」エクスポートのみで始めることを推奨します。
:::

### ステップ4: 確認して送信

設定を確認し「送信」をクリックすれば完了です。**翌日からデータが流れ始めます**。

## エクスポート後の動作確認SQL

設定翌日以降、BigQuery Console で以下のSQLを実行してデータが入っているか確認しましょう。

```sql
-- エクスポートされたイベント数を日別に確認
SELECT
  event_date,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM
  `your-project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY))
GROUP BY
  event_date
ORDER BY
  event_date DESC;
```

:::message
`your-project.analytics_XXXXXXX` の部分は、実際のプロジェクトIDとGA4プロパティIDに置き換えてください。データセット名は `analytics_` + GA4プロパティID の形式になります。
:::

正常にエクスポートされていれば、日別のイベント数・ユニークユーザー数・セッション数が表示されます。

## チャネル別セッション数も確認してみよう

もう一歩進んで、チャネル別のデータが正しく取れるかも確認しましょう。

```sql
-- チャネル（メディア）別セッション数
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM
  `your-project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 20;
```

## よくあるトラブルと対処法

**Q. 設定したのにデータセットが表示されない**
→ エクスポート開始は翌日からです。当日中はデータセットが空の状態です。

**Q. `events_intraday_` テーブルしかない**
→ 日次エクスポートは深夜〜早朝に確定されます。`events_` テーブルは確定後に作成されます。

**Q. 途中からエクスポートを始めた場合、過去データは取れる？**
→ 取れません。エクスポート設定日以降のデータのみが蓄積されます。**今すぐ設定しておく**ことが最大のポイントです。

## まとめ

- GA4 × BigQuery連携は**無料枠で始められる**
- ストリーミングは OFF にしてコストを抑える
- データロケーションは `asia-northeast1`（東京）を選択
- 過去データは取得不可なので、**早めの設定が吉**

BigQueryにデータが溜まれば、GA4標準レポートでは見えなかったユーザー行動の深掘り、LTV分析、アトリビューション分析など、EC運営に直結する分析が可能になります。

---

:::message
「GA4×BigQueryの設定はできたけど、SQLの書き方がわからない」「自社ECに合った分析ダッシュボードがほしい」という方へ。GA4・BigQueryの設定から分析設計まで、ココナラでサポートしています。
👉 [GA4×BigQuery分析サポートサービス](https://coconala.com/services/1791205)
:::
```