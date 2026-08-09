---
title: "BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック"
emoji: "💡"
type: "tech"
topics: ["bigquery","sql","googlecloud","cost","dataengineering"]
published: false
---

## はじめに

「GA4のデータをBigQueryで分析しようと始めたら、気づいたら月のGCP請求が数万円になっていた」というご相談を、EC事業者様やWebコンサルタントの方々からよくいただきます。BigQueryは強力な分析基盤ですが、使い方を誤ると想定外のコストが積み上がりやすいツールでもあります。

BigQueryの料金体系は、クエリが読み取ったデータ量に応じた「オンデマンド課金」が基本です（執筆時点では1TB読み取りあたり約$6.25）。データが数十GBであれば月数百円で収まりますが、GA4のような日々蓄積するログデータは油断するとあっという間にGBを超え、複数のクエリを何度も実行することでコストが膨らんでいきます。

この記事では、BigQueryを使い始めて間もない方でも取り組みやすい、コスト削減の実践テクニックを7つご紹介します。特にGA4のBigQueryエクスポートを活用されている方にとって、すぐに役立つ内容を中心にまとめています。

---

## テクニック1：パーティション絞り込みで読み取りデータ量を減らす

GA4のBigQueryエクスポートテーブルは、日付ごとに分割された「パーティションテーブル」として保存されています。`_TABLE_SUFFIX`を使って対象期間を絞り込むだけで、読み取りデータ量を大幅に削減できます。

```sql
-- 直近30日分だけを対象にする例
SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

期間指定なしで`events_*`のワイルドカードクエリを実行してしまうと、蓄積された全期間のデータを読み取ることになります。分析目的に合わせて必要な期間だけを指定する習慣を身につけることが、コスト管理の第一歩です。

:::message
クエリ実行前に右上に表示される「処理されるデータ量」の見積もりを必ず確認しましょう。実行前の段階でおおよそのコストを把握できます。
:::

---

## テクニック2：SELECT * を避けて必要な列だけ取得する

BigQueryは列指向データベースのため、`SELECT *`で全カラムを取得するとコストが大きく跳ね上がります。分析に必要な列だけを明示的に指定するだけで、読み取りデータ量を半分以下に抑えられることも珍しくありません。

GA4テーブルには`event_params`や`user_properties`などのネスト構造が含まれており、全展開するとデータ量が膨大になります。以下のように、必要なフィールドのみをUNNESTで展開してください。

```sql
-- ga_session_id と流入元を取得する例
SELECT
  user_pseudo_id,
  event_timestamp,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'session_start'
```

`ga_session_id`はネストされた`event_params`の中に格納されているため、`UNNEST(event_params)`を経由して取得する必要があります。また、流入元の情報は`collected_traffic_source.manual_medium`および`collected_traffic_source.manual_source`から参照してください。

---

## テクニック3：クエリ結果をテーブルに保存して再利用する

同じ集計を何度も実行しているケースは、コスト増加の大きな原因のひとつです。毎朝確認する日次サマリーや月次レポートなど、定期的に使う集計結果はBigQueryのテーブルに書き出しておき、そのテーブルを参照する形に変えるだけでコストを抑えられます。

BigQueryにはクエリ結果を宛先テーブルに保存する機能があり、スケジュールクエリと組み合わせることで「1日1回だけ元データを集計し、結果テーブルを更新する」という仕組みを作れます。BI ToolやLooker Studioのダッシュボードはこの結果テーブルに接続することで、毎回の読み取りコストをゼロに近づけることができます。

:::message
Looker Studioからの接続では、ダッシュボードが開かれるたびにBigQueryへクエリが発行されます。利用人数が多いダッシュボードほど、結果テーブルへの接続切り替えの効果が大きくなります。
:::

---

## テクニック4：マテリアライズドビューで集計コストを自動化する

BigQueryには「マテリアライズドビュー（Materialized View）」という機能があります。通常のビューとは異なり、集計結果をあらかじめキャッシュしておく仕組みで、参照時の読み取りコストを削減しつつ、元テーブルの更新に合わせて自動でリフレッシュされます。

```sql
-- セッション別流入元サマリーのマテリアライズドビュー例
CREATE MATERIALIZED VIEW `your_project.your_dataset.mv_session_traffic`
AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  event_name = 'session_start'
GROUP BY
  event_date,
  traffic_medium,
  traffic_source
