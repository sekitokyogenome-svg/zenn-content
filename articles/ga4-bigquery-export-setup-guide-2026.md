---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "📊"
type: "tech"
topics: ["googleanalytics", "bigquery", "googlecloud"]
published: false
---

## はじめに

「GA4の探索レポートでデータを深掘りしたいのに、サンプリングがかかって正確な数値が出ない」
「14か月より前のデータを分析したいが、GA4の管理画面では保持期間の壁がある」

こうした課題を抱えるマーケターやアナリストは多いのではないでしょうか。

GA4単体の限界を突破する最も有効な手段が、**BigQueryエクスポート**です。
本記事では、GCPプロジェクトの準備からエクスポート設定、コスト感、よくあるハマりどころまで一通り解説します。

## GA4単体の限界

GA4だけで運用していると、以下の制約にぶつかります。

| 制約 | 内容 |
|------|------|
| サンプリング | 探索レポートで大量データを扱うと自動でサンプリングされる |
| データ保持期間 | イベントデータの保持は最大14か月 |
| 外部データとの結合 | CRMや広告コストデータをGA4内で直接JOINできない |

BigQueryにエクスポートすれば、サンプリングなしの生データを無期限で保持でき、SQLで自由に外部データと結合できます。

## 事前準備：GCPプロジェクトの作成

BigQueryエクスポートを有効にするには、Google Cloud Platform（GCP）のプロジェクトが必要です。

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 「プロジェクトを作成」をクリック
3. プロジェクト名を入力し、組織・請求先アカウントを設定
4. BigQuery APIが有効になっていることを確認

:::message
GCPの請求先アカウント（Billing Account）が未設定だとエクスポートが開始されません。無料トライアル中でも請求先の紐付けは必要です。
:::

## BigQueryエクスポートの設定手順

### 1. GA4管理画面を開く

GA4の管理画面から **「プロダクトリンク」>「BigQueryのリンク」** を選択します。

### 2. GCPプロジェクトを選択

リンク設定画面で、先ほど作成したGCPプロジェクトを選びます。

### 3. データのロケーションを設定

データセットのロケーションは **`asia-northeast1`（東京）** を選択してください。

:::message alert
ロケーションは後から変更できません。日本国内のユーザーを対象とするサイトであれば `asia-northeast1` を選んでおくのが無難です。USリージョンを選ぶとクエリのレイテンシやデータ主権の観点で問題になることがあります。
:::

### 4. エクスポート頻度を選択

「毎日」または「ストリーミング」のいずれか（または両方）を選びます。

### 5. イベントの選択

エクスポート対象のイベントを選択します。特別な理由がなければ「すべてのイベント」を推奨します。

### 6. リンクを作成

設定を確認し「送信」をクリックすれば完了です。

## エクスポート方式の比較：日次 vs ストリーミング

| 項目 | 日次（Daily） | ストリーミング（Streaming） |
|------|---------------|---------------------------|
| データ反映 | 翌日に前日分が確定テーブルとして作成 | 数分以内にリアルタイム反映 |
| テーブル名 | `events_YYYYMMDD` | `events_intraday_YYYYMMDD` |
| 追加コスト | なし（BigQueryのストレージ費用のみ） | BigQuery Storage Write API の料金が発生 |
| 主な用途 | 日次レポート・定期分析 | リアルタイムダッシュボード・異常検知 |

:::message
まずは日次エクスポートだけで始めるのがコストを抑えるコツです。リアルタイム分析の要件が出てきた段階でストリーミングを追加しましょう。
:::

## エクスポートされるデータの構造

BigQueryに作成されるテーブルは `events_YYYYMMDD` という命名規則です。

各行が1つの**イベント**に対応し、パラメータはネスト（RECORD型）で格納されます。

主なカラム構成は以下の通りです。

| カラム名 | 型 | 内容 |
|----------|-----|------|
| `event_date` | STRING | イベント発生日（YYYYMMDD形式） |
| `event_name` | STRING | イベント名（`page_view`, `purchase` など） |
| `event_params` | RECORD（繰り返し） | イベントパラメータのキー・値ペア |
| `user_pseudo_id` | STRING | Cookieベースのユーザー識別子 |
| `collected_traffic_source` | RECORD | 流入元情報（medium, source, campaign など） |
| `device` | RECORD | デバイス情報 |
| `geo` | RECORD | 地域情報 |

