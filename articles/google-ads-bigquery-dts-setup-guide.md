---
title: "Google広告データをBigQuery Data Transfer Serviceで自動連携する完全手順"
emoji: "📡"
type: "tech"
topics: ["bigquery","googleads","googlecloud","sql","dataengineering"]
published: false
---

## はじめに

Google広告（旧Google AdWords）でリスティング広告を運用していると、「どのキャンペーンが実際に売上につながっているのか」「クリック数は多いのにコンバージョンが少ない広告グループはどこか」といった疑問が出てきます。Google広告の管理画面でも一定のレポートは確認できますが、過去データの保存期間に制限があり、GA4や他のデータと組み合わせた分析は難しいのが現状です。

BigQueryにGoogle広告のデータを自動でエクスポートできれば、日次の広告パフォーマンスを長期間蓄積し、GA4のセッションデータや自社の売上データと突き合わせた踏み込んだ分析が可能になります。そのための公式機能が **BigQuery Data Transfer Service（以下DTS）** です。

本記事では、DTSを使ってGoogle広告データをBigQueryへ自動連携するための初期設定手順を、Googleクラウドの操作画面を中心に解説します。コマンドライン操作が不要な箇所はGUIだけで完結しますので、クラウド初心者の方でも取り組みやすい内容になっています。

---

## BigQuery Data Transfer Serviceとは

BigQuery Data Transfer Service（DTS）は、Google公式が提供するデータ転送マネージドサービスです。スケジュールを設定するだけで、Google広告・Google Analytics 4・YouTube広告・Search Ads 360など複数のソースからBigQueryへデータを定期的に自動転送できます。

手動でAPIを叩くスクリプトを書く必要がなく、転送の失敗時には自動リトライが走るため、運用負荷を大幅に下げられます。無料枠の範囲内で始められるケースも多く、コストを抑えながらデータ基盤を整えたい中小規模の事業者にも向いています。

:::message
DTSはGoogle Cloudの有料サービスですが、BigQueryへのデータ転送自体には転送料金はかかりません。ただしBigQueryのストレージ料金やクエリ実行料金は別途発生します。毎月の無料枠（ストレージ10GBなど）を超えた場合に課金が始まるため、小規模運用では実質無料に収まることが多いです。
:::

---

## 事前準備：必要な権限とAPIの有効化

設定を始める前に、以下の点を確認してください。

### 必要なGoogleアカウント権限

| 対象 | 必要な権限 |
|------|-----------|
| Google Cloud プロジェクト | BigQuery管理者、またはプロジェクト編集者 |
| Google広告アカウント | 管理者またはレポートアクセス権 |
| BigQuery Data Transfer Service | サービスエージェントへの適切なロール付与 |

Googleアカウントが複数ある場合（個人用・会社用など）、Google広告とGoogle Cloudで同じアカウントを使うか、権限の委任設定が適切に行われているかを先に確認しておくとスムーズです。

### APIの有効化手順

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセスし、対象プロジェクトを選択します。
2. 左メニューの「APIとサービス」→「ライブラリ」を開きます。
3. 検索欄に `BigQuery Data Transfer API` と入力し、表示された結果から「有効にする」をクリックします。

```bash
# gcloud CLIを使う場合は以下のコマンドでも有効化できます
gcloud services enable bigquerydatatransfer.googleapis.com \
  --project=YOUR_PROJECT_ID
```

APIの有効化は数十秒で完了します。有効化後は次のステップに進んでください。

---

## BigQuery側の設定：データセットの作成

Google広告データを受け取るBigQueryのデータセットを作成します。

1. Google Cloud ConsoleでBigQueryを開きます。
2. 左パネルのプロジェクト名の隣にある「+」アイコンをクリックし「データセットを作成」を選択します。
3. 以下の設定を入力します。

| 項目 | 推奨設定 |
|------|---------|
| データセットID | `google_ads_transfer`（任意） |
| データのロケーション | `asia-northeast1`（東京） |
| デフォルトのテーブル有効期限 | 設定なし（長期保存したい場合） |

:::message
データセットのリージョンは後から変更できません。GA4のBigQueryエクスポートと同じリージョンを選んでおくと、後でデータを結合するクエリのコストを抑えられます。
:::

---

## DTS転送設定：Google広告との接続

データセットが用意できたら、DTSの転送設定を作成します。

1. BigQueryの左メニューから「Data Transfer」を選択します。
2. 「転送を作成」ボタンをクリックします。
3. ソースの種類で「Google広告」を選択します。
4. 以下の項目を設定します。

