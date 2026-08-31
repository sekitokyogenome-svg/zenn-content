---
title: "Gemini CLIをGA4データアナリストとして使う具体的な設定と活用例"
emoji: "💻"
type: "tech"
topics: ["gemini","googleanalytics","bigquery","ai","googlecloud"]
published: true
---

## はじめに

GA4のデータをBigQueryに連携したものの、「SQLを書くのが難しい」「毎週のレポートを作るのが手間」と感じていませんか。あるいは、レポートを眺めながら「この数字が下がっている原因は何だろう」と考えても、次の一手が浮かびにくいという経験はないでしょうか。

Googleが提供するコマンドラインツール「Gemini CLI」を活用すると、ターミナル上でGeminiに問いかけるだけで、BigQueryへのクエリ作成・実行・結果の解釈までを一気通貫で進められます。エンジニアでなくても、コマンドを少し覚えるだけで分析の幅が広がります。

本記事では、Gemini CLIをGA4データ分析に特化した「AIアナリスト」として活用するための初期設定から、実際のクエリ活用例までを順を追ってご説明します。

---

## Gemini CLIとは何か

Gemini CLIは、Googleが2025年に公開したオープンソースのコマンドラインインターフェースです。ターミナル（WindowsであればコマンドプロンプトやWSL）からGeminiモデルを呼び出し、会話形式でさまざまな作業を指示できます。

特徴的なのは、ファイルシステムやシェルコマンドと連携できる点です。たとえば「このCSVを読み込んで集計して」「BigQueryにこのSQLを流して結果を見せて」といった指示を自然言語で与えると、Gemini CLIがツール呼び出しを自動で行い、結果をその場で返してくれます。

:::message
Gemini CLIの無料枠では、Google個人アカウントでサインインすると1分あたり60リクエスト・1日あたり1,000リクエストまで利用できます（2025年時点）。商用利用や高頻度の分析にはGoogle AI StudioまたはVertex AIのAPIキーが必要です。
:::

---

## 初期設定：インストールからGA4プロジェクトの接続まで

### インストール

Node.js（v18以上）が必要です。以下のコマンドでインストールします。

```bash
npm install -g @google/gemini-cli
```

インストール後、初回起動時に認証を行います。

```bash
gemini
```

ブラウザが開いてGoogleアカウントへのサインインを求められます。承認するとターミナルに戻り、チャット形式のUIが立ち上がります。

### BigQueryとの連携設定

Gemini CLIからBigQueryを操作するには、Google Cloud CLIの認証が必要です。

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

`YOUR_PROJECT_ID` の部分には、GA4のBigQueryエクスポートを設定しているGoogle CloudプロジェクトのIDを入力してください。BigQueryのエクスポートが有効になっていれば、`analytics_XXXXXXXXX` という名前のデータセットがプロジェクト内に存在しているはずです。

---

## GEMINI.mdでアナリストとしての役割を定義する

Gemini CLIには「GEMINI.md」というプロジェクト設定ファイルがあります。このファイルに指示を書いておくと、毎回のセッションでGeminiが自動的にその内容を読み込み、特定の役割・ルールに従って応答してくれます。

作業ディレクトリに `GEMINI.md` を作成し、以下のような内容を記述します。

```markdown
# GA4データアナリスト設定

あなたはGA4・BigQueryの専門アナリストです。以下のルールに従って分析・回答してください。

## プロジェクト情報
- GCPプロジェクトID: your-project-id
- GA4データセット: analytics_123456789
- テーブル形式: events_YYYYMMDD（日付シャーディング形式）

## クエリルール
- ga_session_idはevent_paramsをUNNESTして取得する
- 流入元はcollected_traffic_source.manual_medium / manual_sourceを使用する
- 日付範囲は_TABLE_SUFFIXでフィルタリングする
- クエリにはコスト削減のためLIMIT句を付ける

## 回答スタイル
- 分析結果は日本語で要約する
- 改善提案はEC事業者向けに具体的に述べる
```

この設定をしておくことで、「先週のセッション数を流入元別に出して」という一言だけで、正しいテーブル・カラムを参照したSQLを自動生成・実行してくれるようになります。

---

## 活用例①：流入元別セッション数の集計

