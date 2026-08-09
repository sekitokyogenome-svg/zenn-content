---
title: "小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略"
emoji: "🆓"
type: "idea"
topics: ["bigquery","ec","googlecloud","cost","sql"]
published: false
book_only: true
---

## はじめに

「BigQueryを導入したいけれど、コストが心配で踏み出せない」——小規模EC事業者のご担当者や、クライアントにデータ分析基盤を提案するコンサルタントの方から、こうしたご相談をよくいただきます。

BigQueryはGoogleが提供するクラウドデータウェアハウスで、GA4のデータをSQLで柔軟に分析できる強力なサービスです。しかし、使い方を誤ると予想外の費用が発生するため、「とりあえず触ってみよう」という感覚での導入はリスクを伴います。

一方で、正しく設計さえすれば、月間の処理データ量が一定規模以内に収まる小規模ECサイトであれば、BigQueryの無料枠だけで十分に運用できるケースは少なくありません。BigQueryには毎月1TBの無料クエリ枠と10GBの無料ストレージ枠が用意されており、サイトの規模や分析頻度によってはコストをほぼゼロに抑えることが可能です。

本記事では、小規模EC事業者がBigQueryを無料枠内で持続的に運用するための設計戦略を、具体的なSQL例を交えながら解説します。BigQueryを初めて検討している方にも理解いただけるよう、できるだけ平易な表現でお伝えします。

## BigQueryの無料枠を正確に把握する

まず前提として、BigQueryの料金体系を整理しておきましょう。BigQueryのコストは大きく「クエリ処理コスト」と「ストレージコスト」の2種類に分けられます。

**クエリ処理コスト**は、SQLを実行したときにスキャンしたデータ量に応じて発生します。無料枠は毎月1TB（テラバイト）で、超過分は1TBあたり約6.25ドル（料金は変動する場合があります）となっています。

**ストレージコスト**は、BigQuery上に保存しているデータの容量に対して発生します。アクティブストレージの無料枠は10GB、90日間更新のないデータは長期保存ストレージとして自動的に割引が適用されます。

GA4のBigQueryエクスポートを利用している場合、1日分のイベントデータは一般的な小規模ECサイトで数十MB程度に収まることが多く、ストレージだけを見れば無料枠を超えるまでにかなりの余裕があります。問題になるのは主にクエリ処理コストです。「クエリを実行するたびに大量のデータをスキャンしてしまう」という設計上の問題を解消することが、無料枠内での運用継続の鍵となります。

## クエリ設計でスキャン量を最小化する

BigQueryでコストを抑える最も効果的なアプローチは、SQLクエリのスキャン量を減らすことです。以下のポイントを意識するだけで、クエリコストを大幅に削減できます。

**日付パーティションを必ず指定する**

GA4のBigQueryエクスポートテーブルは`events_YYYYMMDD`という日付シャーディング形式で保存されています。ワイルドカード（`events_*`）を使う場合は、`_TABLE_SUFFIX`で期間を絞り込まないと全期間のデータをスキャンしてしまいます。

```sql
-- 悪い例：全期間スキャンが走る
SELECT *
FROM `your_project.analytics_XXXXXXX.events_*`
WHERE event_name = 'purchase';

-- 良い例：期間を絞り込む
SELECT *
FROM `your_project.analytics_XXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase';
```

**SELECTに必要なカラムのみを指定する**

`SELECT *`は全カラムをスキャンするため、コストが跳ね上がります。必要なフィールドだけを指定する習慣をつけましょう。

**プレビュー機能でスキャン量を確認する**

BigQueryのコンソールでクエリを実行する前に、右上に表示される「このクエリは約〇〇MBを処理します」という表示を必ず確認してください。実行前にコストを把握できるため、想定外の課金を防げます。

## GA4データを活用する際のSQL設計パターン

GA4のBigQueryエクスポートデータは、イベントごとにネストされた構造を持っているため、通常のテーブルとは異なる扱いが必要です。ここでは、小規模ECサイトでよく使う分析クエリのパターンをご紹介します。

**購入セッションの流入元を集計する例**

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNT(*) AS purchase_count
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchase_count DESC;
```

