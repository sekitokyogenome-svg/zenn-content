---
title: "TerraformでBigQueryのデータセット・テーブル・ビューをコード管理する"
emoji: "🏗️"
type: "tech"
topics: ["bigquery","terraform","googlecloud","dataengineering","iac"]
published: false
---

## はじめに

「BigQueryのテーブル構成をチームで管理しているが、誰かが手動でスキーマを変更してしまい、気づいたら本番環境と開発環境がずれていた」——そのような経験はないでしょうか。

データ分析基盤を運用していると、テーブルやビューの定義をGUIやSQL文で場当たり的に変更するうちに、どこに何があるのかわからなくなる状況は珍しくありません。特にGA4のBigQueryエクスポートを活用して分析している場合、補助テーブルやビューが増えるにつれて管理コストが膨らんでいきます。

そこで有効なのが、インフラのコード管理ツールである **Terraform** を使ってBigQueryリソースをコードとして定義・管理する手法です。データセット・テーブル・ビューの構成をすべてコードで表現することで、変更履歴をGitで追跡でき、チーム間のレビューも容易になります。

本記事では、TerraformによるBigQueryリソースのコード管理の基本を、実際の設定ファイルを交えながら解説します。Terraformを初めて触る方でも概要を把握できるよう、丁寧に説明していきます。

---

## Terraformとは何か、なぜBigQueryに使うのか

Terraform は HashiCorp が開発したオープンソースの Infrastructure as Code（IaC）ツールです。クラウドリソースの構成をHCL（HashiCorp Configuration Language）と呼ばれる宣言的な記法で記述し、`terraform apply` コマンド一つでその状態を実現します。

BigQueryにTerraformを採用する主なメリットは以下のとおりです。

- **構成のバージョン管理**: `.tf` ファイルをGitで管理することで、いつ・誰が・何を変更したかを追跡できます。
- **再現性の確保**: 開発・ステージング・本番の各環境を同じコードから構築でき、設定の乖離を防げます。
- **レビュープロセスの導入**: プルリクエスト経由で変更をレビューする文化を作れます。
- **削除・変更の事故防止**: Terraformの状態ファイル（`.tfstate`）が管理する範囲は、意図しない削除を検知して警告します。

逆に、Terraformはセットアップコストが伴うため、単発の分析作業や少人数での一時的な利用には向きません。チームでのデータ基盤運用や、長期的に保守するテーブル・ビューの管理に特に適しています。

---

## 事前準備：プロバイダーとバックエンドの設定

Terraformを使ってGoogle CloudのBigQueryを操作するには、まず `google` プロバイダーの設定と、状態ファイルを保存するバックエンドの設定が必要です。

以下は `provider.tf` の例です。

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "bigquery/state"
  }
}

