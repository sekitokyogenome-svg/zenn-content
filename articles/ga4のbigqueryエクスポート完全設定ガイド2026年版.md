

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2025年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

「GA4の標準レポートだと、知りたいデータに手が届かない…」
「BigQueryにエクスポートすれば自由に分析できると聞いたけど、設定方法がわからない」

こんな悩みを抱えるEC担当者やWEBマーケターの方、多いのではないでしょうか。GA4のBigQueryエクスポートは**無料のGoogleアカウントでも利用可能**になり、以前よりずっと身近な存在になりました。本記事では、2025年最新の手順で、初めての方でも迷わず設定できるよう解説します。

## なぜBigQueryエクスポートが必要なのか

GA4の探索レポートには以下の制限があります。

| 項目 | GA4探索レポート | BigQuery |
|---|---|---|
| データ保持期間 | 最大14ヶ月 | 無期限（自分で管理） |
| サンプリング | 発生する場合あり | なし（生データ） |
| クロス分析の自由度 | テンプレート依存 | SQLで自在 |
| 外部データとの結合 | 不可 | CRMや広告データと結合可能 |

特にECサイトでは「昨年同月比の商品別CVR」や「特定キャンペーン経由のLTV」など、標準レポートでは出せない分析が売上改善の鍵になります。

## 事前準備

設定に入る前に、以下の3つを確認してください。

:::message
**必要なもの**
1. GA4プロパティの**編集者**以上の権限
2. Google Cloudプロジェクト（未作成なら新規作成）
3. Google Cloudプロジェクトの**オーナー**または**BigQuery管理者**権限
:::

## Step 1：Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 左上のプロジェクトセレクタから「新しいプロジェクト」を作成
3. プロジェクト名を入力（例：`my-ec-analytics`）
4. **BigQuery APIが有効**になっていることを確認（デフォルトで有効）

:::message alert
Google Cloud の無料枠では、BigQuery のストレージは毎月 10GB・クエリは毎月 1TB まで無料です。中小ECサイトであれば多くの場合この範囲で収まりますが、トラフィックが大きいサイトは料金を事前に試算しておきましょう。
:::

## Step 2：GA4からBigQueryリンクを作成

1. GA4管理画面 → **管理**（歯車アイコン）
2. プロパティ列の「**製品リンク**」→「**BigQueryのリンク**」
3. 「**リンク**」ボタンをクリック
4. 先ほど作成したGoogle Cloudプロジェクトを選択
5. データロケーションを選択（日本なら `asia-northeast1` を推奨）

### エクスポート設定の選択肢

| 設定 | 内容 | 推奨 |
|---|---|---|
| **毎日エクスポート** | 1日1回、前日分をまとめて出力 | ✅ まず有効に |
| **ストリーミングエクスポート** | ほぼリアルタイムで出力 | △ コスト要確認 |
| **イベントデータを含める** | 全イベントを出力 | ✅ 有効に |
| **ユーザーデータを含める** | ユーザー単位のテーブルを別途出力 | お好みで |

まずは「**毎日エクスポート**」のみ有効にするのがおすすめです。

6. 設定を確認して「**送信**」

:::message
リンク作成後、BigQueryにデータが反映されるまで**24〜48時間**ほどかかります。翌々日まで気長に待ちましょう。
:::

## Step 3：BigQueryでデータを確認する

48時間ほど経ったら、BigQuery Console でエクスポートされたデータを確認しましょう。以下のSQLを実行してみてください。

```sql
-- エクスポートされたイベント数を日別に確認
SELECT
  event_date,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date
ORDER BY
  event_date
```

`your-project` と `analytics_XXXXXXXXX` は自分の環境に書き換えてください。プロパティIDは GA4 管理画面の「プロパティの詳細」で確認できます。

さらに、セッション単位でチャネル別のページビュー数を確認するクエリも試してみましょう。

```sql
-- チャネル別セッション数（直近7日）
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
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 20
```

このクエリが正常に動けば、BigQueryエクスポートの設定は完了です。

## 設定後にやっておくべきこと

### 1. テーブルの有効期限を設定する
コストを管理するために、不要になった古いデータに有効期限を設定しておくと安心です。

### 2. 定期クエリ（スケジュールドクエリ）の活用
毎週の売上レポートなど、定型分析はスケジュールドクエリで自動化できます。

### 3. Looker Studio との連携
BigQuery のデータを Looker Studio に接続すれば、ダッシュボードとして可視化できます。

## まとめ

GA4 × BigQuery エクスポートの設定手順をおさらいします。

1. **Google Cloud プロジェクト**を用意する
2. GA4管理画面から**BigQuery リンク**を作成する
3. **毎日エクスポート**を有効にして 24〜48 時間待つ
4. SQL でデータが入っていることを**確認**する

設定自体は 10 分ほどで完了します。ここから先の「どんな SQL を書いて、どう売上改善につなげるか」が本番です。

---

:::message
「BigQuery にデータは入ったけど、SQL を書くのはハードルが高い…」「自社ECに合ったダッシュボードを作りたい」という方へ。GA4 × BigQuery の初期設定から分析ダッシュボード構築まで、ココナラでサポートしています。

👉 **[GA4・BigQuery分析のご相談はこちら](https://coconala.com/services/1791205)**
:::
```