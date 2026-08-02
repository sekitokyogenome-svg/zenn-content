---
title: "Claude Codeで競合ECサイトのSEO戦略をGA4×Search Consoleデータから逆算する"
emoji: "🔎"
type: "tech"
topics: ["claude","bigquery","googleanalytics","seo","ec"]
published: false
---

## はじめに

「競合サイトはなぜ検索上位を取り続けているのか」——そう感じながら、自社ECサイトの集客に頭を悩ませている方は少なくないはずです。広告費を増やしても限界があり、SEO対策は地道な作業の連続で、成果が見えにくいと感じているケースも多いのではないでしょうか。

実は、Google Search ConsoleとGA4（Google Analytics 4）のデータを組み合わせると、競合サイトが狙っているキーワード群や、どのような検索意図を持つユーザーを集めているかをある程度推定できます。さらにBigQueryと連携させることで、大量のデータを一括処理し、自社のSEO戦略立案に役立てることができます。

本記事では、Claude Codeを活用してGA4とSearch Consoleのデータを分析するSQL・Pythonコードを生成し、競合ECサイトのSEO戦略を逆算するワークフローを解説します。エンジニアではない方でも実践できるよう、各ステップをできるだけ丁寧に説明します。

---

## GA4×Search ConsoleをBigQueryで統合する準備

分析を始める前に、データ基盤を整えておく必要があります。GA4のデータはBigQueryへのエクスポート機能を使って連携でき、Search ConsoleのデータはLooker Studioや手動CSVエクスポート、あるいはSearch Console APIを通じてBigQueryに取り込めます。

まず、GA4 BigQueryエクスポートが有効になっているか確認してください。GA4の管理画面から「BigQueryのリンク」を設定すると、Googleが管理するBigQueryプロジェクトに日次でイベントデータが蓄積されます。テーブル名は `events_YYYYMMDD` 形式で、分析期間に合わせてワイルドカード（`events_*`）を使って複数日をまとめてクエリできます。

次に、Search ConsoleのデータはCSVでエクスポートしてBigQueryに手動でアップロードするか、Search Console APIを呼び出してデータを収集するスクリプトを用意します。Claude Codeにプロンプトで依頼すれば、APIを叩くPythonスクリプトの雛形も生成してもらえます。

:::message
GA4のBigQueryエクスポートは無料枠で利用できますが、クエリ量が増えると課金が発生します。初めて利用する際はBigQueryの料金体系（クエリ処理量1TB当たり$5）を事前に確認しておくことをおすすめします。
:::

---

## Search Consoleデータから検索キーワードの傾向を把握するSQL

Search Consoleのデータには、「どのキーワードで何回表示され、何回クリックされたか」という情報が含まれています。これを分析することで、自社サイトが上位表示できていないにもかかわらず多く表示されているキーワード、いわゆる「伸びしろキーワード」を発見できます。

以下は、BigQueryにアップロードしたSearch Consoleのエクスポートデータを集計するSQLの例です。

```sql
-- Search Console データ集計（クリック率の低いインプレッション多数キーワードを抽出）
SELECT
  query,
  SUM(impressions)                          AS total_impressions,
  SUM(clicks)                               AS total_clicks,
  ROUND(SUM(clicks) / SUM(impressions) * 100, 2) AS ctr_pct,
  ROUND(AVG(position), 1)                   AS avg_position
FROM
  `your_project.search_console_dataset.searchdata_site_impression`
WHERE
  data_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
  AND impressions > 100
GROUP BY
  query
HAVING
  ctr_pct < 2.0            -- CTR 2%未満に絞る
  AND avg_position <= 20   -- 検索結果2ページ目以内
ORDER BY
  total_impressions DESC
LIMIT 100;
```

このクエリで得られる「表示回数は多いがクリック率が低い」キーワードは、タイトルやメタディスクリプションを改善することで流入増が見込めます。Claude Codeにこの結果を渡し、「各キーワードに対してページタイトルの改善案を提案してほしい」と依頼するだけで、修正候補のリストを自動生成できます。

---

## GA4 BigQueryデータで流入セッションとコンバージョンを紐づけるSQL

Search Consoleで「狙うべきキーワード」が分かったら、次はGA4データを使って「そのキーワード経由で訪れたユーザーが実際に購入（コンバージョン）しているか」を確認します。

GA4のBigQueryエクスポートでは、`ga_session_id` のような特定のパラメータは `event_params` 配列の中に格納されています。直接カラムとして参照することはできないため、`UNNEST` を使って展開する必要があります。また、流入元の情報は `collected_traffic_source` オブジェクトから取得します。

