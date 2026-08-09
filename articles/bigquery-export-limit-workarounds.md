---
title: "BigQueryのエクスポート上限に引っかかったときの回避策まとめ"
emoji: "🚧"
type: "tech"
topics: ["bigquery","googlecloud","sql","dataengineering","googleanalytics"]
published: false
---

## はじめに

「BigQueryで分析したデータをCSVに落としたいのに、ダウンロードボタンが途中で止まってしまう」「エクスポートしようとしたらエラーが返ってきた」——そんな経験はないでしょうか。

BigQueryはGoogleのフルマネージド型データウェアハウスで、GA4のイベントデータや注文履歴など大量のデータを蓄積するのには非常に向いています。しかしいざそのデータを外部に取り出したり、別のツールに連携しようとすると、思わぬ上限制限に行き当たることがあります。

この記事では、BigQueryのエクスポートに関する代表的な上限（制限）の種類と、それぞれの回避策を実例つきで解説します。GA4のBigQueryエクスポートを活用されている方にも参考になる内容です。エンジニアではない経営者や担当者の方にも読みやすいよう、なるべく平易な言葉で説明していきます。

---

## BigQueryのエクスポート上限の種類を把握しておく

回避策を考える前に、まずどのような上限が存在するかを整理しておきましょう。主なものは以下の3種類です。

**1. コンソール（ブラウザ）からのCSV/JSONダウンロード上限**
BigQueryのWebコンソールでクエリ結果をそのまま手元にダウンロードする場合、**最大16,000行**という制限があります。データが少量のうちはこれで十分ですが、GA4データのように日々積み上がるデータを扱うと、すぐに上限に到達してしまいます。

**2. Google Cloud Storage（GCS）へのエクスポート上限**
BigQueryのデータをCloud Storageに書き出す場合、1ファイルあたりの上限は**最大1GBまで**です。それを超えるテーブルをエクスポートしようとすると、ファイルを分割するためのワイルドカード指定が必要になります。また、1回のエクスポートジョブで書き出せるファイル数にも制限があります。

**3. APIやサービスアカウントのクォータ**
プログラムからAPIを呼び出してデータを取得する場合は、プロジェクトごとの1日あたりのクエリバイト数や、同時リクエスト数にクォータが設定されています。スケジュール実行や自動化ツールと組み合わせた際に問題になりやすいポイントです。

自分がどの上限に引っかかっているかを特定することが、回避策選択の第一歩です。

---

## 回避策①：GCSへのワイルドカードエクスポートで大容量データを分割出力する

コンソールのダウンロード（最大16,000行）では足りない場合、まずおすすめしたいのが**Cloud Storageへのエクスポート**です。BigQueryの「エクスポート」機能からGCSバケットを指定することで、テーブルをファイルに書き出せます。

テーブルのサイズが1GBを超える場合は、出力先ファイル名にワイルドカード（`*`）を使って分割出力します。以下はコンソールの「エクスポート」設定ではなく、`bq` コマンドラインツールで行う例です。

```bash
bq extract \
  --destination_format CSV \
  --compression GZIP \
  'my_project:my_dataset.my_table' \
  'gs://my-bucket/export/output_*.csv.gz'
```

`output_*.csv.gz` のようにアスタリスクを含めることで、BigQueryが自動的に `output_000000000000.csv.gz`、`output_000000000001.csv.gz` …と連番ファイルに分割して書き出してくれます。

GCSに書き出したファイルは、その後 `gsutil` コマンドでローカルにダウンロードしたり、Google DriveやLooker Studioに連携したりと、二次利用の幅が広がります。

:::message
GCSバケットとBigQueryプロジェクトは同じリージョンに揃えておくと、転送コストや速度の面で有利です。異なるリージョン間の転送は追加コストが発生する場合があります。
:::

---

## 回避策②：日付パーティションを活用してクエリ・エクスポート対象を絞り込む

GA4のBigQueryエクスポートテーブルは、`events_YYYYMMDD` という日付サフィックス付きのテーブルとして日次で蓄積されます。大量データをまとめて扱おうとするとクォータや処理時間の問題が出やすいため、**期間を分割してクエリやエクスポートを実行する**方法が有効です。

