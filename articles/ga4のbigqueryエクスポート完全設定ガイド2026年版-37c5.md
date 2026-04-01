

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の標準レポートだけでは、もう限界…」

ECサイトを運営していると、こんな壁にぶつかりませんか？

- 「探索レポートで14ヶ月以上前のデータが消えていた…」
- 「セッション単位のユーザー行動を細かく分析したいのに、GA4の画面だとできることが限られる」
- 「広告のROASをセッション×商品カテゴリで正確に出したい」

GA4の管理画面は便利ですが、**生データに直接アクセスできないと解決できない課題**は多いです。その解決策がBigQueryエクスポートです。

この記事では、2026年時点の最新UIに基づいて、GA4→BigQueryのエクスポート設定を**ゼロから完了まで**解説します。

---

## 前提条件の確認

設定を始める前に、以下を準備してください。

| 項目 | 必要な内容 |
|---|---|
| Google Cloudプロジェクト | 課金が有効化済みのプロジェクト |
| GA4プロパティ | 管理者または編集者の権限 |
| IAMロール | `BigQuery User` + `BigQuery Data Editor` がGA4サービスアカウントに付与されていること |

:::message
BigQueryへのエクスポートは**無料枠の範囲内で十分運用可能**です。月間100万PV程度のECサイトなら、ストレージ費用は月数十円〜数百円程度に収まるケースが多いです。
:::

---

## Step 1: Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを作成（既存のものでもOK）
3. **課金アカウントを紐付ける**（これを忘れるとエクスポートが失敗します）
4. BigQuery APIが有効化されていることを確認

```
# gcloud CLIで確認する場合
gcloud services list --enabled --project=YOUR_PROJECT_ID | grep bigquery
```

## Step 2: GA4管理画面からエクスポートを設定

1. GA4の **管理 → プロパティ設定 → データの収集と修正 → BigQueryのリンク** を開く
2. 「リンク」をクリック
3. 対象のGoogle Cloudプロジェクトを選択
4. データロケーションを選択（日本なら `asia-northeast1` 推奨）
5. エクスポート頻度を選択

### エクスポート頻度の選び方

| 頻度 | 特徴 | おすすめユースケース |
|---|---|---|
| **毎日** | 1日1回、前日分をエクスポート。コスト最小 | 日次レポート、月次分析が中心のEC |
| **ストリーミング** | ほぼリアルタイムでエクスポート | リアルタイムダッシュボード、在庫連動が必要な場合 |

:::message alert
ストリーミングエクスポートは**BigQueryのストリーミング挿入料金**が発生します。中小ECではまず「毎日」から始めて、必要に応じてストリーミングを追加する運用がおすすめです。
:::

## Step 3: データが届いているか確認する

設定後、翌日（毎日エクスポートの場合）にBigQueryコンソールで確認します。

```sql
-- エクスポートされたデータの件数を確認
SELECT
  COUNT(*) AS total_events,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  COUNT(DISTINCT 
    CONCAT(
      user_pseudo_id, 
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS total_sessions
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
```

結果が返ってくれば、エクスポートは正常に動作しています。

## Step 4: 実務で使えるクエリを試す

せっかくなので、ECサイトの分析にすぐ使えるクエリも紹介します。

### チャネル別セッション数の集計

```sql
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
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 20
```

GA4の標準レポートでは見えにくい**source/mediumの生の組み合わせ**が一覧で確認できます。

---

## よくあるトラブルと対処法

### テーブルが作成されない
- Google Cloudプロジェクトの**課金が無効**になっていないか確認
- GA4のリンク設定で選択したプロジェクトIDが正しいか再確認

### `events_intraday_*` テーブルしかない
- ストリーミングのみ有効で毎日エクスポートが無効の場合に発生します。日次テーブル（`events_*`）が必要なら、毎日エクスポートも有効にしてください

### データ量が異常に少ない
- 同意モード（Consent Mode）で大量のイベントがフィルタされている可能性があります。GA4管理画面のリアルタイムレポートと突き合わせて確認しましょう

---

## まとめ

GA4→BigQueryエクスポートの設定は、手順自体は30分もかからずに完了します。

1. Google Cloudプロジェクトを準備（課金有効化）
2. GA4管理画面からBigQueryリンクを作成
3. 翌日以降にSQLでデータ到着を確認

一度つないでしまえば、**14ヶ月の壁を超えたデータ蓄積**、**GA4画面では不可能な粒度の分析**が可能になります。

:::message
「設定はできたけど、どんなSQLを書けば売上改善につながるの？」という方は、今後の記事でEC特化のBigQuery分析クエリを順次紹介していきます。
:::

---

## GA4×BigQueryの分析設計、プロに相談しませんか？

「エクスポートはできたけど、自社ECに合った分析設計がわからない」
「SQLを書く時間がない、でもデータは活用したい」

そんな方向けに、GA4・BigQueryの分析設計から実装までをサポートしています。

👉 **[ココナラでGA4×BigQuery分析の相談をする](https://coconala.com/services/1791205)**
```