```

マテリアライズドビューはデータの鮮度とコストのバランスを取るうえで非常に有効です。毎日更新されるレポートには特に向いています。

---

## テクニック5：BigQueryのコスト上限（カスタムクォータ）を設定する

うっかりミスや誤操作による大量読み取りを防ぐには、BigQueryのカスタムクォータ設定が有効です。GCPコンソールから「プロジェクト単位の1日あたりの最大クエリ使用量（TB）」を設定することができ、指定した上限に達するとクエリがブロックされます。

設定手順はGCPコンソールの「BigQuery」→「管理」→「クォータ」から行えます。月1万円以内に収めたい場合、1TBあたり約$6.25（執筆時点）を基準に計算すると、月あたり約50TB・1日あたり約1.5TBが目安となります。チームで利用している場合は、ユーザーごとのクォータ設定も組み合わせることを検討してください。

:::message
クォータによるブロックはあくまで安全網です。日常的なクエリ設計の段階でデータ量を絞り込むことが、コスト管理の基本姿勢です。
:::

---

## テクニック6：プレビューとドライランでコストを事前確認する

BigQueryのコンソールには、実際にクエリを実行せずにデータ量の見積もりを確認できる「ドライラン」機能があります。クエリを書いた後、実行前に右上の「処理されるデータ量」を確認する習慣をつけるだけで、コストの見通しが立てやすくなります。

また、テーブルの内容を確認したいだけであれば、GCPコンソール上の「プレビュー」タブを活用してください。プレビューはコストが発生しないため、テーブル構造の確認やサンプルデータの確認に便利です。

bqコマンドラインツールを使う場合は、`--dry_run`フラグでドライランを実行できます。

```bash
bq query --dry_run --use_legacy_sql=false \
  'SELECT event_name FROM `your_project.analytics_XXXXXXX.events_20260101` LIMIT 10'
```

---

## テクニック7：不要なテーブルと期限切れポリシーを活用する

分析作業中に作成した一時テーブルや中間テーブルが溜まっていくと、ストレージコストが増加します。BigQueryでは、テーブルに「有効期限」を設定することができ、一定期間後に自動削除されます。

```sql
-- 有効期限付きのテーブル作成例（7日後に自動削除）
CREATE TABLE `your_project.your_dataset.temp_session_summary`
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  MIN(event_timestamp) AS session_start_ts
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  user_pseudo_id, ga_session_id
```

また、データセット単位でデフォルトの有効期限を設定しておくと、作成したすべてのテーブルに自動的に期限が適用されます。作業用データセットとレポート用データセットを分けて管理すると、誤って本番テーブルを削除するリスクも減らせます。

---

## まとめ

BigQueryのクエリコストを月1万円以下に抑えるための7つのテクニックをご紹介しました。

| テクニック | 効果 |
|---|---|
| パーティション絞り込み | 読み取りデータ量を削減 |
| 必要列のみ取得 | 列数に応じたコスト削減 |
| 結果テーブルへの保存 | 繰り返し集計コストをゼロ化 |
| マテリアライズドビュー | 自動キャッシュで参照コスト削減 |
| カスタムクォータ設定 | 上限超過を防ぐ安全網 |
| ドライランとプレビュー | 実行前にコスト確認 |
| テーブル有効期限の設定 | ストレージコストの自動管理 |

まず取り組みやすいのは「パーティション絞り込み」「必要列のみ取得」「カスタムクォータ設定」の3つです。この3点を整えるだけでも、月額コストが大きく変わるケースがあります。

BigQueryは使いこなせば強力なデータ基盤になりますが、設計の段階でコスト意識を持つことが長期的な運用の鍵です。GA4との連携や自社データ分析にお悩みの際は、ぜひ以下のご相談窓口もご活用ください。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】](https://zenn.dev/web_benriya/articles/gemini-bigquery-pricing-complete-guide)
- [BigQueryでGA4データのコスト管理・クエリ最適化入門](https://zenn.dev/web_benriya/articles/bigquery-ga4-cost-query-optimization)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
