---
title: "BigQueryのデータリネージ機能でデータマートの依存関係を可視化する"
emoji: "🔀"
type: "tech"
topics: ["bigquery","googlecloud","dataengineering","sql","googleanalytics"]
published: false
---

## はじめに

「このデータマートのテーブル、何のビューが参照しているのか分からなくて修正できない」「上流のテーブルを変更したら、どのレポートに影響が出るか把握しきれない」——そうした悩みを抱えているデータ担当者は少なくありません。

BigQueryを使ったデータ基盤が育ってくると、テーブルやビューの数が増え、依存関係が複雑に絡み合ってきます。特にGA4のイベントデータを元にして複数のデータマートを作成している場合、「どのビューがどのテーブルを参照しているか」を手作業で把握するのは現実的ではありません。

Google CloudにはData Catalog（現在はDataplex配下に統合されつつあります）を通じた**データリネージ（Data Lineage）機能**があります。この機能を活用すると、BigQuery上のテーブル・ビュー・クエリジョブの依存関係を自動的に記録し、視覚的に確認できるようになります。本記事では、この機能の概要から実際の活用方法まで、エンジニアでない方にも分かりやすく解説します。

## データリネージとは何か

データリネージとは、「データがどこから来て、どこへ流れ、どう変換されたか」を追跡する仕組みのことです。日本語では「データの血統」「データの来歴」と訳されることもあります。

たとえばGA4のBigQueryエクスポートデータを元にして、以下のような処理フローがあるとします。

```
GA4 events_* テーブル
  └→ セッション集計ビュー（stg_sessions）
       └→ 流入別売上ビュー（mart_revenue_by_channel）
            └→ Looker Studio レポート
```

このフロー全体を自動的に記録・可視化するのがデータリネージの役割です。Google CloudではBigQueryのジョブ実行履歴を基に、このような依存関係グラフを自動生成してくれます。データエンジニアが手動でドキュメントを書き続ける必要がなくなる点が大きなメリットです。

:::message
データリネージはBigQueryの標準機能として有効化されますが、Dataplex APIの有効化が必要です。Google Cloud ConsoleのAPIとサービスから「Dataplex API」を検索し、有効化してください。
:::

## データリネージを有効化する手順

データリネージはプロジェクト単位で有効化します。Google Cloud Consoleから操作するか、gcloudコマンドで設定できます。

```bash
# Dataplex APIの有効化（未有効の場合）
gcloud services enable dataplex.googleapis.com --project=YOUR_PROJECT_ID

# データリネージAPIの有効化
gcloud services enable datalineage.googleapis.com --project=YOUR_PROJECT_ID
```

有効化後は、BigQueryでクエリを実行するたびにリネージ情報が自動収集されます。過去のジョブ履歴については遡って収集されないため、有効化後の実行分から記録が始まります。

Google Cloud Consoleでリネージを確認する場合は、BigQueryのテーブル詳細画面から「リネージ」タブを開きます。または、Dataplex → データリネージのメニューからプロセスやリンクの一覧を参照できます。

:::message
データリネージの保存期間はデフォルトで30日です。長期間保持したい場合は、APIを通じてエクスポートするか、Cloud Loggingと組み合わせた独自の記録を検討してください。
:::

## GA4データを使ったビューの依存関係を実際に確認する

GA4のBigQueryエクスポートデータを使い、セッションごとの流入元と購入金額を集計するビューを例に考えます。以下はその典型的なSQLです。

```sql
-- stg_sessions: セッション単位の流入元と購入金額を集計するビュー
CREATE OR REPLACE VIEW `your_project.your_dataset.stg_sessions` AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND event_name = 'purchase'
GROUP BY
  user_pseudo_id,
  ga_session_id,
  medium,
  source
;
```

このビューを作成した後、さらに上位のデータマートビューを作成します。

