---
title: "【第5部 品質と復旧】GCSにバックアップしたGA4データをBigQueryに再インポートする手順"
---

## はじめに

GA4とBigQueryを連携して分析基盤を構築していると、「BigQueryのテーブルを誤って削除してしまった」「過去のデータを別プロジェクトに移したい」「長期保存のためにGCSへ退避したデータを再び分析に使いたい」といった場面に遭遇することがあります。

GA4のBigQueryエクスポート機能は、毎日のイベントデータを自動的にBigQueryのデータセットへ書き出してくれますが、長期間分のデータが蓄積されるとストレージコストが増大します。そのため、一定期間を過ぎたデータをGoogle Cloud Storage（GCS）にエクスポートし、BigQuery側から削除しているケースも少なくありません。

しかし、後から「やはりあの時期のデータを分析したい」という状況になることがあります。そのような場合でも、GCSに保存したデータをBigQueryへ再インポートすることで、通常のGA4エクスポートテーブルと同じ形式で分析を再開できます。

本章では、GCSにバックアップしたGA4データをBigQueryへ再インポートする手順を、できるだけ平易に解説します。GA4とBigQueryの連携を運用している担当者の方、またはデータ管理の見直しを検討しているWeb担当者の方に参考にしていただける内容です。

---

## GCSへのエクスポートとデータ形式を確認する

再インポートを行うには、まずGCS上に保存されているデータの形式を把握しておく必要があります。BigQueryからGCSへエクスポートする際、一般的に使用されるファイル形式は以下の3種類です。

- **Avro**（バイナリ形式・スキーマ情報を内包）
- **Parquet**（列指向バイナリ形式・圧縮効率が高い）
- **NDJSON / JSON Lines**（改行区切りのJSONテキスト）

GA4のBigQueryエクスポートテーブルは`events_YYYYMMDD`という日付ごとのパーティションテーブルとして格納されており、エクスポート時の形式によって再インポートの手順が若干異なります。

GCSバケット内のファイル一覧を確認するには、Google Cloud ConsoleのCloud Storageブラウザか、以下のコマンドを使用します。

```bash
gsutil ls gs://your-bucket-name/ga4-backup/
```

ファイルの拡張子（`.avro`、`.parquet`、`.json`）でどの形式で保存されているかを確認してください。エクスポート時の設定が不明な場合は、ファイルを1件ダウンロードしてバイナリエディタや`file`コマンドで確認する方法もあります。

:::message
GCSのエクスポートファイルには圧縮がかかっている場合があります（`.gz`など）。BigQueryへのインポート時は圧縮ファイルをそのまま読み込めますが、ファイルパスのURIにワイルドカード（`*`）を使用する際は圧縮形式を統一しておく必要があります。
:::

---

## BigQueryへの再インポート手順（bqコマンド編）

GCS上のデータをBigQueryへ読み込む方法はいくつかありますが、ここではCloud Shellや手元の端末から実行できる`bq`コマンドを使った方法を紹介します。

まず、インポート先となるデータセットとテーブルを決定します。GA4の標準エクスポートテーブル名は`events_YYYYMMDD`形式ですので、日付ごとに分けてインポートするのが管理しやすい構成です。

以下は、NDJSON形式で保存されたGA4データを`your_project.analytics_XXXXXXXXX.events_20240101`テーブルとして再インポートする例です。

```bash
bq load \
  --source_format=NEWLINE_DELIMITED_JSON \
  --replace \
  your_project:analytics_XXXXXXXXX.events_20240101 \
  gs://your-bucket-name/ga4-backup/events_20240101/*.json \
  gs://your-bucket-name/ga4-backup/schema.json
```

スキーマファイル（`schema.json`）は、元のBigQueryテーブルから事前に取得しておく必要があります。スキーマをJSONファイルとして出力するには、以下のコマンドを使用します。

```bash
bq show --schema --format=prettyjson \
  your_project:analytics_XXXXXXXXX.events_20240101 \
  > schema.json
```

Parquet形式の場合は`--source_format=PARQUET`、Avro形式の場合は`--source_format=AVRO`と指定します。Avroの場合はスキーマが内包されているため、スキーマファイルの指定を省略できることがあります。

:::message
`--replace`オプションを指定すると、既存テーブルが上書きされます。既存データを保持したい場合は`--noreplace`（または省略）を使用してください。意図しないデータ消失を避けるために、インポート前にテーブルの状態を確認することをお勧めします。
:::

---

## インポート後のデータ確認：GA4特有の構造を踏まえたSQL

データをインポートした後は、正しくデータが取り込まれているかを確認することが重要です。GA4のBigQueryエクスポートテーブルはネストされた構造（RECORD型）を持っているため、通常のフラットなテーブルとは異なるクエリ記述が必要です。

まず、基本的な件数確認とイベント種別の確認を行います。

