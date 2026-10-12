# 架空 GA4 EC データ（SQL 検証用）

Zenn 記事「BigQuery だけで GA4 風の EC ダミーデータを作る」の付属データです。
**すべて架空です。実在のストア・顧客のデータではありません。**

| ファイル | 内容 |
|---|---|
| `events_all.ndjson.gz` | 生成済みデータ（13,417 行・展開後 約16.7MB、gzip 約 0.3MB） |
| `schema.json` | `bq load` 用のスキーマ |
| `01_generate_events.sql` | BigQuery だけで同じデータを作る SQL |
| `02_expectations.sql` | 期待値の `ASSERT`（件数・売上など） |
| `generate_ndjson.py` | BigQuery なしで同じデータを作る Python（`pip install pyfarmhash`） |

## 取り込む

```bash
# データセットを作り、NDJSON を読み込む（解凍してから）
bq mk --dataset --location=asia-northeast1 <PROJECT>:dummy_ga4_ec
gunzip -k events_all.ndjson.gz
bq load --source_format=NEWLINE_DELIMITED_JSON --schema=schema.json \
  <PROJECT>:dummy_ga4_ec.events_all events_all.ndjson
```

※ この `bq load` の手順は、この README の作成環境では実行していません（認証が使えないため）。スキーマは、実際に生成したテーブルの定義から書き起こしています。

## 仕込んだ罠

- T1: 同じ `transaction_id` の purchase が 5 件重複
- T2: `transaction_id` が NULL の purchase が 9 件
- T3: `ga_session_id` がユーザー間で衝突する
- T4: `purchase_revenue` は円、`purchase_revenue_in_usd` は USD

期待値: 購入 443 行 / 重複を除く注文番号 429 種 / NULL 9 件 / 重複込みの売上合計 3,238,700 円。

## 一致の確認

`generate_ndjson.py` の出力は、BigQuery で `01_generate_events.sql` を流して作ったテーブルと、
行数・イベント別件数・売上合計・タイムスタンプ／ユーザーID／注文番号／チャネルのチェックサムが一致することを確認しています
（行ごとの完全一致の検証は行っていません）。

## 実際の GA4 エクスポートとの違い

日別シャード（`events_YYYYMMDD`）にはしていません（必要なら記事の分割 SQL を使う）。`events_intraday_*` はなく、項目も一部だけです。
CVR や LTV の「値」の妥当性を見るためのデータではありません。SQL が動くかを確かめる用途です。