```sql
-- mart_revenue_by_channel: 流入チャネル別の売上集計ビュー
CREATE OR REPLACE VIEW `your_project.your_dataset.mart_revenue_by_channel` AS
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  SUM(revenue) AS total_revenue,
  COUNT(DISTINCT ga_session_id) AS sessions
FROM
  `your_project.your_dataset.stg_sessions`
GROUP BY
  medium,
  source
;
```

この2つのビューを作成してクエリを実行すると、BigQueryはリネージ情報として「events_* → stg_sessions → mart_revenue_by_channel」という依存関係を自動的に記録します。Consoleの「リネージ」タブを開くと、この流れがグラフとして表示されます。

## APIでリネージ情報をプログラムから取得する

GUIでの確認に加えて、Data Lineage APIを使うと依存関係をプログラムから取得できます。Pythonでの例を示します。

```python
from google.cloud import datalineage_v1

client = datalineage_v1.LineageClient()

# プロジェクトとロケーションを指定してリネージを検索
project_id = "your-project-id"
location = "us"  # BigQueryのロケーションに合わせる

parent = f"projects/{project_id}/locations/{location}"

# リンク（依存関係）の一覧を取得
request = datalineage_v1.ListLinksRequest(parent=parent)
links = client.list_links(request=request)

for link in links:
    print(f"ソース: {link.source.fully_qualified_name}")
    print(f"ターゲット: {link.target.fully_qualified_name}")
    print("---")
```

このスクリプトを定期実行してBigQueryに保存すれば、独自のリネージ管理基盤を作ることも可能です。リネージ情報をJSON形式でエクスポートしてドキュメント生成に活用する、といった応用もあります。

:::message
Data Lineage APIを使用するには、サービスアカウントに `roles/datalineage.viewer` 以上の権限が必要です。最小権限の原則に従い、閲覧のみのロールで運用することを推奨します。
:::

## データリネージ活用の実践的なユースケース

データリネージが特に役立つシナリオをいくつか紹介します。

**1. 上流テーブルの変更影響範囲の特定**

GA4のエクスポートテーブルのスキーマが変更されたとき、どのビューやクエリに影響が出るかを事前に洗い出せます。リネージグラフを下流方向にたどることで、影響を受けるオブジェクトの一覧が得られます。

**2. 不要テーブルの安全な削除**

「このテーブル、誰も参照していないだろうか？」という疑問に答えてくれます。リネージ上で下流にノードが存在しないテーブルは、削除候補として安全に特定できます。

**3. データ品質問題の根本原因調査**

レポートの数値がおかしいとき、上流のどのテーブルで問題が発生したかを追いやすくなります。リネージを上流方向にたどることで、データの問題が発生した箇所を絞り込めます。

**4. 新メンバーへのオンボーディング**

データ基盤の全体像を口頭で説明するのではなく、リネージグラフを見せることでデータの流れを直感的に伝えられます。ドキュメントメンテナンスの負担も軽減されます。

## まとめ

BigQueryのデータリネージ機能は、データ基盤が複雑化した際の管理コストを下げる実用的なツールです。GA4データを起点とした複数のデータマートを運用している場合、依存関係の把握はレポートの信頼性維持に直結します。

本記事のポイントを整理します。

- Dataplex API と Data Lineage API を有効化するだけで自動収集が始まる
- BigQuery Consoleのリネージタブで依存関係グラフをGUIで確認できる
- Data Lineage APIを使えばプログラムから依存関係を取得・活用できる
- 影響範囲の特定・不要テーブルの削除・障害調査・オンボーディングに活用できる

次のアクションとして、まずはGoogle Cloud ConsoleでDataplex APIを有効化し、既存のビューやテーブルのリネージタブを確認してみてください。依存関係が自動的に記録・表示される様子を体験するだけでも、データ基盤の運用に対する視点が変わるはずです。

## 関連記事

- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)
- [BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）](https://zenn.dev/web_benriya/articles/ga4-bigquery-bounce-rate-calculation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
