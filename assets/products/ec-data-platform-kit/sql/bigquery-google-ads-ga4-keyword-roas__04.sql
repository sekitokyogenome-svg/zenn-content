-- BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する
-- 用途: 結果をLooker Studioで可視化するヒント
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `your_project.reporting.keyword_roas_monthly` AS
(
  -- 上記の最終SELECT文をここに貼り付ける
);
