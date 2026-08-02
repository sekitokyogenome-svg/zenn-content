---
title: "BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した"
emoji: "👤"
type: "idea"
topics: ["bigquery","gemini","sql","googlecloud","ai"]
published: false
---

## はじめに

「BigQueryにデータは蓄積されているのに、SQLが書けないから分析できない」というお悩みを、中小ECサイトの経営者やWebコンサルタントの方からよく伺います。GA4のデータをBigQueryにエクスポートする設定まではできたものの、その先の分析で行き詰まってしまうケースは少なくありません。

2024年以降、Google CloudはBigQueryにGeminiを統合した「Duet AI / Gemini in BigQuery」機能を強化しています。自然言語でSQLを生成してもらえるとあれば、非エンジニアにとっては大きな味方になる可能性があります。

今回は実際にGeminiアシスタントを使い、「SQLがほとんど書けない人でも自力でGA4データを分析できるか」という観点で検証した結果をまとめます。試行錯誤の過程も含めてお伝えするので、同じ悩みをお持ちの方の参考になれば幸いです。

## Geminiアシスタントの基本的な使い方

BigQueryのコンソール画面を開くと、右上または画面中央付近に「Gemini」と書かれたアイコンが表示されています。クリックするとチャット形式でAIに質問できるサイドパネルが開きます。

操作の流れはシンプルです。まずプロジェクトとデータセットを選択し、テーブル名をGeminiに伝えます。そして「どんな分析をしたいか」を日本語で入力すると、SQLの候補を提案してくれます。

ただし注意点があります。Geminiはテーブルの中身を自動的に「読んで」理解するわけではなく、テーブルのスキーマ（列名や型）を参照してSQLを生成します。そのため、GA4のBigQueryエクスポートテーブルのように「ネストされた構造」を持つテーブルでは、そのまま使うと誤ったSQLが生成されることがあります。この点は後ほど詳しく説明します。

:::message
2025年時点では、Geminiの利用にはGoogle CloudプロジェクトでGemini for Google Cloud APIを有効化する必要があります。一定量の無料枠がありますが、利用状況によっては課金が発生する場合もあるため、Cloud ConsoleのBillingページで確認しておくことをおすすめします。
:::

## 実際にやってみた：セッション数の集計

最初の検証として、「先月のセッション数を日別に集計したい」というシンプルなリクエストをGeminiに投げかけました。

Geminiが提案してきたSQLは以下のようなものでした。

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS date,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  date
ORDER BY
  date;
```

ここで重要なポイントは、`ga_session_id`を取得する際に`UNNEST(event_params)`を経由している点です。GA4のBigQueryエクスポートでは、イベントパラメータはネスト構造になっているため、`event_params.ga_session_id`のように直接参照することはできません。Geminiはスキーマを正しく読み取り、適切な記述を提案してくれました。

ただし、テーブル名の`your_project`や`analytics_XXXXXXXXX`の部分は自分のプロジェクトID・データセットIDに書き換える必要があります。この点は非エンジニアの方が戸惑うポイントになりやすいので、「どこを書き換えるか」を追加で質問すると丁寧に教えてくれます。

## 流入元別のセッション分析に挑戦

次に、「流入元ごとのセッション数を集計して、どのチャネルからの流入が多いか確認したい」というリクエストを試しました。

ここで少し壁にぶつかりました。Geminiが最初に提案したSQLでは、流入元の参照方法が誤っており、`traffic_source.medium`という形を使っていました。しかしGA4のBigQueryエクスポートにおいて、手動タグやUTMパラメータ経由の流入は`collected_traffic_source.manual_medium`および`collected_traffic_source.manual_source`として格納されています。

そこで「流入元はcollected_traffic_sourceを使ってください」と追加で指示したところ、正しいSQLを再提案してくれました。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC;
```

このやり取りを通じて感じたのは、「Geminiは指摘すれば修正できるが、GA4特有の仕様までは最初から完璧に把握していない」という点です。知識ゼロの状態でGeminiの提案をそのまま実行すると、エラーになったり意図しない結果になる可能性があります。ある程度「こういう構造になっている」という知識を持っておくと、Geminiをより効果的に活用できます。

## エラーが出たときのGeminiの対応力

SQLを実行したときにエラーが返ってきた場合、そのエラーメッセージをそのままGeminiのチャットに貼り付けて「このエラーを直してください」と伝えると、修正案を提示してくれます。

実際に試したところ、`UNNEST`の使い方が不完全でエラーになったケースでも、エラーメッセージを共有するとすぐに修正されたSQLが戻ってきました。「なぜエラーになったのか」という説明も日本語で付けてくれるため、少しずつ学習しながら進めることができます。

ただし、複雑なネスト構造を含むクエリや、複数テーブルを結合するSQLになると、一度で正しい回答を得られない場合もあります。何度かやり取りをして修正してもらう、というプロセスが必要になることは念頭に置いておいてください。

:::message
エラーメッセージは英語で表示されることが多いですが、そのまま貼り付けて日本語で質問してもGeminiは対応してくれます。コピー&ペーストだけで進められる点は非エンジニアにとって大きなメリットです。
:::

## 非エンジニアが使いこなすための現実的な評価

今回の検証を通じて、GeminiアシスタントによるSQL生成の「できること」と「限界」が見えてきました。

**できること**
- シンプルな集計クエリであれば日本語の指示だけで概ね正しいSQLを生成できる
- エラーメッセージを貼り付けると修正案を提示してくれる
- GA4のネスト構造（UNNEST）を含む書き方も、ある程度対応している
- 日本語でのやり取りが可能なため、英語が苦手な方でも使いやすい

**限界・注意点**
- GA4特有のフィールド仕様（collected_traffic_sourceなど）は追加指示が必要な場合がある
- 複雑な分析（複数イベントの結合、コホート分析など）は一発で正確なSQLが出ないことがある
- テーブル名・プロジェクトIDの置き換えは自分で行う必要がある
- SQLを実行する前に、結果が正しいかどうかを簡単にでも検証する視点が必要

「SQLをまったく書けない人でも自力で分析できるか」という問いに対する答えは、「シンプルな分析であれば、ある程度は可能」というのが正直なところです。ただし、GAデータの構造についての最低限の理解と、Geminiとの対話を繰り返しながら修正していく根気が必要です。完全に手放しで任せられるツールとしてではなく、「SQLの下書きを作ってくれるアシスタント」として活用するのが現実的な使い方だと感じました。

## まとめ

BigQueryのGeminiアシスタントは、非エンジニアがSQL分析に踏み出す際の心理的なハードルを大きく下げてくれるツールです。日本語で話しかけるだけでSQLの候補が出てくるという体験は、「SQLを学ばなければ分析できない」というこれまでの常識を変えつつあります。

一方で、GA4のBigQueryエクスポートデータの構造（ネスト・collected_traffic_source・UNNEST経由のパラメータ取得など）は独特であり、Geminiの提案をそのまま実行すると誤った結果やエラーになるケースもあります。こうした仕様をあらかじめ把握した上でGeminiを使うと、やり取りの効率が格段に上がります。

まずはシンプルな集計（日別セッション数・流入元別集計など）からGeminiと一緒に試してみることをおすすめします。小さな成功体験を積み重ねることで、自社データの分析を自走できる環境が整っていきます。

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
