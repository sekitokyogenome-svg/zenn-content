---
title: "Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術"
emoji: "📋"
type: "tech"
topics: ["claude","bigquery","ai","ec","datanalysis"]
published: true
---

## はじめに

月次のKPIレポートを作成するたびに、「数字を並べることはできても、そこから何を言えばよいのかが難しい」と感じている方は多いのではないでしょうか。セッション数が前月比でどう変化したか、CVRが上下した原因は何か——そういった「考察」の部分こそが、経営判断や施策立案に直結する重要なアウトプットです。

しかし現実には、データを集計してグラフにまとめるだけで時間を取られてしまい、考察を深める余裕がなくなってしまうことも少なくありません。数字を「読む」作業が形骸化し、レポートが単なる記録になってしまうケースをよく目にします。

本記事では、GA4のデータをBigQueryで集計し、その結果をClaude Codeに渡して月次KPIの考察文まで生成させるプロンプト設計の考え方をご紹介します。エンジニアでなくても応用しやすい形で解説しますので、EC運営者やWebコンサルタントの方にも参考にしていただけます。

---

## 月次KPIレポートの「考察」とはどういうものか

KPIレポートにおける「考察」とは、単に数値の増減を述べるのではなく、「なぜそうなったか」「何が影響しているか」「次にどう動くべきか」という解釈と提言を含むものです。たとえば、「先月と比べてオーガニック流入が15%減少した」という事実に対して、「検索順位の変動が背景にある可能性があり、コンテンツの見直しを検討する余地がある」という解釈を加えることで、レポートは初めて意思決定の材料になります。

この考察作業をClaude Codeに担わせるためには、AIが正しく文脈を読めるよう、データの提示方法とプロンプトの構造の両方を整える必要があります。「数字だけ渡せば賢く考えてくれる」というわけではなく、業種・目標・前提条件をきちんと伝えることが出力品質を左右します。

---

## BigQueryでGA4データを集計するSQL設計

考察の素材となるデータを正確に準備するために、まずBigQueryでの集計クエリを整えます。GA4のBigQueryエクスポートでは、`ga_session_id`をはじめとするセッション関連のパラメータは`event_params`の配列に格納されているため、`UNNEST`を使って展開する必要があります。また、流入元の判定には`collected_traffic_source.manual_medium`と`collected_traffic_source.manual_source`を参照します。

以下は、月次の流入元別セッション数とCV数を集計するクエリの例です。

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

sessions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),

conversions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(*) AS cv_count
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)

SELECT
  s.month,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(c.cv_count, 0) AS cv_count,
  ROUND(SAFE_DIVIDE(COALESCE(c.cv_count, 0), s.sessions) * 100, 2) AS cvr
FROM sessions s
LEFT JOIN conversions c
  ON s.month = c.month AND s.medium = c.medium AND s.source = c.source
ORDER BY s.sessions DESC
```

このクエリを前月・当月の2ヶ月分実行し、結果をCSVまたはテキスト形式にエクスポートしておくと、次のステップでClaude Codeに渡しやすくなります。

:::message
`your_project.analytics_XXXXXXX` の部分は実際のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。テーブル名のサフィックスはデータ取得期間に合わせて変更します。
:::

---

## Claude Codeに渡すプロンプトの設計術

BigQueryで集計したデータをClaude Codeに渡す際、プロンプトの構造が考察の深さを大きく左右します。ポイントは次の3点です。

**① 背景・前提条件を最初に書く**

AIに業種・サービスの特性・今月の施策などを事前に伝えることで、的外れな考察を減らすことができます。

**② データは構造化して貼り付ける**

Markdownのテーブル形式やCSV形式でデータを整理してから渡すと、Claude Codeが数値を正確に読み取りやすくなります。

**③ 出力フォーマットを指定する**

「考察を3段落で」「施策提案を箇条書きで」のように出力の形式を指定しておくと、実際のレポートにそのまま貼り付けやすい形で返ってきます。

以下にプロンプトのテンプレート例を示します。

```text
あなたはECサイトのアナリストです。以下のKPIデータをもとに、月次レポート用の考察を作成してください。

【サービス概要】
- 業種: アパレルEC（30〜50代女性向け）
- 今月の施策: メールマガジン配信強化、Instagram広告テスト実施

【KPIデータ（流入元別・前月比較）】
| medium | source | 先月sessions | 今月sessions | 先月CV | 今月CV | 先月CVR | 今月CVR |
|--------|--------|------------|------------|-------|-------|--------|--------|
| organic | google | 3200 | 2750 | 64 | 58 | 2.00% | 2.11% |
| cpc | google | 890 | 1050 | 22 | 31 | 2.47% | 2.95% |
| email | (none) | 410 | 680 | 18 | 34 | 4.39% | 5.00% |
| social | instagram | 120 | 310 | 3 | 9 | 2.50% | 2.90% |

【出力形式】
1. 全体サマリー（2〜3文）
2. チャネル別の変化と要因の考察（各チャネル2〜4文）
3. 来月に向けた施策提案（箇条書き3〜5項目）
```

このようにプロンプトを構造化することで、Claude Codeは「メールマガジン強化の効果が数字に表れている」「オーガニックのセッション減少は施策起因ではなく外部要因の可能性がある」といった文脈に沿った考察を生成しやすくなります。

---

## 出力精度をさらに高めるための工夫

Claude Codeの出力をより業務に使いやすくするための工夫をいくつか紹介します。

**目標値・ベンチマークを一緒に渡す**

「CVRの業界平均は1.5〜2.0%程度」「今月の売上目標は前月比110%」といった比較軸を加えると、考察の具体性が増します。単なる増減の記述から、「目標に対してどうだったか」という評価軸が加わります。

**「異常値」を明示する**

データの中で特に目立つ変化（急増・急落）があれば、プロンプト内に「この数値は特に注目してほしい」と明記しておくと、考察の優先度がより適切になります。

**出力後に追加質問で深掘りする**

最初の出力に対して「なぜメール経由のCVRが高い傾向があるか、EC一般論も含めて補足してください」のように追加プロンプトを投げることで、考察をさらに充実させることができます。一問一答でなく、対話的に使うのが効果的です。

:::message
Claude Codeの出力はあくまで「たたき台」として活用し、実際のレポートに使用する際は数値の正確性と文脈の妥当性をご自身で確認することをお勧めします。
:::

---

## まとめ

本記事では、月次KPIレポートの考察部分をClaude Codeに生成させるための設計アプローチをご紹介しました。要点を整理すると次の通りです。

- **データ準備**: BigQueryでGA4データを集計する際は`UNNEST(event_params)`でセッションIDを取得し、流入元は`collected_traffic_source`を参照する
- **プロンプト設計**: 背景・データ・出力形式の3要素をセットで渡すことが考察品質の鍵になる
- **活用方法**: 出力はたたき台として使い、追加質問で深掘りしながら仕上げていく

月次レポートの「数字を並べるだけ」から脱却し、考察まで含めた意思決定に役立つレポートへと進化させるための一助となれば幸いです。まずは1チャネルのデータだけに絞って試してみるところから始めてみてください。

## 関連記事

- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】](https://zenn.dev/web_benriya/articles/gemini-bigquery-nl-sql-guide-2026)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
