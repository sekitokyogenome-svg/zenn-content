

```markdown
---
title: "Looker Studioが重い・遅い問題をBigQuery化で解決した話【表示速度10倍改善】"
emoji: "⚡"
type: "idea"
topics: ["LookerStudio", "BigQuery", "GA4", "データ分析", "EC"]
published: false
---

## 「レポート開くのに毎回30秒以上かかるんですが…」

EC運営をしている方なら、一度はこの苦痛を味わったことがあるのではないでしょうか。

Looker Studio（旧データポータル）でGA4のレポートを作ったはいいものの、ページを開くたびにグルグルと読み込みが回り続ける。フィルタを切り替えるとまた30秒。日付範囲を変えるとさらに30秒。

チームミーティングで画面共有しながら「ちょっと待ってくださいね…」と言い続ける気まずさ。あれ、本当につらいですよね。

この記事では、月商3,000万円規模のアパレルECサイトで実際にこの問題を解決した事例をお伝えします。

## なぜLooker Studio × GA4ネイティブ接続は遅いのか

Looker StudioからGA4に直接接続（ネイティブコネクタ）している場合、**レポートを開くたびにGA4のAPIを叩いてデータを取得**しています。

これが遅くなる主な原因は3つです。

| 原因 | 影響度 |
|------|--------|
| GA4 APIのレスポンス自体が遅い | ★★★ |
| ページ内のグラフ数が多いほどAPI呼び出しが増える | ★★★ |
| 複雑なフィルタや計算フィールドがAPI処理を重くする | ★★ |

特にEC系サイトは、商品カテゴリ別・流入元別・デバイス別など**切り口が多い**ため、1つのレポートに10個以上のグラフを並べがちです。これが致命的に遅くなる原因です。

## ビフォー：GA4ネイティブ接続の状態

今回のクライアント（アパレルEC・月間PV約80万）の状況はこうでした。

- **レポート初回表示：35〜45秒**
- **フィルタ切替：20〜30秒**
- **日付範囲変更：25〜40秒**
- レポートページ数：5ページ
- 1ページあたりのグラフ数：8〜12個

毎朝の数字確認に使うレポートなのに、開くだけでストレス。結果として「誰もレポートを見なくなる」という本末転倒な状態に陥っていました。

## アフター：BigQuery中間テーブル化後の状態

GA4 → BigQueryエクスポートを有効にし、BigQuery上で**集計済みの中間テーブル**を作成。Looker StudioからはBigQueryコネクタで接続する構成に変更しました。

- **レポート初回表示：3〜5秒** 🎉
- **フィルタ切替：1〜2秒**
- **日付範囲変更：2〜3秒**
- レポートページ数：5ページ（変更なし）
- 1ページあたりのグラフ数：8〜12個（変更なし）

**表示速度は約10倍改善**しました。レポートの中身は一切変えていません。データソースを変えただけです。

## 具体的にやったこと：3ステップ

### ステップ1：GA4 → BigQueryエクスポートを有効化

GA4の管理画面からBigQueryリンクを設定します。これは無料（BigQueryの無料枠内で収まるケースが多い）で、設定した翌日からデータが蓄積されます。

### ステップ2：日次の集計テーブルをスケジュールクエリで作成

GA4の生データ（イベント単位）をそのままLooker Studioに繋いでも、まだ遅いです。**あらかじめ日別・チャネル別・デバイス別に集計したテーブル**を作るのがポイントです。

```sql
-- 日次集計テーブルの作成例
CREATE OR REPLACE TABLE `project.dataset.daily_summary` AS
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  device.category AS device_category,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date, medium, source, device_category
```

このクエリをBigQueryの**スケジュールクエリ**で毎朝自動実行するよう設定します。

### ステップ3：Looker StudioのデータソースをBigQueryに切替

Looker Studioのデータソースを、GA4ネイティブコネクタからBigQueryコネクタに変更します。接続先は、ステップ2で作った集計テーブルです。

:::message
集計テーブルは数万行程度まで圧縮されるため、Looker Studioの処理が劇的に軽くなります。GA4の生データは数千万行〜数億行あることを考えると、この差は歴然です。
:::

## コスト面はどうだったか

気になるBigQueryのコストですが、今回のケースでは以下の通りでした。

| 項目 | 月額コスト |
|------|-----------|
| BigQueryストレージ（GA4データ90日分） | 約$2〜3 |
| スケジュールクエリ実行（日次） | 約$1〜2 |
| Looker Studioからのクエリ | 約$0.5〜1 |
| **合計** | **約$4〜6（600〜900円程度）** |

月額1,000円以下で、チーム全員のレポート閲覧ストレスが解消されるなら、十分すぎる投資対効果です。

## この構成で得られた副次的なメリット

速度改善以外にも、嬉しい変化がありました。

- **レポートを毎朝見る習慣がチームに定着した**（見るのが苦じゃなくなった）
- **GA4 UIでは作れなかった独自指標**（LTV、リピート率など）をSQL側で自由に計算できるようになった
- **データの正確性が向上した**（GA4 UIのサンプリング問題を回避）

:::message alert
GA4ネイティブコネクタでは、データ量が多い場合にサンプリング（推定値）が適用されることがあります。BigQuery経由なら全数データで集計できるため、数字のブレがなくなります。
:::

## まとめ

Looker Studioが遅い問題の多くは、「GA4 APIに毎回問い合わせている」構造そのものに原因があります。BigQueryに集計済みテーブルを用意してデータソースを切り替えるだけで、レポートの体験は劇的に変わります。

「設定のやり方がわからない」「自社ECに合った集計テーブルの設計を相談したい」という方は、お気軽にご相談ください。

https://coconala.com/services/1791205

GA4×BigQuery×Looker Studioの構築を、御社のビジネスに合わせてサポートいたします。
```