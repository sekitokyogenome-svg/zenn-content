

```markdown
---
title: "GA4のBigQueryエクスポート完全設定ガイド【2026年版】"
emoji: "🔗"
type: "tech"
topics: ["GA4", "BigQuery", "GoogleCloud", "analytics", "EC"]
published: false
---

「GA4の管理画面だけでは、本当に欲しいデータに辿り着けない…」

EC運営をしていると、こんな壁にぶつかりませんか？

- 購入までの行動を**セッション単位で細かく追いたい**のにGA4のレポートでは限界がある
- 14ヶ月を超えた過去データが探索レポートで使えなくなった
- チャネル別・商品別のLTVを自由にSQLで分析したい

これらの課題を一気に解決するのが **GA4 → BigQueryエクスポート** です。本記事では2026年最新のUI・仕様に対応した設定手順を、つまずきやすいポイントとともに解説します。

## 前提条件を確認しよう

設定を始める前に、以下を満たしているか確認してください。

| 項目 | 必要な条件 |
|------|-----------|
| GA4プロパティ | 設定済みであること |
| Google Cloudプロジェクト | 作成済み＆課金が有効 |
| 権限（GA4側） | プロパティの**編集者**以上 |
| 権限（GCP側） | プロジェクトの**BigQuery管理者** + **サービス利用コンシューマ** |

:::message
無料のGA4プロパティでもBigQueryエクスポートは利用可能です。GA4 360でなくても大丈夫です。
:::

## STEP 1：Google Cloudプロジェクトの準備

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 左上のプロジェクト選択 → 「新しいプロジェクト」で作成（既存でもOK）
3. **「APIとサービス」→「ライブラリ」**から **BigQuery API** が有効になっていることを確認
4. **ナビゲーションメニュー → 「お支払い」** から課金アカウントが紐づいていることを確認

:::message alert
課金が有効でないと、GA4側のリンク設定時にプロジェクトが候補に表示されません。クレジットカード登録だけで無料枠内なら費用はほぼかかりません。
:::

## STEP 2：GA4管理画面からBigQueryリンクを作成

1. GA4管理画面 →「プロパティ設定」→「製品リンク」→ **BigQueryのリンク** を選択
2. **「リンク」** をクリック
3. Google Cloudプロジェクトを選択
4. データロケーション（リージョン）を選択 → **東京なら `asia-northeast1`**
5. エクスポート頻度を選択

| エクスポート種別 | 特徴 | おすすめ用途 |
|---|---|---|
| **毎日** | 翌日にまとめてエクスポート（`events_YYYYMMDD`テーブル） | 日次レポート・定期分析 |
| **ストリーミング** | ほぼリアルタイムで `events_intraday_YYYYMMDD` に書き込み | リアルタイムダッシュボード |

:::message
中小ECならまず **「毎日」だけ** で十分です。ストリーミングはBigQueryのストレージ書き込み料金が追加でかかるため、必要になってから有効化しましょう。
:::

6. 「送信」をクリックしてリンク完了

設定後、**翌日から** `analytics_<プロパティID>` というデータセットがBigQueryに自動作成され、日次テーブルが蓄積され始めます。

## STEP 3：データが届いているか確認するSQL

設定翌日以降、BigQueryコンソールで以下のクエリを実行してみましょう。

```sql
-- エクスポートされたイベント数を日別に確認
SELECT
  event_date,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS sessions
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
GROUP BY
  event_date
ORDER BY
  event_date DESC;
```

`your-project` と `XXXXXXXXX`（GA4プロパティID）は自分の環境に置き換えてください。

ポイントは **セッションの識別方法** です。GA4のBigQueryエクスポートには `session_id` という単独カラムはなく、`user_pseudo_id` と `event_params` 内の `ga_session_id` を結合して一意なセッションIDを作ります。

## よくあるトラブルと対処法

### テーブルが作成されない
- 設定直後は反映まで**24〜48時間**かかる場合があります
- Google Cloudの課金が無効になっていないか再確認

### データロケーションを間違えた
- リンク作成後のロケーション変更は**不可**です
- 一度リンクを削除し、再作成する必要があります（削除前のデータは残ります）

### テーブルはあるがデータが少ない
- GA4のフィルタ設定で内部トラフィックを除外しすぎていないか確認
- BigQueryエクスポートはサンプリングされません。GA4管理画面のレポートと多少の差異が出るのは正常です

## 無料枠でどこまで使える？

BigQueryの無料枠（毎月）は以下のとおりです。

| リソース | 無料枠 |
|---|---|
| ストレージ | 10 GB |
| クエリ（オンデマンド） | 1 TiB |

月間10万PV程度のECサイトなら、**1ヶ月のデータ量は数百MB〜1GB前後** に収まることが多く、無料枠内で十分に運用できます。

## まとめ

1. Google Cloudで課金を有効化しBigQuery APIを確認
2. GA4管理画面からBigQueryリンクを作成（ロケーションは `asia-northeast1`）
3. 翌日以降にSQLでデータ到着を確認

ここまでできれば、GA4の生データをSQLで自由に分析する準備は完了です。次のステップとして「チャネル別CVR分析」や「商品別LTV算出」などに進むと、EC運営の意思決定が格段にデータドリブンになります。

---

:::message
「設定はできたけど、どんなSQLを書けばいいかわからない」「自社ECに合った分析軸を相談したい」という方へ──GA4×BigQueryの初期設定から分析設計まで、ココナラでサポートしています。
👉 [GA4・BigQuery分析のご相談はこちら](https://coconala.com/services/1791205)
:::
```