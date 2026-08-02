---
title: "Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計"
emoji: "🔍"
type: "tech"
topics: ["claude","bigquery","googleanalytics","ai","ec"]
published: false
---

## はじめに

「先週のセッション数が突然落ちているけど、原因がわからない」「コンバージョン率が急上昇しているのに、何が要因かを特定するのに半日かかってしまった」——そのような経験はないでしょうか。

GA4のデータを毎日チェックする習慣があっても、異常値を発見した後の「なぜ起きたのか」を突き止める作業は、思った以上に手間と時間がかかります。特に中小ECを運営されている方の多くは、アナリスト専任のスタッフを置くのが難しく、経営者やコンサルタントが自らデータを追いかけるケースも少なくありません。

この記事では、Claude Codeを活用して、GA4のBigQueryエクスポートデータから異常値を自動検知し、さらにその原因仮説まで出力させるプロンプトの設計方法をご紹介します。SQLを含む部分もありますが、コピーして使えるように整理していますので、BigQueryに慣れていない方も参考にしていただけます。

---

## GA4 × BigQueryで異常検知が必要な理由

GA4の管理画面にも比較機能やアラート機能は存在しますが、細かい粒度での異常検知や複数指標の同時監視には限界があります。BigQueryにGA4データをエクスポートすることで、以下のような柔軟な分析が可能になります。

- 流入元別・デバイス別・ランディングページ別など多次元での異常検知
- 日別・時間帯別・セグメント別での前週比・前月比の自動算出
- コンバージョン率だけでなく、カート追加率や離脱率など独自指標の監視

こうした分析を毎回手動でSQLを書いて実行するのは非効率です。Claude Codeにプロンプトを渡して「SQLの生成 → BigQueryへの問い合わせ → 異常値の判定 → 原因仮説の出力」まで自動化することで、日次のモニタリング業務を大幅に効率化できます。

---

## 異常値を取得するBigQueryクエリの設計

まず、Claude Codeに渡す前提となるSQLを設計します。GA4のBigQueryエクスポートテーブルでは、セッションIDやイベントパラメータはネストされた形式で格納されているため、`UNNEST` を使った展開が必要です。

以下は、日別セッション数と購入コンバージョン数を流入元（medium/source）別に集計するクエリの例です。

```sql
WITH session_base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    user_pseudo_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
sessions AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),
purchases AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS conversions
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)
SELECT
  s.date,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(p.conversions, 0) AS conversions,
  SAFE_DIVIDE(COALESCE(p.conversions, 0), s.sessions) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date AND s.medium = p.medium AND s.source = p.source
ORDER BY s.date DESC, s.sessions DESC
```

`ga_session_id` は `UNNEST(event_params)` 経由で取得している点と、流入元の特定に `collected_traffic_source.manual_medium` / `manual_source` を使用している点がポイントです。このSQLをCSV等に出力しておくことで、次のステップでClaude Codeへの入力データとして活用できます。

---

## Claude Codeへ渡すプロンプトの設計

取得したCSVデータをClaude Codeに渡す際のプロンプト設計が、精度の高い異常検知と仮説生成のカギとなります。以下のテンプレートを参考にしてください。

```
以下はGA4のBigQueryエクスポートデータから取得した、過去30日間の流入元別セッション数・コンバージョン数・CVRの日次データです。

[CSVデータをここに貼り付け]

上記データを分析して、以下の手順で回答してください。

1. 直近7日間（最新7行）と、その前の7日間（8〜14日前）を比較し、セッション数・CVRにおいて±20%以上の変化がある流入元・日付の組み合わせをすべて抽出してください。

2. 抽出された異常値について、それぞれ以下の観点で原因仮説を3つずつ挙げてください。
   - 広告・プロモーション要因（キャンペーン開始・終了、入札変更など）
   - サイト内要因（ページ改修、フォーム変更、速度低下など）
   - 外部要因（季節性、競合、検索アルゴリズム変動など）

3. 各仮説の確認方法（GA4管理画面での確認手順、Search Consoleの確認ポイント等）も合わせて提示してください。

出力形式はMarkdownの表と箇条書きを使い、非エンジニアの経営者にも伝わるよう平易な言葉で説明してください。
```