このクエリでは、`ga_session_id`をネストされた`event_params`配列から`UNNEST`を使って取り出しています。GA4のBigQueryエクスポートでは、`ga_session_id`はイベントパラメータとして格納されているため、直接カラムとして参照することはできません。また、流入元の情報は`collected_traffic_source`フィールドの`manual_medium`と`manual_source`を参照します。

:::message
`UNNEST(event_params)`を使わずに`ga_session_id`を参照しようとするとエラーになります。GA4のBigQueryデータ構造はRECORD型のネストが多用されているため、まずデータスキーマを確認してからクエリを組み立てることをお勧めします。
:::

## ストレージコストを抑えるテーブル管理の工夫

クエリコストだけでなく、保存するデータ量を適切にコントロールすることも重要です。

**定期的に参照するサマリーテーブルを作成する**

毎回生データをスキャンするのではなく、週次・月次で集計した結果テーブルを作成しておくことで、レポート確認時のスキャン量を大幅に減らせます。集計済みのサマリーテーブルはデータ量が小さくなるため、参照コストもほぼゼロになります。

```sql
-- 月次売上サマリーを集計テーブルとして保存する例
CREATE OR REPLACE TABLE `your_project.ec_summary.monthly_revenue_202506` AS
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT ep.value.double_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source;
```

**古いデータのアーカイブ方針を決める**

分析に使わなくなった2年以上前のデータは、必要に応じてGCS（Google Cloud Storage）にエクスポートしてBigQueryから削除するか、そのままにして長期保存ストレージの割引を活用するかを検討しましょう。長期保存ストレージは通常の半額程度の料金になるため、削除しなくても一定のコスト最適化が見込めます。

**Looker Studioとの連携はキャッシュを活用する**

Looker Studio（旧データポータル）からBigQueryにクエリを発行する際も、スキャン量に応じたコストが発生します。Looker Studioのデータソース設定で「キャッシュを有効にする」オプションをオンにしておくと、同じクエリ結果を一定時間キャッシュから返すようになり、クエリの実行頻度を下げられます。

## 無料枠を超えそうなときのアラート設定

運用が軌道に乗ってきたら、コスト上限アラートを設定しておくことをお勧めします。Google Cloudの請求アラートを使えば、月間の費用が一定額を超えた段階でメール通知を受け取れます。

また、BigQueryには「カスタムクォータ」の設定機能があり、プロジェクト全体またはユーザーごとに1日あたりのスキャン量に上限を設定することができます。たとえば1日あたり200GBの上限を設けておけば、意図しない大量スキャンが発生しても自動的にクエリが停止されます。

:::message
カスタムクォータはGoogleCloudコンソールの「BigQuery」→「管理」→「クォータ」から設定できます。無料枠の範囲内で運用したい場合、月1TBの範囲で逆算すると1日あたり約33GBが目安になります。
:::

## まとめ

小規模EC事業者がBigQueryを無料枠内で運用し続けるためのポイントを整理します。

1. **クエリには必ず日付範囲を指定する** — `_TABLE_SUFFIX`を使って対象テーブルを絞り込み、不必要なスキャンを防ぐ
2. **SELECT \* を避け、必要なカラムだけを指定する** — スキャン量を実質的に削減できる
3. **GA4データはUNNESTを使って正しく参照する** — `ga_session_id`はイベントパラメータから取得し、流入元は`collected_traffic_source`を使う
4. **定期集計テーブルを活用する** — 生データへのアクセス頻度を下げることでクエリコストを抑える
5. **コストアラートとクォータを設定する** — 意図しない課金を未然に防ぐ安全網として機能する

BigQueryは正しく設計することで、小規模ECサイトの分析基盤として低コストで安定運用できるサービスです。まずは分析頻度の高いレポートから設計を見直し、スキャン量の可視化を習慣づけることから始めてみてください。データ活用が進むにつれて、次のステップとして有料機能の検討も自然と見えてくるでしょう。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】](https://zenn.dev/web_benriya/articles/gemini-bigquery-pricing-complete-guide)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