たとえば直近30日分のデータから、セッションIDと流入元を取得するクエリは以下のようになります。

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `my_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  1, 2, 3, 4
ORDER BY
  event_count DESC
```

`_TABLE_SUFFIX BETWEEN` を使うことで、クエリが読み込むデータ量を必要な期間に絞り込めます。これにより課金対象のスキャンバイト数が削減されるだけでなく、エクスポートのジョブサイズも抑えられます。

月次でのレポート作成であれば、月ごとにクエリを分けてGCSに書き出し、後から結合するという運用が現実的です。スケジュールドクエリを設定すれば、この分割処理を自動化することもできます。

:::message
`ga_session_id` はイベントレベルのカラムではなく、`event_params` の中にネストされています。`UNNEST(event_params)` を経由せずに直接参照しようとするとエラーになるため注意してください。
:::

---

## 回避策③：PythonスクリプトとBigQuery APIで柔軟にページング取得する

コンソールでもGCSエクスポートでも対応が難しい場合（たとえば特定の列だけを毎日差分で取得したい場合など）は、**PythonのBigQueryクライアントライブラリ**を使ってプログラム的にデータを取り出す方法があります。

以下はBigQuery APIでクエリを実行し、結果をPandasのDataFrameとしてローカルのCSVに書き出すシンプルな例です。

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="my_project")

query = """
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  event_date
FROM
  `my_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
"""

df = client.query(query).to_dataframe()
df.to_csv("output.csv", index=False, encoding="utf-8-sig")
print(f"{len(df)} 件を出力しました")
```

このスクリプトをCloud FunctionsやCloud Run Jobsに乗せれば、毎日自動で前日分のデータをCSV化してGCSやGoogle Driveに保存する、といった仕組みが構築できます。大量行をメモリ上に展開したくない場合は `to_dataframe()` の代わりにページングAPIを使うことも可能です。

APIのクォータが心配な場合は、BigQueryのレスポンスキャッシュ機能を活用するか、実行タイミングをオフピーク帯にずらすことで安定した動作につながります。

---

## 回避策④：Looker Studioを中継点として活用する

「CSVとして手元に持ちたいわけではなく、レポートや可視化ができれば十分」という場合は、**Looker Studio（旧Data Studio）をBigQueryに直接接続する**方法も選択肢の一つです。

Looker StudioはBigQueryのコネクタを標準で備えており、追加費用なしでテーブルやカスタムクエリの結果を読み込んでグラフや表を描けます。エクスポートのファイルサイズ制限を気にする必要がなく、レポートを都度更新するだけで常に最新データが反映されます。

ただし注意点として、Looker StudioはBigQueryにクエリを発行するたびにスキャンコストが発生します（BigQueryの無料枠を超えた場合）。複雑なクエリや大量データを頻繁に参照する場合は、**BigQuery上にビューや集計済みテーブルをあらかじめ作っておき、それをLooker Studioに接続する**設計にすると、コストと速度の両面で効果的です。

:::message
Looker Studioの「データ抽出」機能を使うと、BigQueryから取得したデータをLooker Studio内にキャッシュとして保持できます。参照頻度が高いレポートではキャッシュを活用することで、BigQueryへの問い合わせ回数を抑えられます。
:::

---

## まとめ

BigQueryのエクスポート上限に直面したときの主な回避策をまとめると、次のようになります。

| 状況 | おすすめの対応 |
|------|----------------|
| コンソールDLで16,000行を超える | GCSへのエクスポートに切り替える |
| テーブルが1GBを超えてGCS書き出しに失敗する | ファイル名にワイルドカード（`*`）を指定して分割出力 |
| クォータやスキャン量を減らしたい | `_TABLE_SUFFIX` で期間を絞ったクエリに変更する |
| 自動化・差分取得がしたい | PythonスクリプトとBigQuery APIで実装する |
| レポート目的でCSV不要 | Looker Studioに直接接続してビジュアル化する |

どの方法が最適かは、データ量・更新頻度・利用目的によって異なります。まずは「何の上限に引っかかっているのか」を明確にしてから対応策を選ぶと、余計な試行錯誤を減らせます。

GA4のBigQueryエクスポートをすでに設定済みの方は、日付パーティションの活用から着手するのが取り組みやすいでしょう。データ基盤の整備に不安を感じている方は、下記からお気軽にご相談ください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
