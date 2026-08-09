---
title: "BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する"
emoji: "📊"
type: "tech"
topics: ["bigquery","sql","googlecloud","cost","dataengineering"]
published: false
book_only: true
---

## はじめに

「BigQueryの請求金額が先月より急に増えていたけれど、どのクエリが原因なのか分からない」——こうした状況に心当たりはないでしょうか。BigQueryはオンデマンド課金の場合、スキャンしたデータ量に応じて費用が発生するため、重いクエリが繰り返し実行されると、気づかないうちにコストが積み上がってしまいます。

特に複数のメンバーやツールがBigQueryにアクセスする環境では、誰がいつどのクエリを実行したかを把握するのが難しくなります。スプレッドシートで手動管理しようとしても、抜け漏れが出やすく、問題が発生してから原因を追うのに時間がかかってしまうことも少なくありません。

この記事では、BigQueryに標準搭載されている `INFORMATION_SCHEMA` ビューを活用して、クエリの実行履歴やコスト情報をSQLで取得し、定期的なモニタリング体制を整える方法をご紹介します。エンジニアでなくても理解できるよう、クエリの意味も一つひとつ丁寧に解説します。

---

## INFORMATION_SCHEMAとは何か

`INFORMATION_SCHEMA` は、BigQueryが内部的に収集しているメタデータにアクセスするための仕組みです。データベースの構造情報（テーブル一覧やスキーマ定義）だけでなく、ジョブの実行履歴やスロット使用量なども参照できます。

BigQueryのコスト監視で特に役立つのは以下の2つのビューです。

- **`INFORMATION_SCHEMA.JOBS`** — プロジェクト内で実行されたクエリジョブの詳細（実行時刻、スキャンバイト数、実行ユーザー、処理時間など）
- **`INFORMATION_SCHEMA.JOBS_BY_USER`** — ユーザー別に絞り込んだジョブ情報（自分が実行したジョブのみ参照したい場合に便利）

これらのビューはリアルタイムに近い情報を返しますが、過去180日分のデータを保持している点もポイントです。定期的にクエリを実行して結果をテーブルに蓄積していくことで、コスト推移の分析にも活用できます。

:::message
`INFORMATION_SCHEMA.JOBS` を参照するには、対象プロジェクトに対して `bigquery.jobs.list` 権限が必要です。通常は「BigQuery 管理者」または「BigQuery ジョブユーザー」のロールがあれば参照できます。
:::

---

## 直近7日間のコスト上位クエリを抽出する

まずは、過去7日間でスキャンデータ量が多かったクエリを上位10件抽出するSQLを見てみましょう。これにより、コストの大半を占めているクエリを素早く特定できます。

```sql
SELECT
  job_id,
  user_email,
  query,
  creation_time,
  ROUND(total_bytes_processed / POW(1024, 4), 4) AS processed_tb,
  ROUND(total_bytes_processed / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_sec,
  state
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
ORDER BY
  total_bytes_processed DESC
LIMIT 10;
```

このクエリのポイントを整理します。

- `total_bytes_processed / POW(1024, 4)` でバイトをテラバイトに変換しています
- `* 6.25` はBigQueryオンデマンド料金（$6.25/TB）の概算です。レートは変動するため、正確な金額はGCPコンソールでご確認ください
- `error_result IS NULL` でエラーになったクエリを除外しています

`region-asia-northeast1` の部分はご自身のプロジェクトのリージョンに合わせて変更してください（東京リージョンの場合はそのままで構いません）。

:::message
料金の計算はあくまでも参考値です。キャッシュが利用された場合やフラットレート契約の場合は計算方法が異なります。請求の確認はCloud Billingで行ってください。
:::

---

## ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む

プロジェクトに複数のメンバーがいる場合、誰がどのくらいのデータをスキャンしているかをユーザー別に集計するとチームの利用傾向が見えてきます。

```sql
SELECT
  DATE(creation_time, 'Asia/Tokyo') AS query_date,
  user_email,
  COUNT(*) AS job_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 4) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
GROUP BY
  query_date,
  user_email
ORDER BY
  query_date DESC,
  total_processed_tb DESC;
```