このプロンプトのポイントは、**判定基準（±20%）を数値で明示**していること、**仮説を3カテゴリに分けることで網羅性を確保**していること、そして**確認方法まで出力させること**で次のアクションに直結させている点です。

---

## 出力結果の活用と運用フロー

Claude Codeからの出力を受け取った後の運用フローも設計しておくことで、継続的なモニタリング体制を構築できます。

### 週次レポートへの組み込み

Claude Codeの出力をSlackやメールに転送する仕組みを組み合わせることで、毎週月曜の朝に先週の異常値サマリーを受け取る運用も実現できます。BigQueryのスケジュールクエリ → Google Cloud Storage(CSV出力) → Pythonスクリプト → Claude API呼び出し → Slack通知、という自動化パイプラインが一例です。

```python
import anthropic
import csv

def load_csv(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()

def analyze_anomaly(csv_text: str) -> str:
    client = anthropic.Anthropic()
    prompt = f"""
以下はGA4の流入元別日次データです。
直近7日と前の7日を比較し、±20%以上の変動がある行を抽出して、
原因仮説を広告要因・サイト内要因・外部要因の3軸で各3つ提示してください。

{csv_text}
"""
    message = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text

if __name__ == "__main__":
    csv_text = load_csv("/path/to/ga4_export.csv")
    result = analyze_anomaly(csv_text)
    print(result)
```

### 仮説の検証優先順位のつけ方

Claude Codeが出力した仮説をそのまま全件追いかけるのは非効率です。以下の観点で優先順位をつけると実践しやすくなります。

- **変動幅が大きいものを優先**：±20%を基準にしても、±50%以上の変動は最優先で調査
- **セッション数が多い流入元を優先**：影響規模が大きいほど売上インパクトも大きい
- **CVRとセッション数が同時に変動しているケース**：複合的な問題である可能性が高く、早期対応が重要

---

## プロンプト設計で陥りやすい落とし穴

Claude Codeへのプロンプト設計で、実際の運用でよく見られる課題をいくつかご紹介します。

**データが多すぎてコンテキストを超える問題**
30日分の流入元別データをそのまま貼り付けると、トークン数の上限に達することがあります。対策として、あらかじめSQLで上位10流入元に絞るか、集計粒度を週次に変えてから渡すと安定します。

**判定基準を曖昧にすると仮説が拡散する**
「異常値を見つけてください」だけでは、Claude Codeが何を異常とみなすか定まらず、出力がばらつきます。「±20%以上」「絶対値で100セッション以上の変化」など、数値基準を明示することで出力の一貫性が高まります。

**仮説の出力のみで終わらせない**
原因仮説が出ても、「次に何をするか」がプロンプトに含まれていないと、アクションに繋がりにくいです。前述のように確認方法を一緒に出力させることが、実務での活用率を高めるコツです。

:::message
プロンプトの改善はPDCAを繰り返すことが大切です。最初から完璧なプロンプトを目指すより、実際に使いながら「この仮説は的外れだった」「この観点が抜けていた」と気づいた点を少しずつ追記していく進め方が現実的です。
:::

---

## まとめ

本記事では、Claude CodeとGA4のBigQueryエクスポートデータを組み合わせて、異常値の検知から原因仮説の出力までを自動化するプロンプト設計についてご紹介しました。

要点を整理すると以下の通りです。

- GA4のBigQueryデータでは `UNNEST(event_params)` でのセッションID取得と `collected_traffic_source` での流入元取得が基本
- プロンプトには判定基準・仮説のカテゴリ・確認方法の3点を明示することで出力精度が上がる
- Pythonスクリプトを使えばBigQuery出力 → Claude API呼び出しまで自動化できる
- 仮説は全件追いかけず、変動幅・影響規模を基準に優先順位をつけて対応する

まずは手元のGA4データで30日分のCSVを取得し、本記事のプロンプトテンプレートをそのまま試してみることをお勧めします。データと向き合う時間が大幅に短縮され、「異常を発見して終わり」から「原因を仮説立てて次の一手を打つ」サイクルへと移行していただけるはずです。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
