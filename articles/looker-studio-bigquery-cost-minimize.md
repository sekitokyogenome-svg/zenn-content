---
title: "Looker StudioでBigQueryに接続するときの料金を最小化する設定"
emoji: "💰"
type: "tech"
topics: ["lookerstudio","bigquery","cost"]
published: false
---

## はじめに

「Looker StudioからBigQueryに接続したら、思ったより料金がかかっていた」という経験はないでしょうか。

Looker Studioは無料のBIツールですが、データソースにBigQueryを使う場合、クエリのスキャン量に応じた料金が発生します。ダッシュボードを開くたびに裏側でSQLが走るため、設定を誤ると月額数万円の請求が来ることもあります。

この記事では、Looker Studio × BigQueryの構成でコストを抑えるための具体的な設定と運用方法を解説します。

## BigQueryの課金体系をおさらいする

BigQueryのオンデマンド料金は、クエリがスキャンしたデータ量に対して課金されます。

- 1TBあたり約$6.25（2026年3月時点、東京リージョン）
- 毎月1TBまでは無料枠あり
- テーブル全体をスキャンすると、不要なカラムも課金対象になる

Looker Studioはダッシュボードを開くたび、フィルタを変えるたびにクエリを発行します。閲覧者が多いほどクエリ数は増えるため、設計段階でのコスト対策が重要です。

## 方法1: BIエンジン（BI Engine）を有効化する

BigQuery BI Engineは、インメモリで高速にクエリを処理する機能です。Looker Studioとの相性が良く、コスト削減にも直結します。

### 設定手順

1. Google Cloudコンソールで「BigQuery」→「BI Engine」を開く
2. 「予約を作成」をクリック
3. リージョン（例: `asia-northeast1`）を選択
4. 容量を設定する（最小1GB）

```
リージョン: asia-northeast1
容量: 1GB（小規模ダッシュボードなら十分）
月額料金: 約$36.50/GB
```

BI Engineを使うと、同じクエリが何度実行されてもオンデマンド料金が発生しません。閲覧回数が多いダッシュボードほど効果が大きくなります。

### BI Engineが適さないケース

- 1回のクエリで扱うデータが数十GB以上
- 複雑なJOINやサブクエリを多用している
- BI Engineの容量を超えるデータセット

このような場合は、次に紹介するマテリアライズドビューやテーブル集約が有効です。

## 方法2: マテリアライズドビューで集計済みデータを用意する

GA4のイベントテーブルは日ごとに数百MBになることもあります。毎回生データをスキャンするのではなく、集計済みのテーブルを作っておくと大幅にコストを削減できます。

```sql
CREATE MATERIALIZED VIEW `project.dataset.mv_daily_sessions`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 720
)
AS
SELECT
  event_date,
  COUNT(DISTINCT CONCAT(user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date;
```

:::message
マテリアライズドビューは自動的にキャッシュが更新されます。`refresh_interval_minutes` を適切に設定して、更新頻度を制御してください。
:::

このビューをLooker Studioのデータソースに指定すれば、クエリのスキャン量はMB単位に収まります。

## 方法3: Looker Studioのキャッシュ設定を見直す

Looker Studioには、データソースごとのキャッシュ設定があります。

### キャッシュ有効期限の設定

1. Looker Studioでレポートを開く
2. 「リソース」→「追加済みのデータソースの管理」
3. 対象データソースの「編集」をクリック
4. 「データの更新頻度」を設定する

推奨設定は以下の通りです。

| ダッシュボードの用途 | 推奨キャッシュ時間 |
|---|---|
| リアルタイム監視 | 1時間 |
| 日次レポート | 12時間 |
| 月次レポート | 24時間（最大） |

キャッシュが有効な間は、同じクエリが再実行されません。特に閲覧者が多いダッシュボードでは大きな効果があります。

## 方法4: パーティションテーブルを活用する

BigQueryのパーティションテーブルを使うと、日付で絞り込んだときに不要な日のデータがスキャンされなくなります。

GA4のエクスポートテーブル（`events_*`）はシャーディングテーブルですが、カスタムテーブルを作る場合はパーティションを指定してください。

```sql
CREATE TABLE `project.dataset.sessions_partitioned`
PARTITION BY event_date
CLUSTER BY traffic_source
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  traffic_source.source AS traffic_source,
  traffic_source.medium AS traffic_medium,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
FROM
  `project.analytics_XXXXXXX.events_*`;
```

Looker Studioの日付フィルタが`event_date`カラムに紐づいていれば、自動的にパーティションプルーニングが効きます。

## 方法5: 抽出データソースを使う

Looker Studioには「抽出データソース」という機能があります。これはBigQueryのデータを定期的にLooker Studio側にコピーして保持する仕組みです。

### 抽出データソースの設定方法

1. Looker Studioで「リソース」→「抽出データの管理」
2. 「抽出データソースを追加」をクリック
3. 元のBigQueryデータソースを選択
4. 抽出するフィールドと日付範囲を設定
5. 自動更新のスケジュールを設定（毎日など）

これにより、ダッシュボードの閲覧時にはBigQueryへのクエリが発生しません。更新時のみ1回のクエリが走ります。

:::message
抽出データソースには行数の上限（1億行）があります。大規模データの場合は事前に集計テーブルを作り、それを抽出元にするのがおすすめです。
:::

## コスト監視の設定

対策を実施したら、効果を測定するためにコスト監視も設定しておきましょう。

### BigQueryのクエリコスト上限を設定する

Google Cloudコンソールの「BigQuery」→「管理設定」で、プロジェクト単位・ユーザー単位のスキャン量上限を設定できます。

```
プロジェクトのカスタムクォータ: 10TB/日
ユーザーのカスタムクォータ: 1TB/日
```

上限を超えるとクエリがブロックされるため、予期せぬ高額請求を防止できます。

### Cloud Monitoringでアラートを作る

BigQueryのスキャン量をCloud Monitoringで監視し、閾値を超えたらメール通知する設定も有効です。月の途中で予算を超えそうなときに気づけます。

## まとめ

Looker Studio × BigQueryの料金を最小化するポイントをまとめます。

1. **BI Engine**: 閲覧頻度が高いダッシュボードに有効
2. **マテリアライズドビュー**: 集計済みデータでスキャン量を削減
3. **キャッシュ設定**: 用途に応じてキャッシュ時間を長めに設定
4. **パーティション**: 日付フィルタのスキャン範囲を限定
5. **抽出データソース**: BigQueryへのクエリ自体を減らす
6. **コスト監視**: クォータとアラートで予防する

これらを組み合わせることで、月間のBigQuery料金を無料枠内に収めることも十分に可能です。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
