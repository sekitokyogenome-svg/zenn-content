---
title: "BigQueryのフラットレート vs オンデマンド料金を実データで比較してどちらが安いか検証した"
emoji: "💰"
type: "idea"
topics: ["bigquery","googlecloud","cost","sql","dataengineering"]
published: false
---

## はじめに

「BigQueryを使い始めてから、月末の請求を見るたびにヒヤッとする」——そんな経験はありませんか。GA4のデータをBigQueryにエクスポートして分析を始めると、最初のうちはコストを気にせず使えるのですが、データ量が増えてきたタイミングで急に料金が跳ね上がることがあります。

BigQueryの料金体系には、大きく分けて「オンデマンド（クエリ課金）」と「フラットレート（定額）」の2種類があります。どちらが自社に合っているかを判断しないまま使い続けると、数万円から数十万円規模の無駄が発生することもあります。

この記事では、実際のGA4エクスポートデータを使ったクエリを例に取りながら、2つの料金モデルの仕組みと向き不向きを整理します。「エンジニアではないけれど、コストの判断材料が欲しい」という方にも読んでいただけるよう、できる限り平易に解説しています。

---

## BigQueryの料金体系をおさらいする

まず、2つの料金モデルの基本を確認しておきましょう。

**オンデマンド料金**は、クエリが処理したデータ量に応じて課金されるモデルです。2024年時点では、処理したデータ1TBあたり約6.25ドル（東京リージョン）が目安となっています。小さいクエリであれば無料枠（月1TB）に収まることも多く、使い始めのフェーズには向いています。ただし、誤って全テーブルをスキャンするようなクエリを実行すると、一度の操作で数千円が飛ぶこともあります。

**フラットレート（Editions）**は、スロット（処理能力の単位）を時間単位または月単位で購入するモデルです。2023年のEditions刷新以降は、「Standard」「Enterprise」「Enterprise Plus」という3つのエディションが用意されており、最小購入単位も柔軟になっています。月額固定でスロットを確保するため、クエリをどれだけ実行しても基本料金は変わりません。

判断のポイントは**「月間クエリ処理量が何TBか」**に尽きます。処理量が少なければオンデマンドが安く、多ければフラットレートが有利になります。

---

## 損益分岐点をシミュレーションする

フラットレートへ移行したほうがコスト的に有利になる目安として、**月100スロット（Standard Editions）の場合を例**に試算してみます。

Standard Editionsの場合、100スロットを月単位で契約すると東京リージョンでおよそ月$2,000前後（時間契約の場合はさらに細かく計算できます）。一方、オンデマンドで同額に達するには、月間約320TBの処理が必要です（$2,000 ÷ $6.25/TB = 320TB）。

| 月間処理量 | オンデマンド費用（目安） | フラットレート（目安） | 有利なプラン |
|---|---|---|---|
| 10 TB | 約$62 | 約$2,000〜 | オンデマンド |
| 50 TB | 約$312 | 約$2,000〜 | オンデマンド |
| 200 TB | 約$1,250 | 約$2,000〜 | オンデマンド（僅差） |
| 400 TB | 約$2,500 | 約$2,000〜 | フラットレート |
| 1,000 TB | 約$6,250 | 約$2,000〜 | フラットレート（大幅） |

多くの中小規模のECサイトやWebメディアでは、GA4エクスポートのデータだけであれば月間処理量が数十TBに収まることが多く、その場合はオンデマンドが合理的です。ただし、社内の複数チームが頻繁にアドホッククエリを実行する、またはBIツールが毎時クエリを投げているといった環境では、想定外に処理量が膨らむことがあります。

---

## GA4データを使ってクエリコストを事前に確認する方法

BigQueryでは、クエリを実行する前に「このクエリが何TBを処理するか」を調べることができます。Webコンソール上でクエリを入力すると右上に処理量が表示されますが、コマンドラインでも確認可能です。

