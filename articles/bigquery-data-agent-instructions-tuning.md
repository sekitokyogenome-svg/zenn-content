---
title: "データエージェントに効く指示（instructions）の書き方"
emoji: "📋"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "エージェント", "promptengineering"]
published: true
---

## この記事で解決する課題

データエージェントを構築したのに、回答が的外れだったり、同じ質問でもたびたびブレが生じたりしていませんか。

BigQueryのConversational Analytics APIや自律型エージェントは、`instructions`パラメータによってビジネスコンテキストを受け取ります。ここに何を書くかで、エージェントの回答品質は大きく変わります。本記事では、実務で効果があった指示の設計パターンと、よくある失敗を整理します。

:::message
本記事は2026年10月時点の情報に基づいています。API仕様は更新が速いため、採用前に公式ドキュメントをご確認ください。
:::

---

## instructionsの役割

BigQueryデータエージェントの`instructions`は、エージェントが質問を解釈するときの「前提知識」として機能します。

- テーブルやカラムの**ビジネス上の意味**を補足する
- **計算ルール**（ROASの定義、返品除外など）を統一する
- **言語の揺れ**（「先月」「前月」「直近1ヶ月」の扱い）を解消する
- 回答の**出力形式**（単位・桁区切り・日付形式）を固定する

Knowledge Catalogでテーブルスキーマを整備するのと同様に、instructionsはエージェントに自社データの文脈を伝えるための設計物です。

---

## 基本構造：5つのセクション

実務で使っているinstructionsの基本テンプレートを示します。

```text
【役割】
あなたは中小ECサイトの売上・広告データを分析するアナリストです。
SQLは自動生成してかまいません。回答は日本語で、事業担当者が理解できる言葉で説明してください。

【用語定義】
- 売上：税込合計金額（返品済み注文を除く）
- ROAS：SUM(revenue) / SUM(ad_cost) × 100（%表記）
- 先月：CURRENT_DATE() から1ヶ月遡った月の1日〜末日
- 新規顧客：過去に購入履歴がないユーザー

【除外ルール】
- status = 'returned' の注文は売上集計から除外する
- テスト注文（email LIKE '%@test.example.com'）は除外する
- 集計期間の指定がない場合は直近30日を使う

【出力形式】
- 金額はカンマ区切りの円表記（例：1,234,567円）
- 比率はパーセント小数点1桁（例：12.3%）
- 日付はYYYY-MM-DD形式

【注意事項】
- データが存在しない期間についてはその旨を明示すること
- 集計結果が0件の場合はゼロではなくデータなしと表現すること
```

---

## 効果的な書き方のパターン

### パターン1：曖昧な言葉を明確に定義する

ビジネス用語は組織によって意味が異なります。定義を明示することで、質問ごとに解釈がブレなくなります。

**NG例（曖昧なまま）**
```text
売上を正確に計算してください。
```

**OK例（定義を明示）**
```text
売上はorders.total_amountの合計値を指します。
ただし、order_status = 'returned' および order_status = 'cancelled' の行は除外してください。
返品調整済みの行（is_adjusted = TRUE）を使う場合は、adjusted_amountを優先してください。
```

---

### パターン2：計算ロジックをSQLで示す

ROASやCPAなど、定義が複数あり得る指標は計算式を直接書きます。

```text
【指標の計算式】
- ROAS（%）= SUM(orders.revenue) / SUM(ad_spend.cost) * 100
  ※ ad_spend.costはゼロの場合はNULLを返す（SAFE_DIVIDE使用）
- CPA = SUM(ad_spend.cost) / COUNT(DISTINCT orders.order_id)
  ※ 注文件数がゼロの場合はNULL
- LTV = 顧客ごとの過去全注文のtotal_amountの合計（返品除外）
```

これにより、エージェントが生成するSQLのROAS計算式が毎回一致します。

---

### パターン3：スコープを明示して迷子を防ぐ

どのデータセット・テーブルを使うかを明示すると、エージェントが関係ないテーブルを参照するリスクが減ります。

```text
【使用するテーブル】
- 受注データ：`your-project.ec_mart.orders`（主キー：order_id）
- 広告費：`your-project.ec_mart.ad_spend`（日次・媒体別）
- 商品マスタ：`your-project.ec_mart.products`（主キー：product_id）
- GA4：`your-project.analytics_XXXXXXXXX.events_*`（パーティション：_TABLE_SUFFIX）

【参照しないテーブル】
- 以下のテーブルは古いため使わないこと：legacy_orders, old_campaigns
```

---

