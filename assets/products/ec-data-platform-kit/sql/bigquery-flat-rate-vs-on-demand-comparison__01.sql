-- BigQueryのフラットレート vs オンデマンド料金を実データで比較してどちらが安いか検証した
-- 用途: 実際のクエリで処理量を比較してみた
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
