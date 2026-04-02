

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

「GA4の標準レポートだけだと、細かい分析ができない…」
「BigQueryにエクスポートしたいけど、設定が難しそうで手が出ない…」

中小ECを運営していると、GA4の探索レポートではサンプリングがかかったり、データ保持期間の制限（最大14ヶ月）に悩まされたりしますよね。BigQueryにエクスポートすれば、**生データを無期限で保持**でき、SQLで自由自在に分析できます。

この記事では、2026年最新のGA4 → BigQueryエクスポート設定を、スクリーンショットの代わりにステップごとの手順で丁寧に解説します。

## BigQueryエクスポートで何が変わるのか

| 項目 | GA4標準 | BigQuery連携後 |
|---|---|---|
| データ保持期間 | 最大14ヶ月 | 無期限 |
| サンプリング | 発生する場合あり | なし（生データ） |
| 分析の自由度 | 探索レポートの範囲内 | SQLで無制限 |
| 他データとの結合 | 不可 | CRMや広告データと結合可能 |

## 事前準備

### 1. Google Cloudプロジェクトの作成

- [Google Cloud Console](https://console.cloud.google.com/) にアクセス
- 新規プロジェクトを作成（既存プロジェクトでもOK）
- **BigQuery API** が有効になっていることを確認

### 2. 課金アカウントの設定

BigQueryには無料枠（毎月10GBのストレージ、1TBのクエリ）がありますが、課金アカウントの紐付けは必須です。

:::message
中小ECサイト（月間PV 10万〜50万程度）であれば、BigQueryの費用は**月額数百円〜数千円程度**に収まるケースがほとんどです。無料枠内で済むことも多いです。
:::

### 3. 権限の確認

GA4側とGoogle Cloud側の両方で適切な権限が必要です。

- **GA4**: 「編集者」以上の権限
- **Google Cloud**: 「BigQuery管理者」＋「プロジェクト編集者」

## BigQueryエクスポートの設定手順

### ステップ1: GA4管理画面からリンクを作成

1. GA4の管理画面 → **プロパティ設定** → **データの収集と修正** → **BigQueryのリンク**
2. 「リンク」をクリック
3. Google Cloudプロジェクトを選択

### ステップ2: エクスポート設定の選択

ここが最も重要なポイントです。

| エクスポート種別 | 更新頻度 | 用途 |
|---|---|---|
| **毎日** | 1日1回（翌日反映） | コスト重視・日次レポート |
| **ストリーミング** | ほぼリアルタイム | リアルタイム分析が必要な場合 |

:::message alert
ストリーミングエクスポートは追加コストが発生します。まずは「毎日」のみで始めて、必要に応じてストリーミングを追加するのがおすすめです。
:::

### ステップ3: データロケーションの選択

データロケーションは**後から変更できません**。日本のEC事業者であれば `asia-northeast1`（東京）を選択しましょう。

### ステップ4: リンクの確認と送信

設定内容を確認して「送信」をクリックすれば完了です。翌日からデータが蓄積され始めます。

## エクスポートされたデータを確認するSQL

設定後、翌日以降にBigQueryコンソールで以下のSQLを実行してみましょう。

```sql
-- エクスポートされたイベント数とユーザー数を確認
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name
ORDER BY
  event_count DESC
LIMIT 20;
```

`your-project` と `analytics_XXXXXXXXX` は、それぞれ自分のプロジェクトIDとGA4プロパティIDに置き換えてください。

次に、セッション単位でデータが取れていることを確認します。

```sql
-- セッションIDの取得確認
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  event_name,
  TIMESTAMP_MICROS(event_timestamp) AS event_time
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
  AND event_name = 'session_start'
ORDER BY
  event_time DESC
LIMIT 10;
```

このクエリが正常に結果を返せば、BigQueryエクスポートは正しく動作しています。

## 設定後にやっておきたい3つのこと

### 1. テーブルの有効期限を設定しない

デフォルトではテーブルの有効期限は無期限ですが、データセットレベルで有効期限が設定されていないか確認しましょう。せっかくの生データが自動削除されてしまいます。

### 2. コストアラートの設定

Google Cloudの「予算とアラート」で月額上限のアラートを設定しておきましょう。想定外のコスト発生を防げます。

### 3. 初回データ確認を忘れずに

リンク設定から48時間以内にデータが表示されない場合は、権限設定やプロジェクトの課金状態を再確認してください。

:::message
BigQueryエクスポートは**過去に遡ってデータを取得できません**。設定した日以降のデータのみが蓄積されるため、分析を始めたいと思ったら、まず先にエクスポート設定だけでも済ませておくことをおすすめします。
:::

## まとめ

GA4 → BigQueryエクスポートの設定自体は、手順通りに進めれば15分程度で完了します。ポイントをおさらいします。

- Google Cloudプロジェクトと課金アカウントを事前準備
- まずは「毎日エクスポート」から始める
- データロケーションは `asia-northeast1`（東京）を選択
- **設定日以降のデータしか貯まらないので、早めの設定が吉**

BigQueryにデータが蓄積されれば、ユーザー行動の深掘り分析、LTV計算、アトリビューション分析など、GA4標準では難しかった分析が自在にできるようになります。

---

「BigQueryの設定はできたけど、SQLが書けない」「自社ECに合った分析クエリが欲しい」という方は、GA4×BigQuery分析の設計からSQL作成まで対応しています。お気軽にご相談ください。

👉 [ココナラでGA4・BigQuery分析サービスを見る](https://coconala.com/services/1791205)
```