```sql
SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `your_project.analytics_XXXXXXXXX.events_20240101`
GROUP BY
  event_name
ORDER BY
  event_count DESC
LIMIT 20;
```

次に、GA4特有のネスト構造である`event_params`から値を取得する例を示します。セッションIDはこの`event_params`配列をUNNESTして取り出す必要があり、直接カラムとして参照することはできません。

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `your_project.analytics_XXXXXXXXX.events_20240101`
WHERE
  event_name = 'page_view'
LIMIT 100;
```

流入元（参照元・メディア）を確認したい場合は、`collected_traffic_source`フィールドを使用します。

```sql
SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS session_count
FROM
  `your_project.analytics_XXXXXXXXX.events_20240101`
WHERE
  event_name = 'session_start'
GROUP BY
  source,
  medium
ORDER BY
  session_count DESC;
```

これらのクエリでデータが返ってくれば、インポートは正常に完了していると判断できます。

---

## 複数日付のデータを一括インポートするスクリプト

バックアップデータが複数日分ある場合、毎回手動でコマンドを実行するのは非効率です。シェルスクリプトを使えば、日付範囲を指定して繰り返し処理を行うことができます。

```bash
#!/bin/bash

PROJECT="your_project"
DATASET="analytics_XXXXXXXXX"
BUCKET="gs://your-bucket-name/ga4-backup"
SCHEMA_FILE="schema.json"
START_DATE="20240101"
END_DATE="20240131"

current_date="$START_DATE"
while [ "$current_date" -le "$END_DATE" ]; do
  table="${PROJECT}:${DATASET}.events_${current_date}"
  uri="${BUCKET}/events_${current_date}/*.json"

  echo "Loading: $table from $uri"

  bq load \
    --source_format=NEWLINE_DELIMITED_JSON \
    --replace \
    "$table" \
    "$uri" \
    "$SCHEMA_FILE"

  # 翌日の日付に進める（GNU date使用）
  current_date=$(date -d "${current_date} + 1 day" +%Y%m%d)
done

echo "インポート処理が完了しました。"
```

このスクリプトはCloud ShellやLinux環境で動作します。Windowsをお使いの場合は、Cloud Shellを利用するか、WSL（Windows Subsystem for Linux）上で実行してください。

:::message
スクリプト実行前に、対象の日付範囲でGCSにファイルが存在するかを`gsutil ls`で確認しておくと、エラー発生時の原因特定がしやすくなります。また、インポート先のデータセットが存在しない場合はあらかじめ作成しておく必要があります。
:::

---

## コスト面と運用上の注意点

GCSからBigQueryへのデータロード（`bq load`）は、BigQueryのロード操作として扱われ、**ロード自体の料金は無料**です（2024年時点のGoogle Cloudの料金体系では、バッチロードは無料枠内に含まれます）。ただし、以下の点は考慮が必要です。

**GCSのストレージ料金**
GCSにデータを長期保存する場合、ストレージクラスの選択が費用に影響します。頻繁にアクセスしないデータは「Nearline」「Coldline」「Archive」クラスを選ぶことでコストを抑えられます。ただし、取り出し時に転送料金が発生します。

**BigQueryのクエリ料金**
インポート後のデータに対してクエリを実行すると、スキャンしたデータ量に応じた料金が発生します。GA4データはネスト構造を多く含むため、`SELECT *`のような全カラム取得は費用が膨らみやすい傾向があります。必要なカラムのみを指定したクエリを心がけてください。

**データのバージョン管理**
インポートしたデータと現行のGA4エクスポートデータが混在しないよう、データセット名やテーブル名の命名規則を事前に決めておくことをお勧めします。たとえば、再インポートしたデータ用に専用のデータセット（例：`analytics_XXXXXXXXX_restored`）を作成するといった方法があります。

---

## まとめ

GCSにバックアップしたGA4データをBigQueryへ再インポートする手順は、大きく以下の流れになります。

1. **GCS上のファイル形式を確認する**（NDJSON / Parquet / Avro）
2. **BigQueryのスキーマファイルを取得しておく**（特にNDJSON形式の場合）
3. **`bq load`コマンドでインポートを実行する**（形式に合わせたオプション指定）
4. **インポート後にSQLで件数・構造を確認する**（UNNEST・collected_traffic_source等を活用）
5. **複数日分は自動化スクリプトで対応する**

GA4のBigQueryエクスポートデータは独自のネスト構造を持つため、インポート後の検証クエリを丁寧に行うことが大切です。特に`ga_session_id`の取得方法や流入元の参照フィールドは、標準的なSQLとは異なる書き方が必要ですので、本章のサンプルクエリを参考にしていただければと思います。

データ保全と分析の柔軟性を両立するために、GCSを活用したアーカイブ運用の導入もぜひ検討してみてください。
