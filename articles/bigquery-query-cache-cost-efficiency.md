---
title: "BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する"
emoji: "💾"
type: "tech"
topics: ["bigquery","sql","googlecloud","cost","dataengineering"]
published: false
book_only: true
---

## はじめに

BigQueryを使い始めてしばらく経つと、ふとこんな疑問が浮かぶことがあります。「毎日同じレポートを出しているのに、毎回費用が発生しているのだろうか？」「クエリをもう少し工夫するだけでコストを抑えられるのではないか？」

GA4のデータをBigQueryでレポーティングしている場合、日次で何十GBものデータをスキャンするクエリを繰り返し実行することも珍しくありません。オンデマンドクエリ（処理データ量課金）の場合、1TBあたり約6.25ドルの費用が発生するため、積み重なると無視できない金額になります。

実はBigQueryには「クエリキャッシュ」という機能が標準で備わっており、上手く活用することで同一クエリの再実行コストをゼロに抑えることができます。ただし、キャッシュが効く条件といくつかの落とし穴を理解しておかないと、「キャッシュが使えると思っていたのに実は毎回課金されていた」という事態になりかねません。

本記事では、BigQueryのクエリキャッシュの仕組みをわかりやすく解説し、日々の運用でコスト効率を高めるための実践的なポイントをご紹介します。

---

## クエリキャッシュの基本的な仕組み

BigQueryは、クエリを実行するたびにその結果を一時テーブルとしてキャッシュに保存します。その後、**まったく同じクエリ**が再度実行された場合、データをスキャンせずにキャッシュから結果を返します。このとき、スキャンしたデータ量はゼロとなり、オンデマンド課金の対象外になります。

キャッシュの有効期間は**24時間**です。同一クエリでも24時間を超えると自動的に無効になり、次回実行時には再スキャンが行われます。

キャッシュが有効に機能するかどうかは、BigQueryコンソールの実行結果パネルで確認できます。「キャッシュから取得されました」というメッセージが表示されていれば、その実行は無課金です。

:::message
クエリキャッシュはデフォルトで有効になっています。あえて無効化したい場合は、クエリ設定から「キャッシュされた結果を使用する」のチェックを外してください。テストや最新データの確認が目的でない限り、通常はキャッシュを有効にしたまま運用することをお勧めします。
:::

---

## キャッシュが効く条件と効かない条件

クエリキャッシュの恩恵を受けるには、いくつかの条件を満たす必要があります。逆に、これらの条件を外れると、同じように見えるクエリでもキャッシュがヒットしません。

**キャッシュが有効になる主な条件**

- クエリ文字列が完全に一致している（スペースや改行も含めて）
- 参照しているテーブルのデータが前回実行時から変更されていない
- `CURRENT_TIMESTAMP()`、`NOW()`、`RAND()` などの非決定論的関数を含まない
- テーブルが外部テーブル（Cloud StorageやSheetsなど）ではない
- ワイルドカードテーブル（`_TABLE_SUFFIX`）を使用していない

**キャッシュが無効になる代表的なケース**

GA4のBigQueryエクスポートを使用している場合に特に注意が必要なのが、日付の扱いです。たとえば以下のように `CURRENT_DATE()` を直接クエリに含めると、毎日違うクエリ文字列と判定されてキャッシュがヒットしません。

```sql
-- キャッシュが効かない例（毎回異なる日付が埋め込まれるため）
SELECT
  event_date,
  COUNT(*) AS session_count
FROM
  `project.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY
  event_date
```

この場合、`_TABLE_SUFFIX` の値が毎日変化するため、クエリ文字列が変わり、キャッシュは使われません。固定の日付文字列を用いるか、後述のマテリアライズドビューなどの代替手段を検討してください。

---

## GA4データを活用するクエリでのキャッシュ設計

GA4のBigQueryエクスポートデータを使ったレポーティングでは、クエリの書き方次第でキャッシュの効き方が大きく変わります。以下に、セッション数と流入元を集計するクエリの例を示します。

```sql
-- キャッシュを意識した集計例（対象期間を固定文字列で指定）
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `project.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date
```

このように対象期間を固定の文字列リテラルで指定すると、翌日以降に同じクエリを再実行してもクエリ文字列が変わらないため、テーブルのデータが更新されていない期間のデータについてはキャッシュから結果を取得できます。

:::message
`ga_session_id` は `event_params` の中にネストされているため、直接 `event_params.ga_session_id` のように参照することはできません。`UNNEST(event_params)` を使って展開し、`key = 'ga_session_id'` で絞り込む必要があります。
:::

日次バッチで過去月分のサマリーを再集計するような処理では、対象期間を固定することでキャッシュを活かしやすくなります。一方で「本日分」を含むクエリはどうしてもキャッシュが効きにくいため、日中の頻繁な再実行には注意が必要です。

---

## キャッシュを最大限活用するための運用ポイント

クエリキャッシュを日々の運用に組み込むには、以下のような工夫が有効です。

**1. クエリをテンプレート化して文字列の揺れを防ぐ**

チームで同じレポートを参照する場合、各自がクエリを書き直してしまうとキャッシュがヒットしません。共有のクエリをスニペットや保存済みクエリとして管理し、コピーして使う運用にすることで、文字列の完全一致を保てます。

**2. スケジュールクエリと組み合わせる**

BigQueryのスケジュールクエリ機能を使い、固定のクエリを定期実行してキャッシュを温めておく方法もあります。たとえば毎朝6時に前日分のサマリーを集計しておけば、日中にLooker StudioやConnected Sheetsから同じクエリを参照したときにキャッシュから結果を返せます。

**3. マテリアライズドビューを活用する**

頻繁に参照される集計クエリはマテリアライズドビューとして定義することを検討してください。マテリアライズドビューは結果を実テーブルとして保持し、元データが更新されたときのみ差分更新が行われるため、キャッシュより確実に再スキャンコストを削減できます。

**4. Information Schemaでコストを定期的に確認する**

クエリキャッシュが実際にどれくらい活用されているかは、`INFORMATION_SCHEMA.JOBS` を使ってモニタリングできます。

```sql
-- キャッシュヒット状況を確認するクエリ
SELECT
  cache_hit,
  COUNT(*) AS job_count,
  SUM(total_bytes_processed) AS total_bytes
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
GROUP BY
  cache_hit
```

`cache_hit = TRUE` の割合が高いほど、コスト効率よく運用できているサインです。逆にキャッシュヒット率が低い場合は、クエリ設計や実行パターンの見直しが有効かもしれません。

---

## まとめ

BigQueryのクエリキャッシュは、正しく理解して活用することでオンデマンドクエリのコストを大幅に削減できる機能です。今回の要点を整理します。

- キャッシュは**クエリ文字列の完全一致**と**参照テーブルの未変更**が条件
- `CURRENT_DATE()` や `RAND()` などの非決定論的関数を含むとキャッシュは無効
- GA4のBigQueryエクスポートでは、`ga_session_id` の取得に `UNNEST(event_params)` を使い、流入元には `collected_traffic_source.manual_medium / manual_source` を参照する
- 対象期間を固定文字列で指定することでキャッシュが効きやすくなる
- `INFORMATION_SCHEMA.JOBS` でキャッシュヒット率を定期的に確認する

クエリを少し書き方に気をつけるだけで、毎月のBigQuery利用料を抑えられる可能性があります。まずは自社でよく実行するクエリのキャッシュヒット状況を確認するところから始めてみてはいかがでしょうか。

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
