---
title: "Looker Studio × BigQueryでEC売上ダッシュボードを1日で作る完全手順"
emoji: "📈"
type: "tech"
topics: ["lookerstudio", "bigquery", "ec"]
published: false
---

## はじめに

「GA4のデータはBigQueryにエクスポートしたけど、ダッシュボードの作り方がわからない」「Looker Studioを開いてみたものの、BigQueryとの接続やグラフ設定で手が止まってしまった」――EC運営者やマーケティング担当者にとって、データの可視化は後回しになりがちです。

実際のところ、Looker Studio × BigQueryの組み合わせは**正しい手順を踏めば1日で実用的なダッシュボードが完成**します。本記事では、EC売上ダッシュボードをゼロから構築する手順を、SQLコードとUI操作の両面から解説します。

---

## 前提条件

本記事の手順を進めるには、以下が準備できている必要があります。

- **GA4→BigQueryエクスポート**が有効になっていること
- BigQuery上に `analytics_XXXXXXXX.events_*` テーブルが存在すること
- **mart層（集計済みテーブル）**の設計方針が決まっていること

:::message
GA4→BigQueryエクスポートの設定がまだの方は、GA4管理画面の「BigQueryのリンク設定」から有効化できます。設定翌日からデータが蓄積されます。
:::

3層設計（raw → staging → mart）を採用している場合、staging層で基本的なフラット化が済んでいると、mart層のSQL作成がスムーズです。

---

## Step 1: ダッシュボード用のmartテーブルを作成する

まず、Looker Studioから参照するための集計テーブルを作ります。日別・チャネル別に売上・セッション数・CVR・客単価をまとめたmartビューです。

```sql
CREATE OR REPLACE VIEW `your_project.your_mart_dataset.mart_dashboard_daily` AS
WITH sessions AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'))
    ) AS sessions
  FROM `your_project.analytics_XXXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
),

purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `your_project.analytics_XXXXXXXX.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
)

SELECT
  s.date,
  COALESCE(s.source, '(direct)') AS source,
  COALESCE(s.medium, '(none)') AS medium,
  s.device_category,
  s.sessions,
  COALESCE(p.transactions, 0) AS transactions,
  COALESCE(p.revenue, 0) AS revenue,
  SAFE_DIVIDE(COALESCE(p.transactions, 0), s.sessions) AS cvr,
  SAFE_DIVIDE(COALESCE(p.revenue, 0), COALESCE(p.transactions, 0)) AS aov
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date
  AND COALESCE(s.source, '') = COALESCE(p.source, '')
  AND COALESCE(s.medium, '') = COALESCE(p.medium, '')
  AND s.device_category = p.device_category
ORDER BY s.date DESC;
```

:::message alert
`SAFE_DIVIDE`を使うことで、セッションやトランザクションが0の場合でもゼロ除算エラーを回避できます。Looker Studio側でエラー表示になるのを防ぐために重要です。
:::

---

## Step 2: Looker StudioからBigQueryのmartテーブルに接続する

