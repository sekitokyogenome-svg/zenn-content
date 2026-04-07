

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2025年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の管理画面だけでは限界がある…」と感じていませんか？

「GA4のレポートでは見たいデータが出せない」「セッション単位で細かく分析したいのに探索レポートだと重くてタイムアウトする」──中小ECの運営者やマーケターなら、一度はこの壁にぶつかったことがあるのではないでしょうか。

その解決策が **GA4 × BigQuery連携** です。GA4の生データをBigQueryにエクスポートすれば、SQLで自由自在に分析できるようになります。

本記事では、2025年最新のUI・仕様に基づいて、**初めてでも迷わない設定手順**と**設定後に確認すべきポイント**をまとめました。

## 前提条件を確認する

連携を始める前に、以下の3つを満たしているか確認してください。

| 条件 | 詳細 |
|------|------|
| GA4プロパティの編集権限 | 「管理者」または「編集者」ロール |
| Google Cloudプロジェクト | 課金が有効化されていること |
| BigQuery API | 対象プロジェクトでAPIが有効化されていること |

:::message
BigQueryには毎月10GBまでの無料ストレージ枠と、毎月1TBまでの無料クエリ枠があります。中小ECサイト（月間10万PV程度）であれば、多くの場合無料枠内で運用できます。
:::

## ステップ1：Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを新規作成、または既存プロジェクトを選択
3. 「APIとサービス」→「ライブラリ」で **BigQuery API** を検索し有効化
4. 「お支払い」から課金アカウントを紐付け（無料枠利用でも必要）

## ステップ2：GA4管理画面でBigQueryリンクを作成

1. [GA4管理画面](https://analytics.google.com/) を開く
2. 左下の **⚙ 管理** → 対象プロパティの **「サービス間のリンク設定」** セクションへ
3. **「BigQueryのリンク」** をクリック
4. **「リンク」** ボタンを押す

ここから設定ウィザードが始まります。

### 2-1. BigQueryプロジェクトの選択

「BigQueryプロジェクトを選択」でステップ1で用意したプロジェクトを選びます。**データのロケーション**は、日本向けECなら `asia-northeast1`（東京）を推奨します。

:::message alert
ロケーションは後から変更できません。東京リージョンを選ぶとレイテンシが低く、また国内のデータ保管要件にも対応しやすくなります。
:::

### 2-2. データストリームとエクスポート頻度の設定

| 設定項目 | 推奨設定 | 説明 |
|---------|---------|------|
| データストリーム | ウェブストリームを選択 | 複数ある場合は分析対象を選択 |
| 頻度 | **毎日＋ストリーミング** | 日次テーブル＋リアルタイムテーブルの両方が作成される |
| ユーザーデータを含める | オン | user_propertiesなどが含まれるように |

「毎日」だけでも分析は可能ですが、**ストリーミング**も有効にしておくと、当日分のデータにもアクセスできるため便利です。

### 2-3. 確認して送信

設定内容を確認し「送信」をクリック。リンクが作成されると、**翌日からBigQuery上にテーブルが生成**され始めます。

## ステップ3：BigQueryでデータが届いているか確認する

翌日以降、BigQuery Consoleを開き、以下の構造でデータセットとテーブルが作られているか確認します。

```
プロジェクトID
 └─ analytics_<プロパティID>
     ├─ events_YYYYMMDD      ← 日次テーブル
     ├─ events_intraday_YYYYMMDD  ← ストリーミングテーブル
     └─ pseudonymous_users_*  ← ユーザーデータ（有効時）
```

届いていることが確認できたら、簡単なSQLを実行してみましょう。

```sql
-- 直近1日のイベント数とユニークユーザー数を確認
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name
ORDER BY
  event_count DESC
LIMIT 20;
```

:::message
`your-project` と `analytics_XXXXXXXXX` は自分の環境に置き換えてください。プロパティIDはGA4管理画面の「プロパティの詳細」で確認できます。
:::

結果が返ってくれば、連携は正常に完了しています。

## ステップ4：セッション単位で正しくデータを取る基本SQL

GA4のBigQueryデータはイベント単位（1行＝1イベント）です。セッション軸で分析するには、`ga_session_id` を使ってセッションを識別します。

```sql
-- セッション数・ページビュー数・コンバージョン数を日別に集計
WITH sessions AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name
  FROM
    `your-project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
)
SELECT
  date,
  COUNT(DISTINCT session_id) AS sessions,
  COUNTIF(event_name = 'page_view') AS pageviews,
  COUNTIF(event_name = 'purchase') AS purchases
FROM sessions
GROUP BY date
ORDER BY date;
```

このSQLが動けば、GA4 × BigQuery環境の構築は完了です。ここから先は、チャネル別分析やLTV計算など、自由に深掘りしていけます。

## よくあるトラブルと対処法

| 症状 | 原因 | 対処 |
|------|------|------|
| テーブルが作成されない | リンク作成から24時間未満 | 翌日まで待つ |
| `events_intraday` しかない | 日次エクスポートは翌日生成 | 翌日に `events_YYYYMMDD` を確認 |
| 権限エラー | サービスアカウントにBigQuery権限がない | GA4が自動作成するサービスアカウントに「BigQueryデータ編集者」ロールを付与 |

## まとめ

1. Google Cloudプロジェクトを準備し、BigQuery APIと課金を有効化
2. GA4管理画面からBigQueryリンクを作成（ロケーションは東京推奨）
3. 翌日にテーブル生成を確認し、SQLで動作検証

ここまでできれば、GA4の管理画面では不可能だった**生データレベルの自由な分析**が始められます。

---

:::message
「設定はできたけど、何をどう分析すればいいかわからない」「自社ECに合ったSQLを書いてほしい」という方へ──GA4×BigQueryの初期設定から分析ダッシュボード構築まで、まるごとサポートしています。

👉 [ココナラでGA4・BigQuery分析サポートを見る](https://coconala.com/services/1791205)
:::
```