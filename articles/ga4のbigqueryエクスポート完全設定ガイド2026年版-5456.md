

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2025年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の管理画面だけでは限界がある」と感じていませんか？

GA4の探索レポートでデータを分析していて、こんな壁にぶつかったことはないでしょうか。

- 探索レポートで14ヶ月以上前のデータが参照できない
- セグメント比較をしようとすると（other）にまとめられてしまう
- ユーザー単位の購買行動を細かく追えない

これらはすべて、GA4のデータをBigQueryにエクスポートすることで解決できます。この記事では、設定手順から初期確認のSQLまで、つまずきやすいポイントを押さえながら解説します。

## 前提：必要なもの

| 項目 | 内容 |
|------|------|
| GA4プロパティ | 編集者以上の権限 |
| Google Cloudプロジェクト | 課金が有効であること |
| BigQuery API | 有効化済み |

:::message
BigQueryへのエクスポート自体は**無料**です。ただし、BigQuery側でのデータ保存（ストレージ）とクエリ実行（分析）に対してGoogle Cloudの料金が発生します。中小ECサイト規模なら月額数百円〜数千円程度に収まるケースがほとんどです。
:::

## 手順1：Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを新規作成（または既存のものを選択）
3. 「APIとサービス」→「ライブラリ」から **BigQuery API** を有効化
4. 請求先アカウントがプロジェクトにリンクされていることを確認

:::message alert
請求先アカウントが未設定だとエクスポートのリンク時にエラーになります。無料トライアル枠でもリンクは必要です。
:::

## 手順2：GA4からBigQueryへのリンク設定

1. GA4管理画面 →「管理」→「プロダクトリンク」→「BigQueryのリンク」
2. 「リンク」をクリック
3. Google Cloudプロジェクトを選択
4. データロケーションを選択（日本なら `asia-northeast1` を推奨）
5. データストリームを選択
6. エクスポートタイプを選択

### エクスポートタイプの選び方

| タイプ | 特徴 | おすすめ用途 |
|--------|------|-------------|
| **毎日** | 1日1回、前日分をまとめてエクスポート | コスト重視・日次レポートで十分な場合 |
| **ストリーミング** | ほぼリアルタイムでエクスポート | 当日データを分析したい場合 |
| **両方** | 毎日＋ストリーミング併用 | 柔軟に分析したい場合 |

:::message
中小ECサイトであれば、まずは**「毎日」のみ**で始めるのがおすすめです。ストリーミングは追加コストが発生するため、リアルタイム分析の必要性が出てから追加しても遅くありません。
:::

## 手順3：エクスポートされたデータを確認する

設定完了後、翌日以降にBigQueryにデータが届きます。Google Cloud Console → BigQuery で、以下のようなデータセットとテーブルが作成されているか確認しましょう。

```
プロジェクトID
  └─ analytics_XXXXXXXXX（GA4プロパティID）
       ├─ events_20250101（日次テーブル）
       ├─ events_20250102
       └─ events_intraday_20250103（ストリーミング時）
```

## 手順4：初期確認用SQLを実行する

データが正しくエクスポートされているか、以下のSQLで確認します。

### イベント数とユーザー数の日別確認

```sql
SELECT
  event_date,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS session_count
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250107'
GROUP BY
  event_date
ORDER BY
  event_date
```

### チャネル別セッション数の確認

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS session_count
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250107'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  session_count DESC
LIMIT 20
```

:::message
GA4管理画面のレポートと数値が完全に一致しないことがあります。これはGA4のしきい値適用やサンプリングの影響で、BigQuery側の数値のほうが「生データに近い正確な値」です。
:::

## よくあるトラブルと対処法

| 症状 | 原因 | 対処法 |
|------|------|--------|
| テーブルが作成されない | 請求先アカウント未設定 | Google Cloudの課金設定を確認 |
| データが空 | リンク後24時間未経過 | 翌日まで待つ |
| `events_intraday` しかない | ストリーミングのみで日次未完了 | 日次エクスポートは翌日に確定テーブル化される |
| テーブル名のプロパティIDが違う | 複数プロパティの混同 | GA4管理画面でプロパティIDを再確認 |

## まとめ：エクスポートは「今日」設定しよう

BigQueryエクスポートは**設定した日以降のデータしか蓄積されません**。過去データの遡及エクスポートはできないため、分析予定がなくても早めに設定しておくことが重要です。

設定自体は10分程度で完了しますが、「データを活用した分析」はここからがスタート。次の記事では、エクスポートしたデータを使った実践的な分析SQLを紹介していきます。

---

:::message
「BigQueryの設定はできたけど、SQLを書いて分析するのはハードルが高い…」という方へ。GA4×BigQueryの初期設定から分析テンプレート構築まで、EC事業に特化してサポートしています。
👉 [GA4・BigQuery分析のご相談はこちら](https://coconala.com/services/1791205)
:::
```