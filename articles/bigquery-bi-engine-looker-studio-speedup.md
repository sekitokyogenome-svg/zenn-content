---
title: "BigQueryのBI Engineを有効化してLooker Studioの表示速度を改善する"
emoji: "🚀"
type: "tech"
topics: ["bigquery","lookerstudio","googlecloud","sql","dataengineering"]
published: false
---

## はじめに

Looker Studio（旧データポータル）でダッシュボードを開くたびに、グラフが表示されるまで数十秒待つ——そのような状況にお困りではないでしょうか。GA4のデータをBigQueryにエクスポートして分析基盤を構築したものの、レポートの読み込みに時間がかかりすぎて、毎朝の数字確認がストレスになっているというお話はよく耳にします。

原因の多くは、Looker StudioがBigQueryにクエリを発行するたびに大量のデータを全件スキャンしていることにあります。GA4のイベントテーブルは日々データが蓄積されていくため、数ヶ月分のデータを扱うだけでも、1回のダッシュボード表示で何GBものスキャンが走ることは珍しくありません。

こうした課題に対して、Google Cloudが提供する**BI Engine**というインメモリキャッシュ機能が有効な手段となります。BI Engineを有効化することで、繰り返し発行されるクエリの結果をメモリ上にキャッシュし、Looker Studioの表示速度を大幅に改善できます。本記事では、BI Engineの仕組みから設定手順、費用の考え方まで、エンジニアでない方にも分かりやすく解説します。

## BI Engineとは何か

BI Engineは、BigQuery上に構築されたインメモリ分析アクセラレータです。通常のBigQueryクエリはディスク上のカラム型ストレージからデータを読み込みますが、BI Engineは頻繁にアクセスされるデータをメモリ（RAM）上に保持することで、クエリの応答時間を短縮します。

Looker StudioとBigQueryを接続している環境では、BI Engineが自動的にクエリを最適化します。ユーザーがダッシュボードのフィルターを操作したり、期間を変更したりするたびにBigQueryへクエリが飛ぶのですが、BI Engineがそのクエリを受け取り、キャッシュから応答できるものはキャッシュから返す、という動作をします。

料金はGB単位のメモリ予約に基づきます。東京リージョン（asia-northeast1）の場合、1GBあたり月額約0.02ドル（2025年時点）です。データ量に応じて1GBから始めて様子を見ることができます。クエリのスキャン料金とは別に発生しますが、頻繁にダッシュボードを開く運用であれば、コスト面でもメリットが出やすい構成です。

## BI Engineの設定手順

設定はGoogle Cloudコンソールから数分で完了します。以下の手順に沿って進めてください。

**手順1: プロジェクトとリージョンを確認する**

まず、BigQueryのデータセットが存在するリージョンを確認します。GA4のエクスポート先データセットは多くの場合 `analytics_XXXXXXXXX` という名前で、`asia-northeast1`（東京）または `US` に作成されています。BI Engineの予約はリージョン単位で行うため、データセットのリージョンに合わせる必要があります。

**手順2: BI Engineの予約を作成する**

1. Google Cloudコンソールにログインし、左上のナビゲーションメニューから「BigQuery」を選択します。
2. 左側のメニューで「BI Engine」を選択します（表示されない場合は「その他のプロダクト」から探してください）。
3. 「予約を作成」ボタンをクリックします。
4. リージョンを選択し、メモリサイズを設定します。まずは **1GB** から始めることをお勧めします。
5. 「作成」をクリックして完了です。

**手順3: Looker Studioからの動作確認**

設定完了後、Looker Studioで対象のダッシュボードを開き、グラフの表示速度が改善されているか確認します。BigQueryコンソールの「クエリ履歴」で確認すると、BI Engineによって処理されたクエリには「BI Engineが使用されました」という表示が出ます。

```bash
# gcloudコマンドで予約状況を確認する場合
gcloud alpha bq reservations list --location=asia-northeast1
```

## BI Engineが効きやすいクエリとそうでないクエリ

BI Engineはすべてのクエリに対して等しく効果を発揮するわけではありません。どのようなケースで恩恵を受けやすいか、理解しておくことが大切です。

**効果が出やすいケース**

- Looker Studioのダッシュボードで同じテーブルに繰り返しクエリが飛ぶ場合
- 集計・グループ化・フィルタリングが主体のBI系クエリ
- 比較的小〜中規模のデータセット（数百GB以下）へのアクセス

**効果が限定的になるケース**

