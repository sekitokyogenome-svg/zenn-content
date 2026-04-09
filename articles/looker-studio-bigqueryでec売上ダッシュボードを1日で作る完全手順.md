

```markdown
---
title: "Looker Studio × BigQueryでEC売上ダッシュボードを1日で作る完全手順"
emoji: "📊"
type: "tech"
topics: ["LookerStudio", "BigQuery", "GA4", "EC", "ダッシュボード"]
published: false
---

## 「毎朝スプレッドシートを手作業で更新するのが辛い…」

EC運営をしていると、売上・CVR・チャネル別の数字を毎日チェックしたいですよね。でも現実は、GA4の画面を何度も行き来したり、スプレッドシートに手動でコピペしたり。週次レポートの作成に毎回2時間かかっている、という方も多いのではないでしょうか。

この記事では、**GA4 × BigQuery × Looker Studio** を組み合わせて、自動更新されるEC売上ダッシュボードを1日で構築する手順を解説します。

## 全体の構成とゴール

```
GA4 → BigQuery（自動エクスポート） → ビュー/テーブル → Looker Studio
```

最終的に作るダッシュボードの構成要素は以下の4つです。

| パネル | 内容 |
|--------|------|
| ① KPIスコアカード | 売上・セッション数・CVR・客単価 |
| ② 日次売上推移 | 折れ線グラフ（前月比較付き） |
| ③ チャネル別売上 | 棒グラフ or テーブル |
| ④ 商品別売上TOP10 | テーブル |

## Step 1: BigQueryにGA4データを確認する

GA4からBigQueryへのエクスポートが設定済みであることが前提です。まだの方はGA4管理画面 > BigQueryリンクから設定してください（反映まで約24時間かかります）。

テーブルが存在するか確認します。

```sql
SELECT
  table_id,
  row_count
FROM
  `your-project.analytics_XXXXXXX.__TABLES__`
WHERE
  table_id LIKE 'events_%'
ORDER BY
  table_id DESC
LIMIT 5;
```

## Step 2: ダッシュボード用のビューを作成する

Looker Studioから直接 `events_*` テーブルを参照すると、クエリコストが膨らみやすくなります。**中間ビュー（またはスケジュールクエリで日次テーブル）を作るのがポイント**です。

### 日次サマリービュー

```sql
CREATE OR REPLACE VIEW `your-project.analytics_XXXXXXX.v_daily_ec_summary` AS
WITH purchase_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    ecommerce.purchase_revenue AS revenue,
    ecommerce.transaction_id
  FROM
    `your-project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 90 DAY))
)
SELECT
  date,
  IFNULL(medium, '(none)') AS medium,
  IFNULL(source, '(direct)') AS source,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS purchases,
  SUM(CASE WHEN event_name = 'purchase' THEN revenue ELSE 0 END) AS total_revenue
FROM
  purchase_events
GROUP BY
  date, medium, source;
```

### 商品別売上ビュー

```sql
CREATE OR REPLACE VIEW `your-project.analytics_XXXXXXX.v_product_sales` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  items.item_name,
  items.item_category,
  SUM(items.quantity) AS total_quantity,
  SUM(items.item_revenue) AS item_revenue
FROM
  `your-project.analytics_XXXXXXX.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 90 DAY))
GROUP BY
  date, items.item_name, items.item_category;
```

:::message
ビューはクエリ実行時に毎回計算されます。データ量が大きい場合は、スケジュールクエリで日次テーブルに書き出す方がコストを抑えられます。
:::

## Step 3: Looker Studioでダッシュボードを組む

### 3-1. データソースの追加

1. [Looker Studio](https://lookerstudio.google.com/) で「空のレポート」を作成
2. 「データを追加」→ BigQuery → 先ほど作成した `v_daily_ec_summary` を選択
3. 同様に `v_product_sales` も追加

### 3-2. KPIスコアカード（4枚並べる）

| 指標 | 設定 |
|------|------|
| 売上合計 | `total_revenue` の SUM |
| セッション数 | `sessions` の SUM |
| CVR | 計算フィールド: `SUM(purchases) / SUM(sessions)` |
| 客単価 | 計算フィールド: `SUM(total_revenue) / SUM(purchases)` |

:::message alert
CVR・客単価は「計算フィールド」で作成してください。Looker Studio上で指標同士を割り算する場合、集計方法を「自動」ではなく明示的に設定しないと正しく計算されないことがあります。
:::

### 3-3. 日次売上推移（時系列グラフ）

- ディメンション: `date`
- 指標: `total_revenue`（SUM）
- 「比較期間」を有効にして前月同期間を表示

### 3-4. チャネル別売上（テーブル）

- ディメンション: `source` / `medium`
- 指標: `sessions`, `purchases`, `total_revenue`
- 並び替え: `total_revenue` 降順

### 3-5. 商品別TOP10（テーブル）

- データソースを `v_product_sales` に切り替え
- ディメンション: `item_name`
- 指標: `total_quantity`, `item_revenue`
- 行数を10に制限、`item_revenue` 降順

## Step 4: 日付フィルターと仕上げ

レポート上部に**日付範囲コントロール**を追加し、デフォルトを「過去30日間」に設定します。これでチーム全員が同じURLを開くだけで最新データを見られます。

### 運用Tipsまとめ

- **コスト管理**: BigQuery BI Engineを有効にすると、Looker Studioからのクエリが高速化＆コスト削減できる
- **アクセス権**: Looker Studioの共有設定で「閲覧者」権限を使えば、BigQueryの権限を渡さずに済む
- **アラート**: Looker Studioの「定期メール配信」で毎朝9時にPDFを自動送信すると、チーム内の数字確認が習慣化しやすい

## まとめ

| 工程 | 所要時間の目安 |
|------|---------------|
| BigQueryビュー作成 | 1〜2時間 |
| Looker Studioレイアウト | 2〜3時間 |
| フィルター・仕上げ | 1時間 |
| **合計** | **約4〜6時間** |

手作業レポートから解放されるだけでなく、「数字を見る→施策を打つ→効果を確認する」サイクルが圧倒的に速くなります。

---

:::message
「ビューの設計やダッシュボード構築を丸ごとお願いしたい」「自社ECに合わせたカスタマイズが必要」という方は、ココナラでGA4・BigQuery・Looker Studioのダッシュボード構築をサポートしています。
👉 [サービス詳細はこちら](https://coconala.com/services/1791205)
:::
```