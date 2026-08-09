---
title: "NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する"
emoji: "📓"
type: "tech"
topics: ["bigquery","googleanalytics","ai","googlecloud","datanalysis"]
published: false
---

## はじめに

「GA4のレポートを見てはいるものの、何をどう読めばいいのかよくわからない」「BigQueryにデータを飛ばしてはみたけど、SQLが書けないので活用できていない」——そんなお悩みをお持ちではないでしょうか。

GA4とBigQueryの連携は、データ分析の可能性を大きく広げる強力な組み合わせです。しかし、BigQueryのデータを実際に活用しようとすると、SQLの知識が必要になり、非エンジニアには高いハードルに感じられることが多いです。

そこで今回ご紹介するのが、GoogleのAIノートツール「NotebookLM」を活用したアプローチです。BigQueryからエクスポートしたCSVデータをNotebookLMに読み込ませることで、SQLを書かなくても自然言語でデータに質問しながら分析を進められます。中小ECサイトの経営者やWebコンサルタントの方にも実践しやすい方法ですので、ぜひ最後までご覧ください。

## GA4データをBigQueryからCSVに取り出す

まず、BigQueryに蓄積されたGA4データを分析用に取り出します。Google Cloudのコンソールからクエリを実行し、結果をCSVとしてダウンロードするか、Google ドライブにエクスポートします。

下記はECサイトでよく使われる「流入元別のセッション数と購入件数」を集計するクエリの例です。

```sql
SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
  , UNNEST(collected_traffic_source) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 100;
```

:::message
`your_project.analytics_XXXXXXXXX` の部分はご自身のGCPプロジェクトID・BigQueryデータセット名に置き換えてください。`_TABLE_SUFFIX`で対象期間を絞ることで、クエリコストを抑えられます。
:::

クエリ結果が表示されたら、BigQueryのUI右上にある「保存」→「CSVをダウンロード」を選択します。このCSVファイルが次のステップで使うデータになります。

## NotebookLMにCSVをアップロードして対話分析を始める

NotebookLM（https://notebooklm.google.com）はGoogleが提供するAIノートサービスです。PDFやドキュメント、CSVなどのファイルをソースとして登録し、その内容に基づいてAIと対話できます。ハルシネーション（事実でない情報の生成）を抑える設計になっており、登録したデータの範囲内で回答してくれる点が特徴です。

手順は以下のとおりです。

1. NotebookLMにアクセスし、新しいノートブックを作成する
2. 「ソースを追加」からダウンロードしたCSVファイルをアップロードする
3. アップロード完了後、チャット欄から質問を入力する

たとえば次のような質問が有効です。

- 「流入元ごとの購入件数を多い順に教えてください」
- 「Organic Searchと比べてPaid Searchの購入転換率はどうですか？」
- 「セッション数が多いのに購入が少ない流入元はどれですか？改善のヒントはありますか？」

NotebookLMはCSVのデータを読み取ったうえで回答するため、数字の根拠が明確です。「ソースを見る」ボタンで元データの該当行を確認することもできます。

## 複数のクエリ結果を組み合わせてより深い分析を行う

NotebookLMは複数のソースを同一ノートブックに登録できます。たとえば「流入元別集計」のCSVと「商品カテゴリ別購入数」のCSVを両方アップロードし、横断的な質問をすることが可能です。

下記は商品カテゴリ別の購入数を取り出すクエリの例です。

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_events,
  SUM(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'value')
  ) AS total_revenue
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  item_category
ORDER BY
  purchase_events DESC;
```

このCSVも追加でアップロードすることで、「SNS流入のユーザーはどのカテゴリをよく購入しているか」のような複合的な質問にも対応できるようになります。ただし、BigQuery上で結合したクエリ結果を1つのCSVにまとめてからNotebookLMに渡す方が、回答の精度が上がりやすいです。

## 分析結果をレポートとして整理する

NotebookLMには「ノート」機能があり、AIとの対話で得た洞察を手動でメモとして保存できます。また「スタジオ」機能を使うと、登録したソースから自動的にサマリーや FAQ、タイムラインなどの整理されたドキュメントを生成することが可能です。

分析で得られた主要な発見をNotebookLMのノートにまとめておくと、毎月の定期レポートや社内共有用の資料作成に役立ちます。Google ドキュメントへのエクスポートにも対応しているため、そのまま報告書として仕上げることもできます。

:::message
NotebookLMでの分析は、あくまでアップロードしたCSVの範囲内に限られます。期間やフィルタ条件の異なるデータを分析したい場合は、BigQueryで別途クエリを実行し、新しいCSVをソースに追加する形で運用するとよいでしょう。
:::

## まとめ

本記事では、GA4のBigQueryエクスポートデータをNotebookLMと組み合わせて対話的に分析する方法をご紹介しました。要点を整理します。

- **BigQueryでCSVを取り出す**: 流入元や商品カテゴリなど、分析したい切り口でSQLを実行し、結果をCSVでダウンロードする
- **NotebookLMにアップロード**: ソースとして登録し、自然言語で質問しながら分析を進める
- **複数ソースの組み合わせ**: 複数のCSVを登録することで横断的な質問が可能になる
- **ノート機能で整理**: 気づきをメモし、レポートとして活用する

SQLに不慣れな方でも、まずBigQueryのサンプルクエリを参考にCSVを取り出すところから始めることで、NotebookLMによる対話分析を体験できます。データに触れる機会を増やすことで、徐々に自社に合ったKPIやレポートの形が見えてくるはずです。ぜひ一歩ずつ試してみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
