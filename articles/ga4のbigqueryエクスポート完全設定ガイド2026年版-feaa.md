

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

## 「GA4の標準レポートだけでは限界…」と感じていませんか？

「GA4の探索レポートでセグメントを切ると、しょっちゅうサンプリングがかかって正確な数字が出ない」
「過去14ヶ月より前のデータを分析したいのに、もう消えていた」
「商品別×流入元別のLTVを出したいけど、GA4の画面では無理だった」

中小ECを運営していると、こうした壁にぶつかる瞬間がありますよね。これらの問題をすべて解決するのが **GA4 → BigQueryエクスポート** です。

本記事では、2026年最新のUI・仕様に基づいて、設定手順をゼロから解説します。

## BigQueryエクスポートで何が変わるのか

| 項目 | GA4標準レポート | BigQuery連携後 |
|------|----------------|----------------|
| サンプリング | かかる場合あり | **なし（生データ）** |
| データ保持期間 | 最大14ヶ月 | **無期限（自分で管理）** |
| クロス分析の自由度 | 探索レポートの範囲内 | **SQLで無制限** |
| 外部データとの結合 | 不可 | **CRMや広告データと結合可能** |

月間100万PV程度のECサイトなら、BigQueryの無料枠（毎月10GBストレージ＋1TBクエリ）でほぼ収まります。

## 前提条件の確認

:::message
以下の3つが揃っていることを確認してください。
- Google Cloud プロジェクトが作成済み（課金アカウント紐付け済み）
- GA4プロパティの **編集者** 以上の権限を持っている
- Google Cloud プロジェクトで **BigQuery API** が有効化されている
:::

## Step 1：Google Cloud プロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを選択（なければ新規作成）
3. 左メニュー「APIとサービス」→「ライブラリ」→ **BigQuery API** を検索して有効化
4. 「IAMと管理」→ GA4が使うサービスアカウントに **BigQuery編集者** ロールが付与されていることを確認

## Step 2：GA4管理画面からBigQueryリンクを作成

1. GA4管理画面 →「プロパティ設定」→「製品リンク」→ **BigQueryのリンク** を選択
2. 「リンク」をクリック
3. 連携するGoogle Cloudプロジェクトを選択
4. データロケーションを選択（日本なら **asia-northeast1（東京）** を推奨）
5. エクスポートタイプを選択：

| タイプ | 特徴 | 推奨用途 |
|--------|------|----------|
| **毎日** | 1日1回、前日分をエクスポート | コスト重視・日次レポート |
| **ストリーミング** | ほぼリアルタイムでエクスポート | リアルタイム在庫連動・即時分析 |

:::message alert
ストリーミングエクスポートは追加コストが発生します。中小ECではまず **毎日エクスポートのみ** で始めるのがおすすめです。後からストリーミングを追加することもできます。
:::

6. 「送信」でリンク完了

設定後、**翌日から** `analytics_<プロパティID>` というデータセットがBigQuery上に作成され、`events_YYYYMMDD` テーブルにデータが蓄積されます。

## Step 3：データが正しくエクスポートされたか確認する

リンク設定の翌日以降、以下のSQLをBigQueryで実行してみましょう。

```sql
-- エクスポート確認：直近のイベント件数とイベント名の内訳を取得
SELECT
  event_name,
  COUNT(*) AS event_count
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

`page_view` や `session_start`、`purchase` などのイベントが表示されれば成功です。

## Step 4：セッション単位で確認してみる

GA4のBigQueryデータはイベント単位（1行＝1イベント）で格納されます。セッション単位の集計には `ga_session_id` を使います。

```sql
-- セッション数とユーザー数を日別に集計
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  date
ORDER BY
  date;
```

:::message
`CONCAT(user_pseudo_id, ga_session_id)` でセッションを一意に識別するのがGA4 BigQuery分析の基本パターンです。このパターンは今後の分析でも頻出するので覚えておきましょう。
:::

## 設定後に押さえておきたいコスト管理のコツ

1. **パーティション分割テーブルを活用する**：`_TABLE_SUFFIX` で日付を絞ることで、スキャン量を大幅に削減できる
2. **必要なカラムだけSELECTする**：`SELECT *` は避け、使うフィールドだけ指定する
3. **BigQuery Sandboxで始める**：クレジットカード登録なしでも1TBクエリ/月は無料で使える

## まとめ

- GA4 → BigQuery連携は **管理画面から数クリック** で設定できる
- 中小ECなら **毎日エクスポート** から始めれば十分
- 生データが手元にあれば、サンプリングなしの正確な分析が可能に
- セッション識別は `CONCAT(user_pseudo_id, ga_session_id)` が基本

設定は簡単ですが、「設定した後にどんなSQLを書けばいいのか分からない」「自社ECに合った分析設計をしたい」というお声もよくいただきます。

---

:::message
📊 **GA4×BigQuery分析の設計・SQL作成を代行します**
「エクスポートはできたけど、ここからどう活用すればいいか分からない」という方へ。GA4のBigQueryデータを使ったEC向け分析ダッシュボードの構築や、LTV分析・チャネル評価のSQL作成をサポートしています。
👉 [ココナラでサービスを見る](https://coconala.com/services/1791205)
:::
```