以下のような指示をGemini CLIのチャット欄に入力します。

```
先週（2025-07-21〜2025-07-27）の流入元・メディア別のセッション数を集計してください。
```

Gemini CLIが生成・実行するSQLの例は次のとおりです。

```sql
SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `your-project-id.analytics_123456789.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250721' AND '20250727'
  AND event_name = 'session_start'
GROUP BY
  source, medium
ORDER BY
  sessions DESC
LIMIT 50;
```

:::message
`ga_session_id` はイベントレベルのパラメータとして格納されており、`UNNEST(event_params)` を経由しなければ取得できません。直接 `event_params.ga_session_id` のように参照するとエラーになるためご注意ください。
:::

結果が返ってきたら、続けて「このデータから改善提案をください」と入力するだけで、Geminiが数値を踏まえた考察を日本語で回答してくれます。

---

## 活用例②：購入完了ファネルのドロップオフ分析

ECサイトでよくある課題として「カートに商品を入れたが購入に至らない」があります。以下のように指示します。

```
先月（2025-07-01〜2025-07-31）のview_item → add_to_cart → purchase
のファネル別ユーザー数を出してください。
```

生成されるSQLのイメージは次のとおりです。

```sql
WITH funnel AS (
  SELECT
    user_pseudo_id,
    MAX(IF(event_name = 'view_item', 1, 0))   AS viewed,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added,
    MAX(IF(event_name = 'purchase', 1, 0))    AS purchased
  FROM
    `your-project-id.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  GROUP BY
    user_pseudo_id
)
SELECT
  SUM(viewed)    AS view_item_users,
  SUM(added)     AS add_to_cart_users,
  SUM(purchased) AS purchase_users,
  ROUND(SUM(added)     / NULLIF(SUM(viewed), 0) * 100, 1) AS add_rate_pct,
  ROUND(SUM(purchased) / NULLIF(SUM(added), 0)  * 100, 1) AS purchase_rate_pct
FROM funnel;
```

ドロップオフが大きいステップを特定し、続けてGeminiに「add_to_cartからpurchaseのドロップ率が高い場合の改善施策を教えてください」と質問すると、カート放棄メール・送料無料施策・決済ステップ簡略化など、EC文脈に合った提案が返ってきます。

---

## 活用例③：週次レポートをMarkdownで自動生成する

Gemini CLIはシェルスクリプトとも連携できます。以下のようなスクリプトを用意しておくと、週次レポートをMarkdownファイルとして自動出力できます。

```bash
#!/bin/bash
REPORT_DATE=$(date +%Y%m%d)
gemini -p "
先週のGA4データを以下の観点で分析し、Markdown形式でレポートを生成してください。
1. 流入元別セッション数（上位10件）
2. ページ別PV数（上位10件）
3. 購入完了数と売上合計
分析結果の末尾に改善提案を3点追加してください。
" > "report_${REPORT_DATE}.md"
echo "レポートを report_${REPORT_DATE}.md に保存しました。"
```

`-p` オプションで非対話モード（プロンプトを引数として渡す形式）での実行が可能です。このスクリプトをcronに登録しておけば、毎週月曜の朝に前週レポートが自動生成される運用が実現できます。

---

## まとめ

本記事では、Gemini CLIをGA4データ分析に活用するための設定と具体的な活用例をご紹介しました。要点を整理します。

- **GEMINI.mdによる役割定義**：プロジェクト情報や分析ルールを事前に設定することで、毎回の指示が簡潔になる
- **正しいテーブル参照**：`ga_session_id` はUNNEST経由、流入元は `collected_traffic_source` を使うことでクエリエラーを防げる
- **ファネル分析や自動レポートへの応用**：SQLの知識が浅くても、Geminiが適切なクエリを生成・実行してくれるため、分析のハードルが下がる

次のアクションとして、まずは `GEMINI.md` を作成し、自社のプロジェクトIDとデータセット名を設定してみてください。設定後に「先週のセッション数を流入元別に出して」と入力するだけで、すぐに動作を確認できます。

GA4×BigQuery×AIの組み合わせは、今後のデータドリブン経営の基盤になります。小さな一歩から始めてみましょう。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
