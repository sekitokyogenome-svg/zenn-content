---
title: "ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法"
emoji: "💬"
type: "tech"
topics: ["bigquery","ec","googlecloud","sql","ai"]
published: false
---

## はじめに

「返品・交換の問い合わせが多いのはわかっているけど、どの商品が原因なのかデータで把握できていない」——そんな悩みを抱えているECサイト運営者の方は少なくないのではないでしょうか。

CS（カスタマーサポート）への問い合わせは、お客様の生の声が詰まった貴重なデータです。しかし多くの場合、問い合わせ管理ツール・メール・チャットツールといった複数の場所に分散してしまい、集計や分析に手間がかかります。結果として「なんとなく多い気がする」という定性的な判断のみに留まり、商品改善に結びつけられないケースが多いです。

本記事では、EC事業者のCS問い合わせデータをBigQueryに集約し、GA4の行動データと組み合わせて商品改善に活かす方法を、非エンジニアの方にもわかりやすく解説します。ツールの構成から実際のSQL例まで、ステップごとにご説明します。

---

## CS問い合わせデータをBigQueryに集約する仕組み

まず全体の流れを把握しておきましょう。大まかには次のような構成になります。

1. CS対応ツール（Zendesk・Re:lationなど）からデータをエクスポートまたはAPIで取得
2. Google Cloud Storage（GCS）やCloud Functionsを経由してBigQueryへ格納
3. GA4のBigQueryエクスポートデータと結合して分析

小規模なEC事業者であれば、まずCSVエクスポート＋BigQueryへの手動インポートから始めるだけでも十分です。ZendeskやFreshdeskなどの主要CSツールは、チケットデータをCSV形式でエクスポートする機能を持っています。

BigQueryへのインポートはGoogle Cloud Consoleの画面操作のみで完結できるため、SQLが書けなくても始められます。インポートするCSVに含めておくと後々便利なカラムとして、「問い合わせカテゴリ」「対象商品コード（SKU）」「チャネル（メール・チャット・電話）」「解決日時」などが挙げられます。

:::message
エクスポートするCSVのカラム名は英語（スネークケース）に統一しておくと、BigQueryのテーブル設計がシンプルになります。例：`ticket_id`、`product_sku`、`category`、`created_at`
:::

---

## 問い合わせカテゴリ別・商品別の集計SQL

BigQueryにCSデータを格納したら、まず「どの商品にどんな問い合わせが多いか」を集計してみましょう。以下は、問い合わせカテゴリと商品SKUで件数を集計するシンプルなクエリです。

```sql
SELECT
  product_sku,
  category,
  COUNT(*) AS inquiry_count,
  COUNTIF(LOWER(category) LIKE '%return%' OR LOWER(category) LIKE '%返品%') AS return_count,
  COUNTIF(LOWER(category) LIKE '%defect%' OR LOWER(category) LIKE '%不良%') AS defect_count
FROM
  `your_project.cs_dataset.tickets`
WHERE
  DATE(created_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
GROUP BY
  product_sku,
  category
ORDER BY
  inquiry_count DESC
LIMIT 50
```

このクエリを定期的に実行してLooker Studioでグラフ化するだけでも、「問い合わせが集中している商品」が一目でわかるようになります。

さらに踏み込みたい場合は、GA4のBigQueryエクスポートデータと結合し、購入後にCS問い合わせを行ったユーザーの行動パターンを追うことも可能です。

---

## GA4データと組み合わせて購入〜問い合わせの流れを把握する

GA4のBigQueryエクスポートには、ユーザーの行動ログが`events_YYYYMMDD`テーブルとして格納されています。これとCSデータを組み合わせることで、「購入後何日以内に問い合わせが発生しているか」「どの流入チャネルからの購入者に問い合わせが多いか」といった深い分析が可能になります。

以下は、GA4の購入イベントと流入元を取得するクエリの例です。`ga_session_id`はイベントパラメータのネスト構造内に格納されているため、`UNNEST`を使って展開する必要があります。

```sql
SELECT
  user_pseudo_id,
  event_date,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'transaction_id'
  ) AS transaction_id
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
```

