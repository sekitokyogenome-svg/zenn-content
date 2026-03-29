---
title: "GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】"
emoji: "📊"
type: "tech"
topics: ["googleanalytics", "bigquery", "lookerstudio"]
published: true
---

## はじめに

GA4はそのまま使うと、分析規模が大きくなるにつれて限界が出てきます。

- サンプリングがかかって正確な数値が出ない
- データ保持期間が最大14ヶ月
- 広告データや売上データと結合できない

これらをまとめて解決するのが **GA4→BigQueryエクスポート** です。

この記事では、GA4のデータをBigQueryに連携する方法と、長期運用に耐える3層設計の考え方を解説します。

---

## GA4のBigQueryエクスポートを有効にする

GA4管理画面から数クリックで設定できます。

1. GA4管理画面 →「プロパティ設定」→「BigQueryのリンク設定」
2. GCPプロジェクトを選択（なければ先に作成）
3. エクスポート頻度を選択（毎日 or ストリーミング）
4. データセットのリージョンを選択（`asia-northeast1` 推奨）

設定完了後、翌日から `analytics_XXXXXXXXX` というデータセットに自動でデータが蓄積されます。

:::message
GCPの料金について：BigQueryはストレージとクエリの従量課金です。GA4の生データ蓄積だけであれば、月数百円〜1,000円程度が目安です。
:::

---

## 生データをそのまま使わない方がいい理由

エクスポートされた生データ（`events_YYYYMMDD`テーブル）は、1イベント1行のネスト構造になっています。

```sql
-- 生データへのクエリ例（冗長になりがち）
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'page_view'
```

毎回このような`UNNEST`を書くのは非効率で、チームで共有するには可読性が低すぎます。

---

## 3層設計（raw / staging / mart）の考え方

長期運用に耐えるデータ基盤を作るには、データを3つのレイヤーに分けて管理します。

### raw層

GA4から届いた生データをそのまま保持するレイヤー。加工はしない。

```
analytics_XXXXXXXXX.events_YYYYMMDD
→ そのまま保持
```

### staging層

生データをフラット化・クレンジングするレイヤー。`UNNEST`処理はここで一括対応。

```sql
-- staging例：page_viewイベントをフラット化
CREATE OR REPLACE VIEW `project.staging.stg_page_views` AS
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE event_name = 'page_view'
```

### mart層

ビジネスロジックを適用した分析用テーブル。Looker Studioはここに繋ぐ。

```sql
-- mart例：チャネル別セッション数・CV数の集計
CREATE OR REPLACE TABLE `project.mart.channel_summary` AS
SELECT
  event_date,
  source,
  medium,
  COUNT(DISTINCT session_id) AS sessions,
  COUNTIF(is_conversion = true) AS conversions
FROM `project.staging.stg_sessions`
GROUP BY 1, 2, 3
```

:::message alert
Looker StudioをBigQueryに繋ぐ際は **raw層やstaging層ではなくmart層** に接続してください。生データへの直接接続はクエリコストが高くなります。
:::

---

## Looker Studioとの接続

mart層のテーブルをデータソースとして接続します。

1. Looker Studio →「データを追加」→「BigQuery」
2. GCPプロジェクト → データセット（`mart`）→ テーブルを選択
3. ダッシュボードを構築

mart層が正しく設計されていれば、Looker Studio側での計算フィールドはほぼ不要になります。

---

## まとめ

| レイヤー | 役割 | 触る頻度 |
|----------|------|----------|
| raw | 生データ保持 | 触らない |
| staging | フラット化・クレンジング | スキーマ変更時のみ |
| mart | 分析・可視化用 | ビジネスロジック変更時 |

この3層構造を最初に作っておくと、データが増えても壊れず、メンバーが増えても管理しやすい基盤になります。

設定代行・データマート設計のご相談はこちらからどうぞ。

https://coconala.com/services/1791205