このクエリを週次や月次でスケジュール実行し、別テーブルに蓄積しておくと、月次レポートの作成にも役立ちます。Looker Studioと接続すれば、ユーザー別・日別のコスト推移をグラフで可視化することも可能です。

特定のユーザーのスキャン量が突出して多い場合、そのユーザーのクエリを個別に確認して最適化の余地がないかを検討するきっかけになります。

---

## 定期監視の仕組みをBigQueryスケジュールクエリで構築する

コスト監視を継続するには、手動でクエリを実行するのではなく、BigQueryのスケジュールクエリ機能を使って自動化するのが現実的です。

以下のSQLは、毎日実行してその日のジョブサマリーを専用テーブルに書き込むためのものです。

```sql
-- 前日分のジョブサマリーを集計テーブルに追記する
SELECT
  DATE(creation_time, 'Asia/Tokyo') AS job_date,
  user_email,
  COUNT(*) AS job_count,
  COUNTIF(error_result IS NOT NULL) AS error_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 6) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 4) AS estimated_cost_usd,
  ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)), 1) AS avg_duration_sec
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  DATE(creation_time, 'Asia/Tokyo') = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
GROUP BY
  job_date,
  user_email;
```

スケジュールクエリの設定手順は以下のとおりです。

```
1. BigQueryコンソールを開く
2. 上記クエリをエディタに貼り付ける
3. 「スケジュール」→「新しいスケジュールクエリを作成」をクリック
4. 繰り返し頻度：毎日、時刻：07:00（JST）などに設定
5. 書き込み先テーブルに集計用テーブルを指定（追加書き込みモード）
6. 保存して完了
```

これにより、毎朝前日分のコストサマリーが自動的に蓄積されていきます。

:::message
スケジュールクエリを実行するサービスアカウントに、`INFORMATION_SCHEMA.JOBS` の参照権限と書き込み先テーブルへの編集権限が付与されているかをあらかじめご確認ください。
:::

---

## アラート設定でコスト超過を早期に検知する

サマリーテーブルを作成したら、Cloud Monitoringのアラートを組み合わせることで、日次コストが閾値を超えた際に通知を受け取ることができます。ただし、より手軽な方法としてBigQueryの「クエリあたりの最大課金バイト数」制限を活用する方法もあります。

BigQueryコンソールの「詳細設定」から、ユーザーまたはプロジェクト全体に対してスキャン量の上限（バイト単位）を設定することが可能です。この上限を超えるクエリは実行がキャンセルされるため、突発的なコスト超過の抑止に有効です。

```sql
-- 特定ユーザーの1クエリあたりの最大スキャン量を設定する例（DDL）
ALTER USER `user@example.com`
SET OPTIONS (
  max_query_bytes = 107374182400  -- 100GB
);
```

:::message
`ALTER USER` 構文はBigQuery Enterprise版の一部機能であり、プロジェクトの設定によっては利用できない場合があります。利用可否は管理者にご確認ください。
:::

また、スケジュールクエリの結果をGoogle スプレッドシートと連携させる構成も、エンジニア以外のメンバーが確認しやすいレポート環境として有効です。Looker StudioのBigQuery接続であれば、ほぼリアルタイムでダッシュボードに反映されます。

---

## まとめ

BigQueryの `INFORMATION_SCHEMA.JOBS` を活用することで、クエリのコスト・実行履歴・ユーザー別の利用状況を、追加ツールなしにSQLだけで把握できます。要点を整理すると以下のとおりです。

- **コスト上位クエリの特定**: `total_bytes_processed` の降順で上位クエリを抽出し、最適化の優先順位を付ける
- **ユーザー別・日別の集計**: チーム内の利用傾向を可視化し、突出した利用者がいれば個別にフォローする
- **スケジュールクエリで自動化**: 日次で集計テーブルに蓄積し、Looker Studioと連携してダッシュボードを構築する
- **スキャン量の上限設定**: 突発的なコスト超過を防ぐためのガードレールとして活用する

コスト監視は「問題が起きてから調べる」ではなく、「日常的に把握できる仕組みを作る」ことが大切です。まずは今回ご紹介したクエリを実行して、自プロジェクトの現状を確認することから始めてみてください。

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
