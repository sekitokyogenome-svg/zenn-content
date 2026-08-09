---
title: "AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った"
emoji: "🛡️"
type: "tech"
topics: ["bigquery","sql","ai","claude","dataengineering"]
published: false
---

## はじめに

「AIにSQLを書いてもらったら、なんか数字がおかしい」——そんな経験をお持ちではないでしょうか。

ChatGPTやClaudeといったAIアシスタントは、複雑なSQLクエリを数秒で生成してくれます。GA4のBigQueryエクスポートデータを分析したい場合でも、「流入元ごとのセッション数を出したい」と入力するだけで、それらしいコードが返ってきます。一見正しそうに見えるのですが、実際に実行してみると「件数が多すぎる」「NULLだらけになる」「集計軸がずれている」といった問題が起きることがあります。

AIが生成するSQLが間違いやすい理由はいくつかあります。GA4のBigQueryエクスポートは独特のネスト構造を持っており、`event_params`や`user_properties`といったフィールドは`UNNEST`しないと正しく取得できません。また、AIは学習データの時点のスキーマを前提に回答するため、最新のGA4仕様と乖離している場合があります。さらに、AIはエラーが出ない限り「正しいSQL」として出力してしまうので、論理的な誤りに気づきにくいのです。

本記事では、AIが生成したSQLをBigQueryで安心して使うための「検証フレームワーク」を紹介します。エンジニアでない方でも理解できるよう、具体的なチェックリストとサンプルコードを交えて解説します。

---

## AIがよく間違えるGA4 SQLのパターン

まず、AIが生成するSQLでありがちな誤りのパターンを把握しておきましょう。

**パターン1: `ga_session_id` を直接参照してしまう**

GA4のBigQueryエクスポートでは、`ga_session_id`はトップレベルのフィールドではなく、`event_params`配列の中に入っています。AIは「`ga_session_id`というフィールドがある」と覚えているため、次のような誤ったSQLを生成することがあります。

```sql
-- NG: ga_session_idを直接参照している（エラーになる）
SELECT
  user_pseudo_id,
  ga_session_id,
  COUNT(*) AS event_count
FROM `project.dataset.events_*`
GROUP BY 1, 2
```

正しくは、`UNNEST(event_params)`を使って値を取り出す必要があります。

```sql
-- OK: UNNEST経由で正しく取得する
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNT(*) AS event_count
FROM `project.dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
```

**パターン2: 流入元を誤ったフィールドから取得する**

AIは古い仕様を参照して`traffic_source.medium`や`traffic_source.source`を使うことがあります。GA4の現行エクスポートでは、セッション単位の流入元は`collected_traffic_source`フィールドを使うのが適切です。

```sql
-- NG: 古い仕様のフィールドを参照（意図しないNULLが増える）
SELECT
  traffic_source.medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `project.dataset.events_*`
GROUP BY 1

-- OK: collected_traffic_sourceを使用する
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `project.dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
ORDER BY users DESC
```

---

## 検証フレームワークの全体像

AIが生成したSQLを検証するにあたって、筆者は次の3ステップのフレームワークを運用しています。

1. **構文チェック** — BigQueryのドライランでコスト0で構文エラーを検出する
2. **論理チェック** — 既知の値と突き合わせて数字の妥当性を確認する
3. **差分チェック** — 既存の信頼できるレポートと比較して乖離を検出する

このフレームワークを使えば、AIが生成したSQLを本番データに適用する前に問題を発見できます。以下、各ステップを順番に説明します。

---

## ステップ1: BigQueryのドライランで構文チェック

BigQueryには「ドライラン」という機能があります。実際にクエリを実行せずに、構文エラーの有無とスキャン予定のデータ量を確認できる機能です。コストが発生しないため、AIが生成したSQLを最初に試す手段として最適です。

Google Cloudのコンソールからも実行できますが、Pythonのクライアントライブラリを使えばスクリプト化も可能です。