以下は、GA4のBigQueryエクスポートテーブルからセッション数とチャネルを集計する典型的なクエリです。`--dry_run`オプションをつけることで、実際には課金されずに処理バイト数だけを確認できます。

```bash
bq query \
  --use_legacy_sql=false \
  --dry_run \
  'SELECT
     collected_traffic_source.manual_medium AS medium,
     collected_traffic_source.manual_source AS source,
     COUNT(DISTINCT
       (SELECT value.int_value
        FROM UNNEST(event_params)
        WHERE key = "ga_session_id")
     ) AS sessions
   FROM
     `your_project.analytics_XXXXXXXXX.events_*`
   WHERE
     _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
     AND event_name = "session_start"
   GROUP BY
     medium, source
   ORDER BY
     sessions DESC'
```

このコマンドを実行すると、標準出力に処理バイト数が返ってきます。これを月間のクエリ実行頻度と掛け合わせることで、月間コストの概算が出せます。

:::message
`ga_session_id` はイベントパラメータの中にネストされているため、`UNNEST(event_params)` を経由して取得する必要があります。テーブルの直接カラムとして参照しようとするとエラーになりますのでご注意ください。
:::

---

## 実際のクエリで処理量を比較してみた

同じ分析目的でも、クエリの書き方によって処理データ量が大きく変わります。以下は「先月の流入チャネル別セッション数」を取得するクエリの、非効率な例と効率的な例の比較です。

**非効率な例（全カラムをスキャン）**

```sql
SELECT *
FROM `your_project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
```

これは全カラムを取得するため、1ヶ月分のデータで数十GB〜数TBをスキャンしてしまいます。

**効率的な例（必要なカラムのみ指定）**

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = "ga_session_id"
    LIMIT 1
  ) AS ga_session_id
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
  AND event_name = "session_start"
```

BigQueryは列指向ストレージを採用しているため、`SELECT *`を避けて必要なカラムだけを指定するだけで、処理量を大幅に削減できます。場合によっては同じ分析が1/10以下のコストで済むことがあります。

オンデマンドプランを使っている場合、このような最適化が直接コスト削減につながります。フラットレートの場合はコストへの影響はありませんが、スロットの占有時間が短くなる分、他のクエリのパフォーマンスが向上するというメリットがあります。

---

## どちらを選ぶべきか：判断フローまとめ

最終的にどちらのプランが合うかは、以下の観点で判断することをお勧めします。

**オンデマンドが向いているケース**

- 月間クエリ処理量が200TB以下に収まっている
- データ分析の頻度が低く、週数回程度のクエリ実行にとどまる
- まだBigQuery活用を試験導入している段階で、将来の処理量が読めない
- コストを使った分だけ把握したい

**フラットレートが向いているケース**

- 社内の複数チームや複数のBIツールが常時クエリを実行している
- 月間処理量が安定して300TB以上ある
- 処理スピードの安定性を重視したい（スロット不足による遅延を避けたい）
- 予算を固定費として管理したいという経営上の要件がある

なお、フラットレートに移行する際は「最初から大きなスロットを購入しない」ことがポイントです。EditionsではAutoscalingの設定もできるため、ベースラインを小さく抑えつつ、ピーク時に自動拡張する構成が現実的です。

---

## まとめ

BigQueryのオンデマンドとフラットレートは、どちらが絶対的に優れているということはなく、利用状況によって最適解が変わります。

- 月間処理量が少ない段階では、オンデマンドがコスト効率で優位
- 処理量が増えるにつれてフラットレートへの移行を検討する価値が出てくる
- クエリの最適化（必要カラムのみ選択、日付パーティションの活用）はどちらのプランでも重要
- `--dry_run` を活用してクエリ実行前にコストを確認する習慣をつける

料金プランの選択よりも先に、まずは現状の月間処理量を把握することをお勧めします。BigQueryのコンソールから「情報パネル」→「ジョブ履歴」や、Cloud Monitoringのメトリクスを使えば、過去の処理量を簡単に確認できます。

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