| 設定項目 | 内容 |
|---------|------|
| 表示名 | `Google Ads Daily Transfer`など識別しやすい名前 |
| スケジュール | 毎日（推奨）または任意の間隔 |
| 転送先データセット | 先ほど作成した `google_ads_transfer` |
| Google 広告顧客 ID | `XXX-XXXX-XXXX` 形式のID |

「次へ」をクリックすると認証画面が表示されます。Google広告にアクセスできるGoogleアカウントでログインし、アクセスを許可してください。

設定保存後、初回の転送が数分〜数時間以内に自動的に実行されます。過去データのバックフィル（遡及取得）は、転送設定画面から「バックフィルのスケジュール」で最大180日分を指定できます。

---

## 転送後のテーブル確認とサンプルSQLクエリ

転送が完了すると、指定したデータセット配下に複数のテーブルが自動生成されます。代表的なものは以下の通りです。

| テーブル名（接頭辞） | 主な内容 |
|--------------------|---------|
| `ads_Campaign_` | キャンペーン別のインプレッション・クリック・費用 |
| `ads_AdGroup_` | 広告グループ別のパフォーマンス |
| `ads_Keyword_` | キーワード別の詳細指標 |
| `ads_ConversionAction_` | コンバージョンアクション別の集計 |

テーブル名の末尾には `_YYYYMMDD` 形式の日付パーティションが付きます。

### キャンペーン別コストとコンバージョンを確認するSQL

```sql
SELECT
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 0) AS cost_jpy,
  metrics.conversions AS conversions,
  SAFE_DIVIDE(
    ROUND(metrics.cost_micros / 1000000, 0),
    metrics.conversions
  ) AS cpa
FROM
  `YOUR_PROJECT.google_ads_transfer.ads_Campaign_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
ORDER BY
  cost_jpy DESC
LIMIT 20;
```

`cost_micros` はマイクロ単位（1/1,000,000）で格納されているため、日本円に換算する際は100万で割ります。

### GA4データと掛け合わせて流入経路を確認するSQL

GA4のBigQueryエクスポートと組み合わせることで、Google広告からの流入セッションが実際にどのようなユーザー行動につながったかを確認できます。

```sql
WITH google_ads_sessions AS (
  SELECT
    -- ga_session_idはevent_paramsのUNNESTで取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `YOUR_PROJECT.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY
    ga_session_id,
    user_pseudo_id,
    medium,
    source
)

SELECT
  source,
  medium,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(event_count) AS total_events
FROM
  google_ads_sessions
GROUP BY
  source,
  medium
ORDER BY
  sessions DESC;
```

:::message
`ga_session_id` はGA4のイベントテーブルでトップレベルのカラムとしては存在しません。`UNNEST(event_params)` でネストされた配列を展開し、`key = 'ga_session_id'` の行から `value.int_value` を取り出す必要があります。直接 `event_params.ga_session_id` のように参照するとエラーになるためご注意ください。
:::

---

## よくあるトラブルと対処法

### 転送ステータスが「失敗」になる

DTSの転送履歴画面でエラーログを確認します。多くの場合、以下のいずれかが原因です。

- Google広告アカウントのアクセス権限が不足している
- サービスアカウントへのBigQueryデータ編集者ロールが未付与
- Google広告の顧客IDに誤りがある（ハイフンなしで入力が必要な場合あり）

エラーメッセージをコピーしてCloud Consoleの「サポート」またはGoogle検索で調べると、対処方法を見つけやすいです。

### テーブルが作られない、データが空

初回転送直後はテーブル生成に時間がかかることがあります。1〜2時間経ってから再度確認してみてください。また、バックフィルを指定していない場合は当日分のデータしか取得されないため、過去データが必要な場合はバックフィルのスケジュールを別途設定します。

---

## まとめ

Google広告データをBigQuery Data Transfer Serviceで自動連携する手順を以下に整理します。

1. **API有効化** — Google Cloud ConsoleでBigQuery Data Transfer APIを有効にする
2. **データセット作成** — 転送先となるBigQueryデータセットをGA4と同じリージョンで作成する
3. **DTS転送設定** — ソースにGoogle広告を選択し、スケジュールと転送先を設定する
4. **データ確認** — 生成されたテーブルにSQLでアクセスし、コスト・コンバージョンを集計する
5. **GA4と結合** — `UNNEST(event_params)` を使ってセッションIDを取得し、広告効果を多角的に分析する

一度設定してしまえばデータ収集は全自動で動き続けるため、毎朝の手動ダウンロード作業から解放されます。蓄積したデータをLooker Studioでダッシュボード化すると、経営会議やクライアントへの報告資料として活用しやすくなります。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