provider "google" {
  project = var.project_id
  region  = "asia-northeast1"
}
```

`backend "gcs"` ではTerraformの状態ファイルをGoogle Cloud Storage（GCS）に保存しています。これにより、チームメンバー間で状態を共有でき、ローカルの `.tfstate` ファイルが散乱する問題を防げます。

変数ファイル `variables.tf` でプロジェクトIDを定義しておくとコードの再利用性が高まります。

```hcl
variable "project_id" {
  description = "Google CloudプロジェクトID"
  type        = string
}
```

実行時は `terraform.tfvars` ファイルに値を記載するか、環境変数 `TF_VAR_project_id` で渡します。

:::message
初回の `terraform init` コマンドを実行することで、プロバイダーのプラグインとバックエンドの初期化が行われます。このステップはリポジトリをクローンした全員が実施する必要があります。
:::

---

## データセットの定義

BigQueryにおける「データセット」は、テーブルやビューを格納するコンテナです。Terraformでは `google_bigquery_dataset` リソースで管理します。

```hcl
resource "google_bigquery_dataset" "analytics" {
  dataset_id                 = "analytics"
  friendly_name              = "アナリティクスデータセット"
  description                = "GA4エクスポートおよび集計テーブルを格納するデータセット"
  location                   = "asia-northeast1"
  delete_contents_on_destroy = false

  labels = {
    env  = "production"
    team = "data"
  }
}
```

`delete_contents_on_destroy = false` は重要な設定です。この値を `true` にすると、`terraform destroy` 実行時にデータセット内のテーブルごと削除されてしまいます。本番運用では `false` を維持し、意図しないデータ消失を防ぐことを推奨します。

また、`labels` を付与しておくことで、コスト分析や権限管理の際にリソースを絞り込みやすくなります。GA4のBigQueryエクスポートが書き込む `analytics_XXXXXXXXX` データセットは、Googleが自動生成するため通常はTerraform管理外とし、集計用やビュー定義用のデータセットをコード管理するのが現実的です。

---

## テーブルの定義とスキーマ管理

`google_bigquery_table` リソースを使うことで、テーブルのスキーマをコードで管理できます。スキーマはJSONファイルとして外出しにするのが一般的です。

まず、`schemas/session_summary.json` としてスキーマを定義します。

```json
[
  {
    "name": "session_date",
    "type": "DATE",
    "mode": "REQUIRED",
    "description": "セッション日付"
  },
  {
    "name": "ga_session_id",
    "type": "INT64",
    "mode": "NULLABLE",
    "description": "GAセッションID（event_paramsより取得）"
  },
  {
    "name": "medium",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "流入メディア（manual_medium）"
  },
  {
    "name": "source",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "流入ソース（manual_source）"
  },
  {
    "name": "session_count",
    "type": "INT64",
    "mode": "NULLABLE",
    "description": "セッション数"
  }
]
```

次に、テーブルリソースを `tables.tf` で定義します。

```hcl
resource "google_bigquery_table" "session_summary" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "session_summary"
  description = "日別・流入元別のセッションサマリーテーブル"

  schema = file("${path.module}/schemas/session_summary.json")

  time_partitioning {
    type  = "DAY"
    field = "session_date"
  }

  labels = {
    env = "production"
  }

  deletion_protection = true
}
```

`deletion_protection = true` を設定すると、Terraform経由でのテーブル削除が保護されます。誤って `terraform destroy` を走らせてもテーブルが消えないため、本番テーブルには設定しておくと安心です。

スキーマJSONファイルをリポジトリで管理することで、スキーマ変更もプルリクエストのレビュー対象になります。

---

## ビューの定義とGA4クエリの活用

BigQueryのビューも `google_bigquery_table` リソースで定義できます。`view` ブロックにSQLを記述するだけです。

以下は、GA4のBigQueryエクスポートデータを使って日別・流入元別のセッション数を集計するビューの例です。

```hcl
resource "google_bigquery_table" "v_session_by_source" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "v_session_by_source"
  description = "GA4エクスポートから流入元別セッションを集計するビュー"

  view {
    query = <<-EOT
      SELECT
        PARSE_DATE('%Y%m%d', event_date) AS session_date,
        (
          SELECT ep.value.int_value
          FROM UNNEST(event_params) AS ep
          WHERE ep.key = 'ga_session_id'
        ) AS ga_session_id,
        collected_traffic_source.manual_medium AS medium,
        collected_traffic_source.manual_source AS source,
        COUNT(DISTINCT
          CONCAT(
            user_pseudo_id,
            CAST(
              (SELECT ep.value.int_value FROM UNNEST(event_params) AS ep WHERE ep.key = 'ga_session_id')
              AS STRING
            )
          )
        ) AS session_count
      FROM
        `${var.project_id}.analytics_XXXXXXXXX.events_*`
      WHERE
        _TABLE_SUFFIX BETWEEN
          FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
        AND event_name = 'session_start'
      GROUP BY
        1, 2, 3, 4
    EOT
    use_legacy_sql = false
  }
}
```

:::message
GA4のBigQueryエクスポートでは、`ga_session_id` はトップレベルのカラムとして存在せず、`event_params` 配列の中にネストされています。`UNNEST(event_params)` を使って展開し、`key = 'ga_session_id'` で絞り込む必要があります。また、流入元情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` から取得してください。
:::

SQLをHCLファイルに埋め込む `<<-EOT ... EOT` のヒアドキュメント記法は可読性が良く、長いSQLの管理に適しています。ただし、SQLが複雑になる場合は `templatefile()` 関数を使って別ファイルに切り出すとさらにメンテナンスしやすくなります。

---

## まとめ

本記事では、TerraformによるBigQueryのデータセット・テーブル・ビューのコード管理について解説しました。要点を整理します。

| 項目 | リソース名 | ポイント |
|------|-----------|----------|
| データセット | `google_bigquery_dataset` | `delete_contents_on_destroy = false` で保護 |
| テーブル | `google_bigquery_table` | スキーマはJSONファイルで外出し管理 |
| ビュー | `google_bigquery_table`（viewブロック） | SQLはヒアドキュメントで記述 |

次のアクションとしては、まず開発環境でプロバイダーの設定と小さなデータセット一つをTerraformで管理することから始めてみてください。既存リソースは `terraform import` コマンドでコード管理下に取り込むことも可能です。

Gitリポジトリと組み合わせてプルリクエストのレビューフローを整えることで、データ基盤の変更管理が格段に安定し、チームの信頼性が向上します。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
