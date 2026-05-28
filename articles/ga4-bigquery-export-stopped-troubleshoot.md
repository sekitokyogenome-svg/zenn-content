---
title: "GA4×BigQueryのエクスポートが止まったときのトラブルシューティング"
emoji: "🚨"
type: "tech"
topics: ["bigquery", "googleanalytics", "troubleshooting"]
published: true
---

## はじめに

ある朝、いつものようにBigQueryでGA4データを確認しようとしたら、昨日のテーブルが存在しない。ダッシュボードのデータも更新されていない。

GA4からBigQueryへのエクスポートが停止するトラブルは、運用していると遭遇することがあります。原因は多岐にわたりますが、パターンを知っていれば対処は難しくありません。

この記事では、エクスポート停止の主な原因、INFORMATION_SCHEMAを使った確認方法、再開手順を解説します。

---

## エクスポートが止まる主な原因

| 原因 | 発生頻度 | 対処難易度 |
|------|----------|------------|
| BigQueryリンクの解除・設定変更 | 中 | 低 |
| GCPプロジェクトの課金アカウント問題 | 中 | 低 |
| BigQueryのAPI権限不足 | 中 | 中 |
| GA4プロパティの権限変更 | 低 | 低 |
| Google側の一時的な障害 | 低 | 対処不要（自動復旧） |
| データセットのリージョン不一致 | 低 | 高（再作成が必要） |

---

## STEP 1：最新テーブルの日付を確認する

まず、BigQueryにどこまでデータが入っているかを確認します。

```sql
SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `beeracle.analytics_263425816.__TABLES__`
WHERE table_id LIKE 'events_%'
ORDER BY table_id DESC
LIMIT 10
```

このクエリで、最後にエクスポートされたテーブルの日付がわかります。

---

## STEP 2：INFORMATION_SCHEMAで詳細を確認する

`INFORMATION_SCHEMA` を使うと、テーブルのメタ情報をより詳しく確認できます。

### テーブルの作成日時と行数

```sql
SELECT
  table_name,
  creation_time,
  ROUND(total_rows / 1000, 1) AS rows_k,
  ROUND(total_logical_bytes / POW(1024, 2), 1) AS size_mb
FROM `beeracle.analytics_263425816.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'events_%'
ORDER BY table_name DESC
LIMIT 10
```

### 直近のテーブル作成状況をチェック

```sql
SELECT
  table_name,
  creation_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, HOUR) AS hours_ago
FROM `beeracle.analytics_263425816.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'events_%'
ORDER BY creation_time DESC
LIMIT 5
```

:::message
GA4の日次エクスポートは通常、対象日の翌日にテーブルが作成されます。「昨日のテーブルがない」場合は、まず24〜48時間待ってから調査を始めるのが良い判断です。GA4側の処理遅延で翌々日にテーブルが作成されることもあります。
:::

---

## STEP 3：GA4管理画面でリンク状態を確認する

BigQuery側に問題がなければ、GA4側の設定を確認します。

1. GA4管理画面を開く
2. 「プロパティ設定」→「製品リンク」→「BigQueryのリンク」
3. リンクが「有効」になっているか確認
4. エクスポート頻度（毎日 / ストリーミング）の設定を確認

よくあるパターン：

- GA4プロパティの管理者が変わり、リンクが解除された
- GCPプロジェクトの課金設定が無効化された
- BigQuery APIが無効化された

---

## STEP 4：GCPの権限と課金を確認する

### BigQuery APIの有効化確認

```bash
gcloud services list --enabled --project=beeracle | grep bigquery
```

`bigquery.googleapis.com` が表示されなければ、APIが無効化されています。

```bash
gcloud services enable bigquery.googleapis.com --project=beeracle
```

### 課金アカウントの確認

```bash
gcloud billing projects describe beeracle
```

`billingEnabled: true` であることを確認します。課金が無効だとエクスポートが停止します。

### サービスアカウントの権限確認

GA4からBigQueryへのエクスポートには、Firebase用のサービスアカウントに `BigQuery データ編集者` ロールが必要です。

```bash
gcloud projects get-iam-policy beeracle \
  --flatten="bindings[].members" \
  --format="table(bindings.role, bindings.members)" \
  --filter="bindings.role:bigquery"
```

---

## STEP 5：エクスポートの再開手順

原因を特定して対処した後、エクスポートを再開します。

### リンクが解除されていた場合

1. GA4管理画面 →「BigQueryのリンク」→「リンク」
2. GCPプロジェクトを選択
3. データセットのリージョンを選択（既存データセットと同じリージョンを選ぶ）
4. エクスポート頻度を選択

:::message
リンクを再設定した場合、再設定日以降のデータからエクスポートが再開されます。停止期間中のデータは自動的にはバックフィルされません。
:::

### 停止期間のデータを補完する方法

エクスポートが停止していた期間のデータは、GA4の管理画面から手動でバックフィルをリクエストできます（2024年以降の機能）。

1. GA4管理画面 →「BigQueryのリンク」
2. 対象のリンクを選択
3. 「バックフィル」→ 対象期間を指定してリクエスト

ただし、バックフィルには以下の制限があります。

- 過去365日分まで
- 1日あたりのバックフィル上限あり
- 処理完了まで数時間かかる

---

## エクスポート停止を早期検知する仕組み

問題が長期化する前に検知できる仕組みを用意しておくのが理想です。

### BigQuery Scheduled Queryでアラート

```sql
-- 日次で実行し、昨日のテーブルが存在しない場合にアラート
DECLARE yesterday STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

SELECT
  CASE
    WHEN COUNT(*) = 0
    THEN ERROR(CONCAT('GA4エクスポートテーブルが見つかりません: events_', yesterday))
  END
FROM `beeracle.analytics_263425816.__TABLES__`
WHERE table_id = CONCAT('events_', yesterday)
```

Scheduled Queryの失敗通知をメールやSlackに送る設定を組み合わせると、停止を当日〜翌日に検知できます。

### Cloud Monitoringでの監視

GCPのCloud Monitoringで以下のメトリクスを監視する方法もあります。

- `bigquery.googleapis.com/storage/table_count`：テーブル数の増加が止まったらアラート
- `bigquery.googleapis.com/storage/stored_bytes`：ストレージサイズの増加が止まったらアラート

---

## よくあるトラブルと対処法まとめ

| 症状 | 原因 | 対処 |
|------|------|------|
| 昨日のテーブルがない | GA4の処理遅延 | 48時間待つ |
| 3日以上テーブルがない | リンク解除/課金停止 | GA4管理画面・GCPコンソール確認 |
| テーブルはあるが行数が0 | ストリーミング設定の問題 | エクスポート頻度を確認 |
| intraday_テーブルだけある | 日次エクスポートのみ遅延 | 翌日まで待つ（intradayは正常） |
| エラーメッセージが出る | 権限不足 | IAMロールを確認 |

---

## まとめ

GA4のBigQueryエクスポートは一度設定すれば安定して動きますが、権限変更や課金停止で突然止まることがあります。

自分としては、`INFORMATION_SCHEMA` での定期チェックとScheduled Queryによるアラートを組み合わせておくと、停止に気づくのが遅れるリスクを大幅に減らせると感じています。

皆さんはエクスポートの監視、どのように対応していますか？コメントで共有いただけると参考になります。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