### パターン4：GA4固有の注意事項を記述する

GA4データを扱う場合、UNNEST処理や正しいカラム名を明示することで技術的ミスを防げます。

```text
【GA4データの取り扱い】
- ga_session_idはUNNEST(event_params)でキー名 'ga_session_id' のint_valueを取り出すこと
- 流入元の取得にはcollected_traffic_source.manual_mediumを使うこと
  （trafficSource.mediumは旧仕様のため使用禁止）
- イベントパラメータの取得にはUNNESTを使い、直接アクセスしないこと
- テーブルは events_* のワイルドカードで参照し、_TABLE_SUFFIXで日付を絞ること
```

:::message
`ga_session_id`は`UNNEST(event_params)`経由でのみ正しく取得できます。`collected_traffic_source.manual_medium`は流入元の標準カラムで、旧来の`trafficSource.medium`より精度が高いです。
:::

---

### パターン5：回答フォーマットを固定する

出力の見せ方まで定義すると、毎回の回答が一貫します。

```text
【回答フォーマット】
- 結論を最初の1〜2文で述べること
- データの根拠となる数値を必ず示すこと
- 異常値や注意すべき点があれば最後に「注意：」として追記すること
- 推奨アクションがあれば「推奨アクション：」として追記すること
- 不明点や確認が必要な場合は「確認が必要：」として示すこと
```

---

## instructionsの長さとその限界

instructionsを長くしすぎると逆効果になります。目安は以下のとおりです。

| instructionsの長さ | 効果 |
|---|---|
| 〜200文字 | 役割と基本ルールのみ。最低限の精度 |
| 200〜800文字 | 用語定義・計算ルール・出力形式を網羅。実務レベルの精度 |
| 800〜2000文字 | 詳細なスコープ・除外条件・フォーマット。高精度だが読み込み負荷増 |
| 2000文字超 | 後半の指示が無視される可能性が出る。スリム化を検討 |

重要なルールほど前に書き、後半に行くほど補足的な内容にすることが重要です。

---

## Conversational Analytics APIでの適用例

```python
import google.auth
import google.auth.transport.requests
import requests

def build_instructions() -> str:
    return """
あなたはEC事業の売上・広告データアナリストです。

【用語定義】
- 売上：orders.total_amount合計（status='returned'除外）
- ROAS：SUM(revenue)/SUM(ad_cost)*100（%）
- 先月：前月の1日〜末日

【GA4ルール】
- ga_session_idはUNNEST(event_params)でint_valueを取得
- 流入元はcollected_traffic_source.manual_mediumを使用

【出力形式】
- 金額：カンマ区切り円表記
- 比率：小数点1桁の%表記
""".strip()


def query_agent(question: str, project_id: str, dataset_id: str) -> dict:
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())

    endpoint = (
        f"https://bigquery.googleapis.com/v2/projects/{project_id}"
        f"/datasets/{dataset_id}:query"
    )
    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
    }
    payload = {
        "naturalLanguageQuery": question,
        "instructions": build_instructions(),
        "location": "asia-northeast1",
    }
    response = requests.post(endpoint, headers=headers, json=payload)
    response.raise_for_status()
    return response.json()
```

instructionsを関数として管理することで、プロジェクト全体で同じビジネスルールを使い回せます。

---

## よくある失敗と対処法

| 失敗パターン | 原因 | 対処法 |
|---|---|---|
| ROASの定義が毎回変わる | 計算式を指定していない | 分子・分母を明示した式を記述する |
| 返品が含まれて売上が過大 | 除外条件を書いていない | `status != 'returned'` を明示する |
| GA4のセッションIDが正しく取れない | UNNEST指示がない | GA4固有ルールのセクションを設ける |
| 「先月」の解釈が月によってズレる | 期間の定義が曖昧 | DATE_TRUNC式で正確に定義する |
| 回答が長すぎて要点が分からない | 出力形式の指定がない | フォーマットセクションで構造を固定する |

---

## まとめ

- instructionsは「役割・用語定義・計算ルール・スコープ・出力形式」の5セクションで構成する
- 曖昧な用語はビジネス定義とSQLの計算式をセットで記述する
- GA4データを扱う場合はUNNEST処理と`collected_traffic_source.manual_medium`の利用を明示する
- 800文字程度を目安にし、重要なルールを前半に配置する
- instructionsを関数化してプロジェクト全体で一元管理する

次回（第21回）は Data Engineering Agentで自然言語からパイプラインを作る を解説します。

---

:::message
GA4・BigQuery・Looker Studio・AIエージェント構築の設計支援・実装代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
