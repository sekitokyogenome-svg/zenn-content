

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の管理画面だけでは限界がある」と感じていませんか？

「セグメントを細かく切りたいのに、GA4の探索レポートが重くて動かない」
「14ヶ月を超えた過去データが消えてしまい、前年比較ができない」
「広告費の最適化のために、ローデータを自由に分析したい」

中小ECの運営者やWEBマーケターの方から、こうした声をよく聞きます。これらの課題を根本的に解決するのが **GA4 → BigQuery エクスポート** です。

この記事では、2026年最新のUI・仕様に基づいて、設定手順をゼロから解説します。

## BigQueryエクスポートで何が変わるのか

| 項目 | GA4管理画面のみ | BigQuery連携後 |
|---|---|---|
| データ保持期間 | 最大14ヶ月 | **無期限** |
| 分析の自由度 | 探索レポートの制約あり | SQLで自在に集計 |
| サンプリング | 大量データで発生 | **一切なし** |
| 他データとの統合 | 困難 | CRMや広告データと結合可能 |

無料枠（毎月10GBストレージ＋1TBクエリ）で中小ECなら十分運用できるのもポイントです。

## 前提条件の確認

:::message
エクスポート設定には以下の権限が必要です。事前に確認しておきましょう。
:::

- **GA4プロパティ**: 編集者以上の権限
- **Google Cloudプロジェクト**: オーナーまたは BigQuery 管理者ロール
- **課金の有効化**: Google Cloudプロジェクトで請求先アカウントが紐付いていること

## 手順①：Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 新規プロジェクトを作成（既存プロジェクトでもOK）
3. 左メニュー「APIとサービス」→「BigQuery API」が有効になっていることを確認
4. 「お支払い」から請求先アカウントを紐付ける

:::message alert
請求先アカウントが未設定だと、GA4側の連携メニューにプロジェクトが表示されません。無料枠内で収まる場合でも設定は必須です。
:::

## 手順②：GA4からBigQueryリンクを作成

1. GA4管理画面 → 「管理」→「プロダクトリンク」→「BigQueryのリンク」
2. 「リンク」をクリック
3. Google Cloudプロジェクトを選択
4. データのロケーションを **「asia-northeast1（東京）」** に設定
5. エクスポートタイプを選択：

| タイプ | 内容 | 推奨 |
|---|---|---|
| 毎日 | 前日分をまとめてエクスポート | ✅ まず有効に |
| ストリーミング | リアルタイムにエクスポート | コスト増のため慎重に |

6. 「送信」をクリックして完了

**設定から24〜48時間後** に、BigQuery上に `analytics_<プロパティID>` というデータセットが自動作成されます。

## 手順③：データが届いているか確認するSQL

設定翌日以降、BigQueryコンソールで以下のSQLを実行してください。

```sql
SELECT
  event_date,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY))
GROUP BY
  event_date
ORDER BY
  event_date DESC;
```

:::message
`your-project` と `XXXXXXXXX` は、ご自身のプロジェクトIDとGA4プロパティIDに置き換えてください。
:::

結果が返ってくれば、エクスポートは正常に動作しています。

## 手順④：セッション単位で確認してみる

GA4のBigQueryデータはイベント単位で格納されています。セッション単位で集計するには、以下のようにセッションIDを組み立てます。

```sql
SELECT
  event_date,
  CONCAT(
    user_pseudo_id,
    CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )
  ) AS session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS events_in_session
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date, session_id, medium, source
ORDER BY
  events_in_session DESC
LIMIT 20;
```

このクエリで、昨日のセッションごとの流入元とイベント数を確認できます。ここまで動けば、BigQuery活用の土台は完成です。

## よくあるトラブルと対処法

| 症状 | 原因 | 対処 |
|---|---|---|
| データセットが作成されない | 請求先アカウント未設定 | Cloud Consoleで紐付け |
| テーブルが空 | 設定直後（24〜48h待ち） | 翌々日まで待つ |
| `events_intraday_*` しかない | 日次エクスポートの処理待ち | 翌朝に `events_*` が生成される |
| ロケーションエラー | プロジェクトとデータセットのリージョン不一致 | 東京リージョンに統一 |

## コスト目安（中小ECの場合）

月間10万セッション規模のECサイトであれば、日次エクスポートのみの場合：

- **ストレージ**: 約2〜5GB/月 → 無料枠内
- **クエリ**: 週2〜3回の分析なら → 無料枠内

月額0円で運用できているケースがほとんどです。ストリーミングを追加する場合のみ、月数百円〜数千円のコストが発生します。

## まとめ

1. Google Cloudプロジェクトを用意し、課金を有効化
2. GA4管理画面からBigQueryリンクを作成（ロケーションは東京）
3. 翌日以降にSQLで疎通確認
4. セッション単位の集計でデータ構造を把握

この4ステップで、GA4データの分析基盤が整います。次のステップとして「購入経路分析」や「LTV計算」など、ECの売上に直結する分析に進んでいきましょう。

---

:::message
「BigQueryの設定はできたけど、SQLを書いて分析するところまで手が回らない…」という方へ。GA4×BigQueryの初期設定から分析ダッシュボード構築まで、まるごとサポートしています。
👉 [ココナラでGA4・BigQuery分析サポートを見る](https://coconala.com/services/1791205)
:::
```