```sql
-- GA4: オーガニック流入セッションのコンバージョン率集計
WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params を UNNEST して取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')              AS session_id,
    collected_traffic_source.manual_medium     AS medium,
    collected_traffic_source.manual_source     AS source,
    event_name
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    medium,
    source,
    COUNTIF(event_name = 'purchase') AS purchase_count
  FROM session_params
  WHERE medium = 'organic'   -- オーガニック検索のみ
  GROUP BY 1, 2, 3, 4
)
SELECT
  source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions,
  SUM(purchase_count)                                                  AS purchases,
  ROUND(SUM(purchase_count) /
        COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY source
ORDER BY sessions DESC;
```

このクエリで、どの検索エンジン・どの流入元からのセッションが購買につながっているかを把握できます。Google経由のオーガニック流入のCVRが他チャネルと比べて著しく低い場合、ランディングページの内容とユーザーの検索意図がずれている可能性を示唆します。

:::message
`collected_traffic_source.manual_medium` および `manual_source` は、UTMパラメータが付いている場合にその値が入ります。UTMなしのオーガニック流入の場合、Googleがセッションスコープで付与したデータ（`session_traffic_source_last_click` など）と合わせて確認すると精度が上がります。
:::

---

## Claude Codeで逆算レポートを自動生成するワークフロー

ここまでのSQLを手動で実行・確認するだけでも十分な示唆が得られますが、Claude Codeを使えばこの一連の分析を半自動化できます。

具体的なワークフローは以下の通りです。

```bash
# 1. BigQueryのクエリ結果をCSVでエクスポート
bq query --use_legacy_sql=false \
  --format=csv \
  --max_rows=5000 \
  'SELECT ...' > /tmp/seo_analysis.csv

# 2. Claude Code に渡して解釈・レポート生成を依頼
claude "以下のCSVはGA4とSearch ConsoleをBigQueryで集計した結果です。
競合ECサイトとの差分を踏まえ、優先度の高いSEO改善施策を
3〜5項目で日本語でまとめてください。
$(cat /tmp/seo_analysis.csv)"
```

Claude Codeはコードの生成だけでなく、分析結果の自然言語での解釈も得意としています。BigQueryから出力したCSVをそのまま貼り付けて「どの施策を優先すべきか」を問うだけで、担当者向けのサマリーを生成してくれます。

また、Python環境がある場合は以下のようにして、定期的に分析レポートをSlackやメールへ送信する自動化パイプラインを構築することもできます。

```python
import subprocess
import json

# Claude Code CLI をPythonから呼び出す例
def run_claude_analysis(csv_data: str, prompt: str) -> str:
    full_prompt = f"{prompt}\n\n{csv_data}"
    result = subprocess.run(
        ["claude", "-p", full_prompt],
        capture_output=True,
        text=True,
        timeout=120
    )
    return result.stdout

if __name__ == "__main__":
    with open("/tmp/seo_analysis.csv", "r", encoding="utf-8") as f:
        csv_content = f.read()

    analysis_prompt = (
        "以下のCSVデータを分析し、オーガニック流入を伸ばすための"
        "SEOアクションプランを優先度順にリストアップしてください。"
    )
    report = run_claude_analysis(csv_content, analysis_prompt)
    print(report)
```

このスクリプトをCloud Run JobsやGCP Cloud Schedulerと組み合わせると、月次・週次で自動レポートを生成・配信する仕組みを作れます。

---

## まとめ

本記事では、GA4とSearch ConsoleのデータをBigQueryで統合し、Claude Codeを活用してSEO戦略を逆算するワークフローを解説しました。要点を整理します。

- **Search ConsoleのCTR分析**によって、「表示されているが選ばれていない」キーワードを発見し、タイトル・メタディスクリプションの改善につなげられます。
- **GA4 BigQueryのSQL分析**では `UNNEST(event_params)` でセッションIDを取得し、`collected_traffic_source.manual_medium` / `manual_source` で流入元を特定することで、オーガニックセッションのコンバージョン状況を把握できます。
- **Claude Codeへの分析依頼**は、CSVを渡してテキストプロンプトを添えるだけで完結します。エンジニアリングの深い知識がなくても、分析の自動化と解釈の効率化が実現できます。

次のアクションとしては、まずGA4のBigQueryエクスポートを有効化し、過去90日分のデータでSearch Consoleとのクロス分析を試してみてください。小さな改善サイクルを回し続けることが、中長期的な検索流入の安定につながります。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
