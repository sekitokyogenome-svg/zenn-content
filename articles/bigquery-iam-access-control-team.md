---
title: "BigQueryのアクセス制御をIAMで適切に設計する【チーム運用編】"
emoji: "🔐"
type: "tech"
topics: ["bigquery","googlecloud","dataengineering","sql","security"]
published: false
---

## はじめに

「分析担当者にデータを見せたいけれど、どこまで権限を渡すべきか迷っている」「とりあえず全員にオーナー権限を付与してしまっているが、セキュリティ的に問題ないのか不安」——そのようなお悩みを持つ方は少なくありません。

BigQueryはGoogle Cloudのデータウェアハウスサービスとして、EC事業者やWebマーケティング担当者にも広く活用されています。GA4のデータをBigQueryにエクスポートして分析するケースも増えており、チームでデータを共有・活用する機会が増えています。

しかし、アクセス権限の設計を誤ると、意図せず重要なデータが漏洩したり、誤操作でテーブルが削除されたりするリスクがあります。また、監査ログに「誰が何をしたか」が残るため、権限設計は後から問題が発覚した際の追跡にも影響します。

本記事では、BigQueryのIAM（Identity and Access Management）を活用したアクセス制御の基本的な考え方と、チームで運用する際の設計指針をご紹介します。エンジニアでない方にも理解しやすいよう、実例を交えながら解説していきます。

---

## BigQuery IAMの基本構造を理解する

BigQueryのアクセス制御は、Google CloudのIAMという仕組みを中心に設計されています。IAMでは「誰（Who）に」「何のリソース（Resource）に対して」「どんな操作（Role）を許可するか」を定義します。

BigQueryには主に以下のようなロールがあります。

| ロール名 | 主な権限 |
|---|---|
| BigQuery 閲覧者（roles/bigquery.dataViewer）| テーブルのデータ参照のみ |
| BigQuery データ編集者（roles/bigquery.dataEditor）| データの読み書き（テーブル削除は不可）|
| BigQuery データオーナー（roles/bigquery.dataOwner）| データセット全体の管理 |
| BigQuery ジョブユーザー（roles/bigquery.jobUser）| クエリの実行（データ閲覧とセットで使う）|
| BigQuery 管理者（roles/bigquery.admin）| プロジェクト全体の管理 |

チーム運用において重要なのは、「閲覧者」と「ジョブユーザー」を組み合わせるパターンです。データを参照するだけのメンバーには、`roles/bigquery.dataViewer` と `roles/bigquery.jobUser` の2つをセットで付与します。この組み合わせにより、クエリは実行できるもののデータの書き換えや削除はできない、安全な権限設計が実現できます。

---

## データセット単位でのアクセス制御を活用する

BigQueryのアクセス制御は、プロジェクト単位だけでなくデータセット単位でも設定できます。この「粒度の細かい制御」がチーム運用において非常に役立ちます。

たとえば以下のようなケースを考えてみましょう。

- **マーケティングチーム**：GA4のイベントデータや広告コストデータを閲覧・分析したい
- **財務チーム**：売上・原価データを参照したいが、広告コストの詳細は不要
- **経営層**：サマリーダッシュボード用データのみ参照したい

このような場合、データセットを用途別に分割し、それぞれに適切なIAMロールを付与することが望ましい設計です。

```bash
# GA4データセットにマーケティングチームの閲覧権限を付与する例（gcloudコマンド）
bq update --dataset \
  --set_label team:marketing \
  your-project-id:ga4_export

# IAMバインディングの追加（データセットレベル）
bq update \
  --set_label owner:marketing \
  your-project-id:ga4_export
```

データセットのIAM設定はGoogle Cloud ConsoleのBigQueryページからGUI操作でも行えます。データセットを選択し「共有」→「権限」から特定のメールアドレスやGoogleグループを追加できます。Googleグループを使うと、メンバーが変わってもグループ側を更新するだけで済むため、管理コストを抑えられます。

:::message
データセット単位の権限設定はプロジェクトレベルの設定より細かく制御できます。ただし、プロジェクトレベルで付与した権限はデータセット設定より優先される点に注意が必要です。
:::

---

## GA4データへの閲覧権限を安全に設計する

GA4のデータをBigQueryにエクスポートしている場合、イベントデータにはユーザーの行動履歴が含まれているため、誰でも自由に参照できる状態は避けるべきです。

以下は、GA4のBigQueryエクスポートデータを使ったクエリ例です。流入元ごとのセッション数を集計しています。

```sql
-- GA4エクスポートデータを使った流入元別セッション集計
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS session_count
FROM
  `your-project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  session_count DESC
LIMIT 20;
```

このようなクエリを実行できるメンバーには、`roles/bigquery.dataViewer`（GA4データセットのみ）と `roles/bigquery.jobUser`（プロジェクトレベル）の組み合わせが適切です。クエリの実行コストはプロジェクト側に課金されるため、`jobUser` 権限の付与先は慎重に管理しましょう。

:::message
`ga_session_id` はイベントパラメータの中に格納されているため、`UNNEST(event_params)` を経由して取得する必要があります。直接カラムとして参照することはできません。また、流入元の情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使用してください。
:::

---

## 権限の最小化原則とGoogleグループの活用

IAMの設計において「最小権限の原則」は基本中の基本です。これは「そのメンバーが業務を遂行するのに必要な最低限の権限だけを付与する」という考え方です。

チーム運用でよく見られる問題として、以下が挙げられます。

- 全員に `roles/bigquery.admin` を付与してしまっている
- 退職したメンバーのアカウントに権限が残ったまま
- 個人のメールアドレスで管理しているため、担当者変更のたびに設定変更が必要

これらの問題を解消するために、**Googleグループを使った権限管理**が有効です。

```
例）チームのGoogleグループ構成
- marketing-team@your-company.com → BigQuery閲覧者（GA4データセット）+ ジョブユーザー
- data-analyst@your-company.com   → BigQuery データ編集者（分析用データセット）+ ジョブユーザー
- bi-admin@your-company.com       → BigQuery 管理者（限定メンバーのみ）
```

Googleグループに対してIAMロールを付与しておくと、メンバーの入退社時はグループのメンバーを更新するだけで権限管理が完了します。個人アカウントへの直接付与を減らすことで、権限の棚卸しやセキュリティ監査も格段にシンプルになります。

また、四半期に一度程度のペースで、付与している権限が現在の業務に即しているか棚卸しをすることをお勧めします。不要になった権限は速やかに削除することが、リスクの低減につながります。

---

## まとめ

本記事では、BigQueryのIAMを使ったアクセス制御の設計について、チーム運用の観点からポイントをまとめました。

- **IAMロールを使い分ける**：閲覧のみのメンバーには `dataViewer` + `jobUser` の組み合わせが基本
- **データセット単位で制御する**：用途別にデータセットを分割し、必要なチームにのみ権限を付与
- **GA4データは適切に保護する**：個人行動データを含むため、閲覧できるメンバーを限定する
- **Googleグループで管理する**：個人アカウントへの直接付与を避け、入退社・担当変更に強い設計にする
- **定期的な棚卸しを行う**：不要な権限は削除し、最小権限の原則を維持する

次のアクションとして、まず自社のBigQueryプロジェクトで現在付与されているIAM権限を一覧で確認してみましょう。Google Cloud Consoleの「IAMと管理」→「IAM」から、プロジェクトに紐づくすべての権限を確認できます。想定外のメンバーに広い権限が付与されていないかどうかをチェックするところから始めると、実践的なアクセス制御設計の第一歩になります。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