### セッションIDを取得するクエリ例

`ga_session_id` は `event_params` 内にネストされているため、`UNNEST` で展開して取得します。

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  event_name,
  event_timestamp
FROM
  `project_id.analytics_XXXXXXX.events_20260328`
WHERE
  event_name = 'page_view'
LIMIT 100
```

### 流入元（メディア）を取得するクエリ例

GA4のBigQueryエクスポートでは、流入元情報は `collected_traffic_source` カラムに格納されます。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `project_id.analytics_XXXXXXX.events_20260328`
WHERE
  event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  event_count DESC
```

:::message alert
旧UAからの移行組がよく間違えるポイントとして、`traffic_source.medium` ではなく `collected_traffic_source.manual_medium` を使う点に注意してください。`traffic_source` はユーザーの初回流入元であり、セッション単位の流入元ではありません。
:::

## コストの目安

BigQueryの料金体系は主に**ストレージ**と**クエリ**の2軸です。

| 項目 | 料金（2026年3月時点の目安） |
|------|---------------------------|
| アクティブストレージ | $0.023/GB/月 |
| 長期ストレージ（90日以上未編集） | $0.016/GB/月 |
| オンデマンドクエリ | $6.25/TB（処理データ量課金） |
| 毎月の無料枠 | ストレージ 10GB + クエリ 1TB |

**月間10万PV程度のサイトの場合：**

- ストレージ：月数GB程度 → 無料枠内に収まることが多い
- クエリ：分析頻度によるが月数十GB程度 → 無料枠内で十分

月間100万PVを超える規模でも、月額数百円〜数千円程度に収まるケースがほとんどです。

:::message
コストが気になる場合は、BigQueryのスロット予約（定額制）やパーティション分割テーブルの活用で最適化できます。まずはオンデマンドで始めて利用状況を見るのがおすすめです。
:::

## よくあるハマりどころ

### 1. リージョンの選択ミス

前述の通り、ロケーションは後から変更できません。誤ったリージョンで作成してしまった場合は、リンクを削除して再設定する必要があります。既にエクスポートされたデータの移行も手動になるため、最初の設定を慎重に行いましょう。

### 2. エクスポートが実際に動いているか確認しない

設定後、BigQuery上にテーブルが作成されるまで**最大24時間**かかります。翌日にBigQueryコンソールを確認し、データセットとテーブルが存在するかチェックしてください。

```bash
# bqコマンドでテーブル一覧を確認
bq ls --max_results=10 project_id:analytics_XXXXXXX
```

### 3. intraday テーブルの扱い

ストリーミングエクスポートで作成される `events_intraday_YYYYMMDD` テーブルは、日次エクスポートの確定テーブルが作成されると**自動で削除**されます。intradayテーブルのデータを恒久的に保持したい場合は、別テーブルにコピーする仕組みが必要です。

### 4. エクスポート上限

1つのGA4プロパティからエクスポートできるイベント数には日次100万イベントの上限があります（GA4 360では上限が緩和）。大規模サイトでは上限に達していないか定期的に確認しましょう。

## まとめ

| ステップ | 内容 |
|----------|------|
| 1. GCPプロジェクト作成 | 請求先アカウントの紐付けを忘れずに |
| 2. GA4からBigQueryリンク | ロケーションは `asia-northeast1` を推奨 |
| 3. エクスポート頻度の選択 | まずは日次エクスポートから開始 |
| 4. データ確認 | 翌日にBigQueryでテーブル生成を確認 |
| 5. SQLで分析開始 | `UNNEST` でネスト構造を展開して活用 |

BigQueryへのエクスポートが完了したら、次はデータを効率的に管理・活用するためのレイヤー設計が重要です。以下の記事で、BigQuery上に3層構造（raw / staging / mart）を構築する方法を解説しています。

👉 [GA4 × BigQuery 3層データ設計ガイド](https://zenn.dev/web_benriya/articles/ga4-bigquery-3layer-design)

---

「設定がうまくいかない」「自社サイトに合った分析基盤を構築したい」といったお悩みがあれば、お気軽にご相談ください。GA4とBigQueryの連携から分析設計まで、実務経験をもとにサポートいたします。

👉 [ココナラでGA4・BigQuery設定サポートを見る](https://coconala.com/services/1791205)
