# dbt プロジェクト雛形

GA4 の生データを `staging` → `mart` の2層に整形するための dbt プロジェクトです。
そのまま `dbt run` が通る構成になっています。

## 構成

```
dbt/
├── dbt_project.yml              プロジェクト定義
├── profiles.yml.example         接続情報のテンプレート
├── models/
│   ├── staging/
│   │   ├── _sources.yml         GA4 生データのソース定義
│   │   ├── schema.yml           テスト定義（not_null など）
│   │   ├── stg_events.sql       イベントの整形
│   │   ├── stg_sessions.sql     セッション単位への集約
│   │   └── stg_ga4_sessions.sql セッション整形（別実装）
│   └── mart/
│       └── mart_traffic.sql     流入元別のサマリ
└── .github/workflows/dbt-ci.yml PR時に dbt test を回す
```

`staging` はビュー、`mart` はテーブルとして作られます（`dbt_project.yml` の設定）。
ビューは実体を持たないのでストレージ費がかからず、
mart は実体化することでダッシュボードからの参照が速くなります。

## セットアップ

### 1. dbt をインストール

```bash
pip install dbt-bigquery
```

### 2. 接続情報を設定

`profiles.yml.example` を `~/.dbt/profiles.yml` にコピーして編集します。

```bash
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
```

書き換える箇所:

| キー | 値 |
|---|---|
| `project` | GCP プロジェクト ID |
| `dataset` | dbt が書き込む先のデータセット（例 `dbt_dev`。生データとは分ける） |
| `method` | ローカルなら `oauth`、CI なら `service-account` |
| `location` | `asia-northeast1`（GA4 のデータセットと揃える） |

:::message alert
`profiles.yml` には接続情報が入ります。リポジトリにコミットしないでください。
`~/.dbt/` に置くか、CI では環境変数から生成します。
:::

### 3. ソース定義を自社に合わせる

`models/staging/_sources.yml` の `database` と `schema` を、
自社の GCP プロジェクトと GA4 データセット（`analytics_XXXXXXXXX`）に書き換えます。

### 4. 接続を確認

```bash
dbt debug
```

`All checks passed!` が出れば設定完了です。

### 5. 実行

```bash
dbt run          # 全モデルを作成
dbt test         # テストを実行
dbt run --select staging   # staging だけ
dbt docs generate && dbt docs serve   # 依存関係をブラウザで確認
```

## 運用のポイント

**まず `dbt test` を通す習慣をつける。**
`schema.yml` に `not_null` テストを書いてあります。
GA4 のエクスポートが止まったり、スキーマが変わったりすると、
ダッシュボードが壊れる前にここで気づけます。

**CI を有効にする。**
`.github/workflows/dbt-ci.yml` は PR で `models/` が変更されたときに
`dbt test` を回す設定です。リポジトリの Secrets に
サービスアカウントの鍵を登録すれば動きます。

**mart は増やしすぎない。**
ダッシュボード1枚につき mart 1つが目安です。
汎用的な mart を作ろうとすると、結局どのダッシュボードにも合わない列が増えます。

## つまずきやすい点

**`dbt debug` で location エラー**
`profiles.yml` の `location` と GA4 データセットのロケーションが違います。
GA4 側は後から変更できないので、`profiles.yml` を合わせてください。

**`Access Denied` になる**
サービスアカウントに、GA4 データセットへの `BigQuery Data Viewer` と
書き込み先データセットへの `BigQuery Data Editor` が要ります。

**実行が遅い / 高額になる**
`stg_events.sql` の `_TABLE_SUFFIX` の期間を確認してください。
開発中は数日分に絞り、本番だけ全期間にするのが安全です。