1. [Looker Studio](https://lookerstudio.google.com/) を開き、「空のレポート」を作成
2. データソースの追加画面で **BigQueryコネクタ** を選択
3. プロジェクト → データセット → `mart_dashboard_daily` ビューを選択
4. 「追加」をクリックしてレポートに接続

接続が完了すると、右側のデータパネルにmartビューのカラム（`date`, `source`, `medium`, `sessions`, `revenue`など）が一覧表示されます。

:::message
カスタムクエリではなく、ビューを直接指定する方式がおすすめです。Looker Studio側でクエリを書くとキャッシュが効きにくくなり、BigQueryのクエリコストが増加する場合があります。
:::

---

## Step 3: KPIスコアカードを配置する

ダッシュボードの最上部に、主要KPIを一目で確認できるスコアカードを4つ並べます。

**配置するスコアカード：**

| 指標 | フィールド | 集計方法 | 表示形式 |
|------|-----------|---------|---------|
| 売上合計 | `revenue` | SUM | ¥ 通貨表示 |
| セッション数 | `sessions` | SUM | 数値（カンマ区切り） |
| CVR | `cvr` | AVG（加重平均推奨） | パーセント表示 |
| 平均客単価（AOV） | `aov` | AVG | ¥ 通貨表示 |

操作手順は以下の通りです。

1. メニューの「グラフを追加」→「スコアカード」を選択
2. 指標フィールドに `revenue` を設定、集計を `SUM` に変更
3. スタイルタブで通貨表示（JPY）を指定
4. 同様に残り3つのスコアカードを横に並べて配置

完成イメージとしては、レポート上部に白背景のカード4枚が横並びになり、大きなフォントで「¥1,234,567」「12,345」「2.3%」「¥5,678」のように表示されます。前期比の矢印アイコンを追加すると、増減が直感的に把握できます。

---

## Step 4: 日別売上推移の時系列チャートを追加する

スコアカードの下に、日別の売上推移を折れ線グラフで配置します。

1. 「グラフを追加」→「時系列グラフ」を選択
2. ディメンションに `date` を設定
3. 指標に `revenue`（SUM）を設定
4. オプションで `sessions`（SUM）を第2軸として追加

折れ線グラフには売上（左軸・青線）とセッション数（右軸・灰色の点線）が重なって表示されます。週末に売上が下がるパターンや、キャンペーン実施日の跳ね上がりなどが視覚的に確認できるようになります。

---

## Step 5: チャネル別の内訳テーブル・棒グラフを追加する

売上がどのチャネルから来ているかを把握するために、2つのコンポーネントを追加します。

### チャネル別テーブル

1. 「グラフを追加」→「表」を選択
2. ディメンションに `source` と `medium` を設定
3. 指標に `sessions`、`revenue`、`cvr`、`aov` を追加
4. デフォルトの並び替えを `revenue` 降順に設定

テーブルには「google / organic」「(direct) / (none)」「instagram / referral」のような行が並び、各チャネルの貢献度が数値で比較できます。

### チャネル別棒グラフ

1. 「グラフを追加」→「棒グラフ」を選択
2. ディメンションに `source` を設定
3. 指標に `revenue`（SUM）を設定
4. 並べ替えを `revenue` 降順に設定

横棒グラフで上から売上の多い順にチャネルが並びます。色分けにより、オーガニック・広告・SNSなどの構成比が把握しやすくなります。

---

## Step 6: 日付範囲フィルターとデバイスフィルターを追加する

ダッシュボードの上部にフィルターコントロールを配置して、閲覧者が自由に条件を変更できるようにします。

### 日付範囲フィルター

1. 「コントロールを追加」→「期間設定」を選択
2. デフォルトの期間を「過去30日間」に設定
3. レポート上部の右端に配置

### デバイスフィルター

1. 「コントロールを追加」→「プルダウンリスト」を選択
2. コントロールフィールドに `device_category` を設定
3. レポート上部の日付範囲フィルターの左側に配置

これにより「mobile」「desktop」「tablet」を切り替えて、デバイスごとの傾向を確認できます。モバイルのCVRがデスクトップより低い場合、モバイルUIの改善が優先課題だとわかります。

---

## Tips: キャッシュ・データ鮮度・コスト最適化

### キャッシュ設定

Looker Studioはデフォルトで12時間のデータキャッシュが有効です。ECダッシュボードの場合、日次更新で十分なケースが多いため、このままで問題ありません。

- **リソース** →「データソースの管理」→ 対象データソースを選択
- 「データの更新頻度」で キャッシュ時間を調整可能

### データ鮮度の管理

GA4→BigQueryのエクスポートは「毎日」設定の場合、前日分が翌朝に反映されます。リアルタイム性が必要な場合はストリーミングエクスポートを検討してください。ただし、ストリーミングはBigQueryのストレージコストが上がる点に注意が必要です。

### コスト最適化のポイント

- **martビューではなくスケジュールドクエリでテーブル化**すると、Looker Studioからのアクセスごとにクエリが走らず、BigQueryのスキャン量を大幅に抑えられます
- BigQueryの `_TABLE_SUFFIX` で期間を絞り、フルスキャンを避ける
- Looker Studioの「抽出データ」機能を使うと、定期的にスナップショットを取得してクエリ回数を減らせます

:::message
ビューのままだと、ダッシュボードを開くたびにBigQuery側でクエリが実行されます。アクセス頻度が高い場合は、スケジュールドクエリで日次テーブル化する運用がコスト面で有利です。
:::

---

## まとめ

本記事で解説した手順をまとめると以下の通りです。

1. **mart層のSQLを作成**して、BI用に集計済みのデータを用意
2. **Looker StudioからBigQueryに接続**し、martテーブルを参照
3. **KPIスコアカード**で売上・セッション・CVR・AOVを俯瞰
4. **時系列チャート**で日別のトレンドを可視化
5. **チャネル別テーブル・棒グラフ**で流入元ごとのパフォーマンスを把握
6. **フィルター**で期間やデバイスの切り替えを実現

GA4 × BigQuery × Looker Studioの組み合わせは、無料（BigQueryの従量課金を除く）でありながら高い柔軟性を持つダッシュボード環境です。一度構築すれば、毎朝ダッシュボードを開くだけでECの健康状態を把握できるようになります。

「自分のECサイトでもダッシュボードを作りたいけど、設計やSQL部分を任せたい」という方は、以下からお気軽にご相談ください。

👉 [GA4 × BigQuery ダッシュボード構築サービス](https://coconala.com/services/419062)