```python
from google.cloud import bigquery

def dry_run(sql: str, project_id: str) -> dict:
    """BigQueryのドライランを実行してSQLを検証する"""
    client = bigquery.Client(project=project_id)
    job_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)

    try:
        job = client.query(sql, job_config=job_config)
        bytes_processed = job.total_bytes_processed
        gb = bytes_processed / (1024 ** 3)
        return {
            "status": "ok",
            "message": f"構文エラーなし。推定スキャン量: {gb:.2f} GB"
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

# 使用例
sql = """
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `myproject.analytics_123456.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1
"""

result = dry_run(sql, project_id="myproject")
print(result)
```

:::message
ドライランはあくまで構文チェックです。クエリが実行できても、返ってくる数値が正しいかどうかは別問題です。次のステップで論理チェックも行いましょう。
:::

---

## ステップ2: 既知の値と突き合わせる論理チェック

構文が正しくても、集計ロジックが間違っていることがあります。そこで、GA4管理画面やLooker Studioなど「すでに正しいとわかっている数値」とBigQueryの結果を比較します。

たとえば、GA4管理画面で「先月のセッション数が12,000件」とわかっている場合、BigQueryで同じ期間のセッション数を集計して一致するか確認します。

```sql
-- セッション数を集計して既知の値と照合する
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS STRING
    )
  )) AS total_sessions
FROM `myproject.analytics_123456.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
```

:::message
GA4管理画面とBigQueryの数値は、サンプリングや処理タイミングの違いから完全には一致しないことがあります。誤差の目安は±5%程度です。それ以上乖離している場合はロジックを再確認してください。
:::

---

## ステップ3: Pythonで自動差分チェックを実装する

毎回手動で確認するのは手間がかかります。そこで、AIが生成したSQLと既存の信頼クエリを比較する自動チェックをPythonで実装しました。

```python
import pandas as pd
from google.cloud import bigquery

def compare_queries(trusted_sql: str, ai_sql: str, project_id: str, threshold: float = 0.05):
    """
    信頼できるクエリとAI生成クエリの結果を比較して乖離率を検出する
    threshold: 許容乖離率（デフォルト5%）
    """
    client = bigquery.Client(project=project_id)

    df_trusted = client.query(trusted_sql).to_dataframe()
    df_ai = client.query(ai_sql).to_dataframe()

    # 共通カラムで結合して比較
    numeric_cols = df_trusted.select_dtypes(include='number').columns.tolist()
    results = []

    for col in numeric_cols:
        if col in df_ai.columns:
            trusted_val = df_trusted[col].sum()
            ai_val = df_ai[col].sum()
            if trusted_val != 0:
                diff_rate = abs(ai_val - trusted_val) / trusted_val
                status = "OK" if diff_rate <= threshold else "WARNING"
                results.append({
                    "column": col,
                    "trusted": trusted_val,
                    "ai_generated": ai_val,
                    "diff_rate": f"{diff_rate:.2%}",
                    "status": status
                })

    return pd.DataFrame(results)

# 使用例（省略: trusted_sqlとai_sqlに各クエリを代入して実行）
```

このスクリプトを定期実行するか、新しいSQLを本番導入する前にチェックするだけで、AIが生成したSQLの品質を客観的に評価できます。

---

## まとめ

AIが生成したSQLは「使えるけれど、そのまま信じるのは危険」というのが本記事のメッセージです。特にGA4のBigQueryエクスポートのように複雑なスキーマを扱う場合は、以下の点を意識するだけで多くの問題を防げます。

- `ga_session_id`は`UNNEST(event_params)`経由で取得する
- 流入元は`collected_traffic_source.manual_medium / manual_source`を使う
- ドライランで構文チェック → 既知値との照合 → 差分チェックの3ステップで検証する

AIは優秀なアシスタントですが、最終的な品質責任はデータを使う側にあります。本記事で紹介したフレームワークを活用して、AIが生成したSQLを安心して活用できる環境を整えてください。

自社のデータ分析基盤に取り入れるにあたってご不明な点があれば、下記よりお気軽にご相談ください。

## 関連記事

- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
