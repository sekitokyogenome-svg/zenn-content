---
title: "Claude Code × dbtでデータ変換パイプラインのテストコードを自動生成する"
emoji: "✅"
type: "tech"
topics: ["claude","bigquery","dbt","dataengineering","ai"]
published: false
---

## はじめに

「dbtのモデルを追加するたびに、テストを書くのが面倒でつい後回しにしてしまう」という経験はありませんか？データエンジニアリングの現場では、モデルの実装よりもテストコードの整備が後手に回りがちです。テストが不十分なままパイプラインを本番運用すると、データの品質問題に気づくのが遅れ、レポートやダッシュボードに誤った数字が表示されてしまうリスクがあります。

dbt（data build tool）はSQLを用いたデータ変換を体系的に管理できるツールですが、`schema.yml` に記述するテスト定義は量が多くなりやすく、地道な作業が求められます。特に `not_null`・`unique`・`accepted_values` といった定型テストを全カラムに漏れなく設定するのは、慣れていても手間のかかる工程です。

そこで活用したいのが **Claude Code** です。Claude CodeはAnthropicが提供するAIコーディングアシスタントで、ターミナルから直接コードの生成・修正・確認ができます。本記事では、Claude Codeを使ってdbtのテストコードを自動生成する具体的な方法を、GA4 × BigQueryの構成を例に解説します。非エンジニアの方でも手順を追って読み進められるよう丁寧に説明しますので、ぜひ参考にしてください。

## dbt × BigQueryの基本構成を整理する

まず、前提となる構成を確認しておきます。EC事業者がよく利用する構成として、GA4のイベントデータをBigQueryにエクスポートし、dbtで集計・変換してLooker Studioのダッシュボードに表示する流れがあります。

この構成では、dbtのモデルは大まかに次の3層に分かれます。

- **staging層**: GA4のrawデータをそのまま軽く整形する層
- **intermediate層**: セッション単位や商品単位に集約する層
- **marts層**: ビジネス指標を計算した最終的なビュー

GA4のBigQueryエクスポートデータは `events_*` というシャーディングテーブル形式で格納されています。たとえば `ga_session_id` はイベントのトップレベルカラムではなく、`event_params` 配列の中に入っているため、直接参照できません。以下のようにUNNESTを使って取り出す必要があります。

```sql
-- staging/stg_ga4_events.sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `your_project.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
```

このようなモデルに対して、`ga_session_id` が `not_null` であるか、`event_name` が想定値の範囲内に収まっているかといったテストを設定するのが品質管理の基本です。

## Claude Codeでテストコードを自動生成する手順

Claude Codeをインストールし、dbtプロジェクトのルートディレクトリで起動します。まだインストールしていない場合は以下のコマンドで導入できます。

```bash
npm install -g @anthropic-ai/claude-code
claude
```

起動後、プロジェクト内のSQLモデルファイルとスキーマファイルの場所を伝えるだけで、Claude Codeはファイルの内容を読み取り、テスト定義の生成を提案してくれます。

プロンプトの例としては、以下のように指示します。

```
models/staging/stg_ga4_events.sql のカラム定義を読んで、
schema.yml に追加すべき dbt テスト（not_null, unique, accepted_values など）を
YAML形式で生成してください。
```

Claude Codeはモデルファイルを解析し、次のようなYAMLを出力します。

```yaml
# models/staging/schema.yml
version: 2

models:
  - name: stg_ga4_events
    description: "GA4イベントデータのステージングモデル"
    columns:
      - name: event_date
        description: "イベント発生日（YYYYMMDD形式）"
        tests:
          - not_null
      - name: event_name
        description: "イベント名"
        tests:
          - not_null
          - accepted_values:
              values:
                - page_view
                - session_start
                - purchase
                - add_to_cart
                - begin_checkout
      - name: user_pseudo_id
        description: "ユーザー識別子"
        tests:
          - not_null
      - name: ga_session_id
        description: "セッションID（event_paramsから取得）"
        tests:
          - not_null
      - name: medium
        description: "流入メディア（collected_traffic_source.manual_medium）"
      - name: source
        description: "流入ソース（collected_traffic_source.manual_source）"
```

生成されたYAMLをそのまま `schema.yml` に貼り付けるのではなく、自社のデータに合わせて `accepted_values` の値を調整することが重要です。Claude Codeに「実際のデータから頻出のevent_nameを10件取得するSQLも生成して」と追加で依頼すると、検証用のクエリまで一緒に出力してもらえます。

## テスト実行と結果の確認

テスト定義を `schema.yml` に追記したら、以下のコマンドでdbtのテストを実行します。

```bash
dbt test --select stg_ga4_events
```

テストが失敗した場合、dbtはどのカラムで何件のレコードが条件を満たさなかったかをコンソールに出力します。Claude Codeのセッションを続けたまま、エラーメッセージをそのままペーストして「このエラーの原因と修正方法を教えて」と尋ねることができます。

:::message
dbt testの失敗ログをClaude Codeに貼り付ける際は、機密情報（プロジェクトID・データセット名など）を伏せてからペーストするようにしましょう。ログには内部のテーブル名やスキーマ情報が含まれる場合があります。
:::

テストがすべてパスしたら、継続的インテグレーション（CI）のパイプラインに組み込むことで、モデルの変更のたびに自動でテストが走る仕組みを整備できます。GitHub Actionsと組み合わせる場合のワークフロー例も、Claude Codeに依頼すれば雛形を生成してもらえます。

## 繰り返し作業をClaude Codeで効率化するポイント

dbtプロジェクトが大きくなると、モデルの数は数十〜数百に及ぶこともあります。そのすべてに手作業でテストを追加するのは現実的ではありません。Claude Codeを活用する際のポイントを整理します。

**ポイント1: モデル一覧をまとめて渡す**
`ls models/staging/*.sql` の出力結果をClaude Codeに渡して「これらすべてのモデルに対応するschema.ymlのテスト定義を一括生成して」と指示すると、複数ファイルをまとめて処理してくれます。

**ポイント2: プロジェクト固有のルールを事前に伝える**
たとえば「このプロジェクトでは `_at` で終わるカラムはすべてTIMESTAMP型で not_null テストを付ける」といったルールをClaude Codeに最初に説明しておくと、以降の生成結果にそのルールが反映されます。

**ポイント3: 生成結果のレビューを怠らない**
AIが生成したコードはそのまま使うのではなく、必ずレビューしてから適用してください。特に `accepted_values` のリストは、実際のデータと照合して過不足がないか確認することが大切です。

## まとめ

本記事では、Claude Code × dbtを活用してデータ変換パイプラインのテストコードを自動生成する方法を解説しました。要点を整理します。

- dbtのテスト定義は品質管理に欠かせないが、手作業での整備は工数がかかる
- Claude Codeにモデルファイルを読み込ませることで、`schema.yml` のテスト定義を自動生成できる
- GA4のBigQueryエクスポートデータでは `ga_session_id` のUNNESTや `collected_traffic_source` の扱いに注意が必要
- 生成結果は必ず自社データと照合してレビューすること
- CIパイプラインに組み込むことで、テストの自動実行が実現できる

次のアクションとしては、まずひとつのstagingモデルを対象にClaude Codeでテスト生成を試してみることをお勧めします。小さな範囲で成功体験を積んでから、プロジェクト全体へ展開していく進め方がスムーズです。

## 関連記事

- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
