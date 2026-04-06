

---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の標準レポートだけでは限界がある…」と感じていませんか？

「GA4で細かいユーザー行動を分析したいのに、探索レポートではサンプリングがかかって正確な数字が出ない」「チャネル別のLTVを出したいけど、どうにも集計しきれない」——中小ECを運営していると、こうした壁にぶつかる瞬間があるはずです。

その突破口が **GA4 → BigQueryエクスポート** です。生データをBigQueryに流し込めば、SQLで自由に集計でき、サンプリングなしの正確な分析が可能になります。

本記事では、2026年最新のUI・仕様に基づいて、エクスポート設定の全手順と注意点を解説します。

## 前提条件の確認

設定を始める前に、以下を満たしているか確認してください。

:::message
**必要な条件**
- GA4プロパティの「編集者」以上の権限
- Google Cloud プロジェクト（課金設定済み）
- Google Cloud プロジェクトの「BigQuery管理者」ロール
- GA4プロパティとGoogle Cloudプロジェクトが同じ組織、または適切にリンク可能な状態
:::

Google Cloudの無料枠（毎月10GBのストレージ、1TBのクエリ処理）で中小ECサイトの多くは十分カバーできます。月間PVが100万以下であれば、無料枠内に収まるケースがほとんどです。

## Step 1：Google Cloud プロジェクトの準備

### 1-1. プロジェクト作成と課金有効化

```
Google Cloud Console → プロジェクト作成
→ 「お支払い」→ 請求先アカウントをリンク
```

課金を有効にしないとBigQueryのデータセットが作成できません。無料枠内でも課金設定は必須です。

### 1-2. BigQuery APIの有効化

```
Google Cloud Console → 「APIとサービス」→「ライブラリ」
→ 「BigQuery API」を検索 → 有効化
```

## Step 2：GA4管理画面からエクスポート設定

1. GA4管理画面を開く
2. 左下「管理（歯車アイコン）」→「プロダクトリンク」→「BigQueryのリンク」
3. 「リンク」をクリック
4. Google Cloudプロジェクトを選択
5. データのロケーションを選択（**東京：`asia-northeast1`** 推奨）
6. エクスポートタイプを選択

### エクスポートタイプの選び方

| タイプ | 頻度 | 特徴 | 推奨シーン |
|--------|------|------|-----------|
| **毎日** | 1日1回 | 前日分のデータが確定後エクスポート。コスト低 | ほとんどのEC事業者はこれで十分 |
| **ストリーミング** | ほぼリアルタイム | 数秒〜数分遅延でデータ反映。追加コストあり | リアルタイムダッシュボードが必要な場合 |

:::message alert
ストリーミングエクスポートはBigQuery Storageの書き込みAPIを使うため、アクセス規模によっては月数千円〜の追加費用が発生します。まずは「毎日」で始めて、必要に応じてストリーミングを追加するのがおすすめです。
:::

7. 「送信」をクリックしてリンク完了

## Step 3：データが届いているか確認する

エクスポート設定後、**毎日エクスポートの場合は翌日以降**にデータが届きます。BigQueryコンソールで確認しましょう。

```sql
-- データセット内のテーブル一覧を確認
SELECT
  table_id,
  row_count,
  ROUND(size_bytes / 1024 / 1024, 2) AS size_mb
FROM
  `your-project.analytics_XXXXXXXXX.__TABLES__`
ORDER BY
  table_id DESC
LIMIT 10;
```

`analytics_XXXXXXXXX` の `XXXXXXXXX` はGA4プロパティIDです。テーブル名が `events_YYYYMMDD` の形式で日付ごとに作成されていれば成功です。

### 実際にイベントデータを取得してみる

```sql
-- 直近1日のイベント数をイベント名別に集計
SELECT
  event_name,
  COUNT(*) AS event_count
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

`page_view`、`session_start`、`purchase` などおなじみのイベント名が並んでいれば、正常にエクスポートされています。

## Step 4：よくあるトラブルと対処法

### テーブルが作成されない

- **原因1**：Google Cloudプロジェクトの課金が無効 → 課金設定を再確認
- **原因2**：権限不足 → GA4のサービスアカウントにBigQueryの「データ編集者」ロールを付与
- **原因3**：設定直後 → 毎日エクスポートは翌日まで待つ

### `events_intraday_*` テーブルとは？

ストリーミングエクスポートを有効にすると `events_intraday_YYYYMMDD` テーブルが作られます。当日の暫定データが入っており、日次テーブル（`events_YYYYMMDD`）が確定すると自動で消えます。クエリ対象を間違えないよう注意してください。

## コスト管理のコツ

:::message
**BigQueryのコストを抑える3つの習慣**
1. クエリには必ず `_TABLE_SUFFIX` で日付範囲を絞る（全期間スキャンを防ぐ）
2. `SELECT *` は避け、必要なカラムだけ指定する
3. Google Cloudの「予算アラート」を月額1,000円などで設定しておく
:::

```sql
-- 悪い例：全テーブルをフルスキャン
SELECT * FROM `your-project.analytics_XXXXXXXXX.events_*`;

-- 良い例：日付とカラムを絞る
SELECT
  event_name,
  user_pseudo_id,
  event_timestamp
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260131';
```

## まとめ

| ステップ | やること |
|---------|---------|
| Step 1 | Google Cloud プロジェクト作成＆課金有効化 |
| Step 2 | GA4管理画面からBigQueryリンクを設定 |
| Step 3 | 翌日以降にSQLでデータ到着を確認 |
| Step 4 | トラブル時は権限・課金・待機時間をチェック |

BigQueryエクスポートさえ設定すれば、チャネル別CVR、ユーザー行動のファネル分析、LTV計算など、GA4標準レポートでは難しかった分析がSQLひとつで実現できます。

次回以降の記事では、このエクスポートデータを使った具体的な分析SQLを紹介していきます。

---

:::message
**「設定はできたけど、何を分析すればいいか分からない」** という方へ

GA4×BigQueryの初期設定から、EC売上に直結する分析ダッシュボード構築まで、ココナラでサポートしています。「うちのサイトだと何が見えるようになる？」というご相談だけでもお気軽にどうぞ。

👉 [ココナラ サービスページはこちら](https://coconala.com/services/1791205)
:::