このクエリで取得した`transaction_id`を、CSデータ側の注文番号と突合することで、「購入から問い合わせまでの経路」が見えてきます。たとえばSNS広告経由の購入者に返品問い合わせが集中しているなら、商品説明や広告クリエイティブの見直しを検討するきっかけになります。

:::message
GA4の`collected_traffic_source`カラムはセッションスコープのデータを保持しており、イベント単位の`traffic_source`よりも広告経由の流入を正確に把握できます。購入イベントの分析には`collected_traffic_source`の使用を推奨します。
:::

---

## AIを活用して問い合わせ本文を自動分類する

問い合わせデータの中でも、自由記述のテキスト（問い合わせ本文）は扱いにくいと感じる方が多いと思います。手作業でカテゴリ分けするのは時間がかかりますし、担当者によって分類基準がばらつくこともあります。

そこで活用できるのが、BigQueryとVertex AIを組み合わせたテキスト分類です。BigQueryのML機能（BQML）やVertex AI APIを呼び出すことで、問い合わせ本文を自動的にカテゴリ分けしたり、ポジティブ・ネガティブのセンチメント判定を行ったりすることができます。

シンプルな実装例として、Cloud FunctionsからGemini APIを呼び出して分類ラベルをBigQueryに書き戻す方法があります。

```python
import vertexai
from vertexai.generative_models import GenerativeModel

def classify_inquiry(inquiry_text: str) -> str:
    vertexai.init(project="your-project-id", location="asia-northeast1")
    model = GenerativeModel("gemini-1.5-flash")

    prompt = f"""
以下のECサイトへの問い合わせ文を、次のカテゴリのいずれか1つに分類してください。
カテゴリ: 返品・交換, 配送遅延, 商品不良, サイズ・仕様確認, その他
問い合わせ: {inquiry_text}
カテゴリ名のみ返答してください。
"""
    response = model.generate_content(prompt)
    return response.text.strip()
```

このような自動分類を週次でバッチ実行するだけで、「先月は商品不良の問い合わせが前月比で増加している」といった傾向を数値で把握できるようになります。分類結果をBigQueryに蓄積しておけば、Looker Studioでのダッシュボード化もスムーズに行えます。

---

## 分析結果を商品改善に落とし込むフロー

データを集めて分析するだけでは、実際の改善には結びつきません。重要なのは、分析結果を商品改善のアクションにどう繋げるかです。

以下のようなフローを設けることで、CS問い合わせ分析を継続的な改善サイクルに組み込むことができます。

**週次レビュー（所要時間: 15〜30分）**
- 前週の問い合わせ件数を商品別・カテゴリ別に確認
- 急増している商品・カテゴリがあれば原因を調査

**月次アクション**
- 問い合わせ上位の商品について、商品説明文・画像・サイズ表記などを見直す
- 「よくある質問（FAQ）」ページを問い合わせ内容に基づいて更新する
- 返品率の高い商品については、仕入れ・品質管理の担当者へフィードバックを共有する

**四半期レビュー**
- 改善施策を実施した商品の問い合わせ件数が減少しているかを検証
- 流入チャネル別の問い合わせ傾向を確認し、広告運用チームと情報共有する

このサイクルを回すことで、CS担当者の対応工数削減と顧客満足度の向上を同時に目指すことができます。問い合わせデータは「コストセンターの記録」ではなく、「商品改善のヒントが詰まったリソース」として活用できます。

---

## まとめ

本記事では、EC事業者のCS問い合わせデータをBigQueryに集約し、商品改善に活かすための方法を解説しました。要点を整理します。

- **第一歩はCSVエクスポートとBigQueryへの手動インポート**から始めると、ハードルが低くてすぐに動き出せます
- **GA4データとの結合**により、流入チャネル別の問い合わせ傾向など、より深いインサイトが得られます
- **AI（Gemini API）を活用した自動分類**で、テキストデータの分析工数を大幅に削減できます
- **週次・月次の改善サイクル**に組み込むことで、データ分析が実際のアクションに繋がります

データ基盤の構築は「一度整えれば、あとは継続的に活用できる」ものです。最初の設計と設定に少し時間をかけることで、日々の判断をデータに基づいて行えるようになります。ぜひ自社のCS問い合わせデータを見直すきっかけにしてみてください。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