- JOINが複雑に絡み合うクエリや、BI Engine非対応の関数を使用している場合
- 毎回まったく異なる条件でスキャンするアドホッククエリ
- 予約メモリサイズを大幅に超えるデータ量を毎回フルスキャンするケース

BI Engineが使用されたかどうかはクエリ実行後の「クエリ情報」パネルで確認できます。「BI Engine mode」の欄に `FULL` と表示されていれば完全にBI Engineで処理されており、`PARTIAL` の場合は一部のみ対応していることを示します。

## GA4データを使ったLooker Studio向けクエリの最適化例

BI Engineの効果を最大限引き出すためには、クエリ自体を最適化することも重要です。以下に、GA4のBigQueryエクスポートデータを用いたビュー定義の例を示します。このビューをLooker Studioのデータソースとして使用することで、ダッシュボードが発行するクエリをシンプルに保てます。

```sql
-- GA4セッションサマリービュー（Looker Studio用）
-- プロジェクトID・データセット名は環境に合わせて変更してください
CREATE OR REPLACE VIEW `your_project.analytics_XXXXXXXXX.v_session_summary` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS session_date,
  -- セッションIDはevent_paramsのUNNESTから取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  user_pseudo_id,
  -- 流入元はcollected_traffic_sourceから参照する
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  geo.country AS country,
  device.category AS device_category,
  event_name
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
;
```

このようにビューで期間や項目を絞り込んでおくことで、Looker StudioからのクエリがBI Engineのキャッシュに乗りやすくなります。毎回 `events_*` のワイルドカードテーブルを直接叩くよりも、ビュー経由でアクセスする構成のほうがキャッシュの有効活用につながります。

:::message
`ga_session_id` はイベントレベルのフィールドではなく `event_params` の中にネストされています。`UNNEST(event_params)` を経由して取得するのが正しい方法です。直接 `ga_session_id` と書いてもエラーになるか意図しない結果になるため注意してください。
:::

## 費用と運用時の注意点

BI Engineは予約したメモリ分だけ常に課金されます。1GBの予約であれば月額約2〜3ドル（リージョンによって異なります）ですので、試験導入のハードルは低いです。ただし、予約を作成したまま忘れると毎月課金され続けるため、以下の点に気をつけてください。

- **使わなくなったら予約を削除する**: コンソールの「BI Engine」ページから削除が可能です。プロジェクトを廃止した際にもBI Engineの予約が残っていると課金が続きます。
- **予約サイズの見直し**: 実際の利用状況を見ながら、1GBで効果が薄い場合は2GBや4GBに増やすことを検討してください。一方、使用率が低い場合は縮小してコストを抑えられます。
- **BigQuery Editionsとの関係**: BigQuery Editionsを契約している場合、BI Engineの予約はオンデマンド利用時とは異なる扱いになることがあります。課金モデルが複雑になる場合はGoogle Cloudのサポートや公式ドキュメントを参照してください。

また、BI Engineはあくまでクエリ応答速度の改善に特化した機能です。データの鮮度（リアルタイム性）には影響せず、BigQueryのストレージに最新データが書き込まれれば、BI Engineも更新されたデータを返します。

## まとめ

本記事では、BigQueryのBI Engineを活用してLooker Studioの表示速度を改善する方法についてご説明しました。要点を整理します。

- **BI Engine**はBigQueryのインメモリキャッシュ機能で、Looker Studioとの連携時に特に効果的です。
- 設定はGoogle Cloudコンソールから数分で完了し、1GBから試せる手軽さが特徴です。
- Looker Studio用のビューを作成してクエリをシンプルに保つことで、キャッシュの効率が高まります。
- GA4データを扱う際は、`ga_session_id` の取得には `UNNEST(event_params)` を、流入元には `collected_traffic_source.manual_medium/manual_source` を使用することが重要です。
- 予約は使わなくなったら忘れずに削除し、コストを管理することが大切です。

まずは1GBの予約を作成し、既存のLooker Studioダッシュボードで速度の変化を確認してみてください。その結果を見ながら、予約サイズやビューの設計を調整していくアプローチが現実的です。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [BigQuery × Looker Studioで前年同期比グラフを作る方法](https://zenn.dev/web_benriya/articles/bigquery-looker-studio-yoy-comparison-chart)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [チャネル別ROASをBigQueryで集計してLooker Studioに可視化する](https://zenn.dev/web_benriya/articles/bigquery-channel-roas-looker-studio)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
