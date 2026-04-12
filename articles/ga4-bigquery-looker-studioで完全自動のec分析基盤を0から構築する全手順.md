

```markdown
---
title: "GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順"
emoji: "📊"
type: "tech"
topics: ["ga4", "bigquery", "lookerstudio", "ec", "データ分析"]
published: false
---

## 「毎週のレポート作成に半日かかっている」あなたへ

EC運営をしていると、売上・CVR・流入チャネル別の成果など、見るべき指標が多すぎて、レポート作成だけで毎週何時間も消耗していませんか？

GA4の管理画面だけでは限界がある。でもBigQueryやLooker Studioは「なんだか難しそう」で手が出ない——。

この記事では、GA4のデータをBigQueryに連携し、Looker Studioで自動更新されるECダッシュボードを**ゼロから構築する全手順**を解説します。一度作れば、毎朝コーヒーを飲みながら最新データを眺めるだけの運用になります。

## 全体アーキテクチャ

構築するのは以下の3層構成です。

```
GA4 → BigQuery（日次自動エクスポート） → Looker Studio（自動更新ダッシュボード）
```

**所要時間の目安：**
| ステップ | 作業時間 |
|---|---|
| GA4 → BigQuery連携設定 | 15分 |
| BigQueryでビュー作成 | 30分 |
| Looker Studioダッシュボード構築 | 60分 |

## Step 1：GA4 → BigQuery連携を設定する

### 1-1. GCPプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. BigQuery APIが有効になっていることを確認
3. 請求先アカウントを紐づけ（無料枠あり：毎月1TBのクエリ、10GBのストレージ）

### 1-2. GA4管理画面からBigQueryリンクを作成

1. GA4の **管理 → プロパティ設定 → BigQueryのリンク設定** を開く
2. GCPプロジェクトを選択
3. **エクスポート頻度は「毎日」を選択**（ストリーミングは費用がかかるため、まずは日次で十分）
4. リンクを作成

:::message
連携設定後、BigQueryにデータが反映されるまで**24〜48時間**かかります。焦らず待ちましょう。
:::

データは `analytics_XXXXXXXXX.events_YYYYMMDD` というテーブルに日別で格納されます。

## Step 2：EC分析用のビューをBigQueryで作成する

GA4のBigQueryスキーマはネストが深く、そのままLooker Studioに接続すると重くなります。**中間ビュー（View）を作成して整形する**のがポイントです。

### 2-1. セッション×チャネル×購入のサマリービュー

```sql
CREATE OR REPLACE VIEW `your_project.analytics_XXXXXXXXX.ec_session_summary` AS
WITH session_base AS (
  SELECT
    event_date,
    user_pseudo_id,
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
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
)
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS report_date,
  IFNULL(source, '(direct)') AS source,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END) AS purchase_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS transactions,
  SUM(CASE WHEN event_name = 'purchase' THEN revenue ELSE 0 END) AS total_revenue,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END),
    COUNT(DISTINCT session_id)
  ) AS cvr
FROM session_base
GROUP BY report_date, source, medium
```

:::message alert
`your_project` と `analytics_XXXXXXXXX` はご自身の環境に必ず書き換えてください。データセット名はGA4のプロパティIDが入ります。
:::

### 2-2. 商品別パフォーマンスビュー（任意）

```sql
CREATE OR REPLACE VIEW `your_project.analytics_XXXXXXXXX.ec_product_performance` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS report_date,
  items.item_name,
  items.item_category,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN
    CONCAT(user_pseudo_id, CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
  END) AS product_views,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN
    CONCAT(user_pseudo_id, CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
  END) AS add_to_carts,
  SUM(CASE WHEN event_name = 'purchase' THEN items.quantity ELSE 0 END) AS units_sold,
  SUM(CASE WHEN event_name = 'purchase' THEN items.item_revenue ELSE 0 END) AS item_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`,
  UNNEST(items) AS items
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY report_date, item_name, item_category
```

## Step 3：Looker Studioでダッシュボードを構築する

### 3-1. データソースの接続

1. [Looker Studio](https://lookerstudio.google.com/) で新規レポートを作成
2. **コネクタ → BigQuery → カスタムクエリではなく「ビュー」を直接選択**
3. `ec_session_summary` ビューを接続

:::message
ビューを直接接続することで、Looker Studio側にSQLを書く必要がなくなり、メンテナンス性が大幅に向上します。
:::

### 3-2. ECダッシュボードの推奨構成

以下のレイアウトがEC分析では実用的です。

| エリア | 配置するグラフ | 利用フィールド |
|---|---|---|
| ヘッダー | スコアカード×4 | sessions / transactions / total_revenue / cvr |
| 中段左 | 時系列グラフ | report_date × total_revenue |
| 中段右 | 円グラフ | medium × sessions |
| 下段 | テーブル | source/medium × sessions / cvr / total_revenue |

### 3-3. 自動更新の設定

Looker Studioはデータソースへアクセスするたびに最新データを取得しますが、**データの鮮度設定**を調整しましょう。

1. データソースの編集画面を開く
2. 「データの更新頻度」を **12時間** に設定

これで、毎朝ダッシュボードを開くだけで前日までの最新データが自動で表示されます。

## 運用のコツと注意点

**コスト管理：** BigQueryのクエリ費用はダッシュボードを開くたびに発生します。ビューではなくスケジュールクエリで**マテリアライズドテーブル（実テーブル）に日次書き出し**する方式にすると、クエリコストを大幅に抑えられます。

**テーブル分割の注意：** `events_*` のワイルドカードで全期間を対象にすると膨大なスキャン量になります。`_TABLE_SUFFIX` で期間を絞るのは必須です。

**データ欠損チェック：** GA4のBigQueryエクスポートは稀に遅延します。日次で `event_date` ごとのレコード数を監視するクエリを用意しておくと安心です。

## まとめ

1. **GA4 → BigQuery連携**は管理画面から15分で完了
2. **中間ビュー**を作ることでLooker Studioの速度と保守性が劇的に改善
3. **Looker Studio**で一度ダッシュボードを組めば、あとは自動更新

この仕組みを導入したECサイトでは、週次レポート作成の工数が**半日 → ほぼゼロ**になった事例もあります。空いた時間を施策の企画と実行に使えるようになるのが、分析基盤構築の最大のメリットです。

---

:::message
「BigQueryのSQL設計がわからない」「自社ECに合ったダッシュボードを作りたい」という方へ——GA4×BigQuery×Looker Studioの分析基盤構築をサポートしています。まずはお気軽にご相談ください。
👉 [ココナラでGA4分析の相談をする](https://coconala.com/services/1791205)
:::
```