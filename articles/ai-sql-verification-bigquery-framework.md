---
title: "AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った"
emoji: "🛡️"
type: "tech"
topics: ["bigquery","sql","ai","claude","dataengineering"]
published: true
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

AIが生成したSQLを検証するにあたって、筆者は次の4ステップのフレームワークを運用しています。

1. **構文チェック** — BigQueryのドライランでコスト0で構文エラーを検出する
2. **単体検査** — 比較対象がなくても検出できる「沈黙エラー」を潰す
3. **論理チェック** — 既知の値と突き合わせて数字の妥当性を確認する
4. **差分チェック** — 既存の信頼できるレポートと比較して乖離を検出する

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

## ステップ2: 比較対象なしで沈黙エラーを検出する

このあとのステップ3とステップ4は、どちらも「すでに正しいとわかっている数字」があることを前提にしています。しかし新しく作る分析には、そもそも比較対象がありません。

そして厄介なことに、比較対象があっても見つけにくい誤りが2種類あります。構文は通り、エラーも出ず、それらしい数字が返ってくる——この「沈黙エラー」の代表格が **JOIN fan-out** と **NULLの扱い誤り** です。どちらも比較対象なしで検出できるので、先に潰しておきます。

:::message
このセクションは、本記事に寄せられた「構文チェックを通すだけでは、JOIN fan-outによる指標の水増しやNULLの扱い誤りが最も見逃されやすい」というご指摘を受けて追記しました。
:::

### JOIN fan-out —— 行が増えて指標が水増しされる

結合先のテーブルでキーが重複していると、JOINした瞬間に行が増えます。1つの注文に明細が3行ぶら下がっていれば、注文テーブル側の売上が3倍に膨らんで集計されます。**エラーは出ません。**

AIに「注文データとイベントデータを結合して」と頼むと素直にJOINを書いてくれますが、結合キーが一意かどうかまでは確認してくれません。

対処は単純で、**JOINする前に「結合先（増える側）のキーが一意か」を確かめる**ことです。注文テーブルに明細テーブルを結合するなら、調べるのは明細テーブルの方です。

```sql
-- 結合先のキーが重複していないか確認する。1行でも返ってきたらfan-outする
SELECT
  order_id,
  COUNT(*) AS rows_per_key
FROM `project.dataset.order_items`
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 10
```

すでに書かれたクエリを検査する場合は、**JOINの前後で行数を比べる**のが確実です。

```sql
-- JOIN前後の行数を比較する。増えていればfan-outしている
WITH base AS (
  SELECT order_id, revenue
  FROM `project.dataset.orders`
)
SELECT
  (SELECT COUNT(*) FROM base) AS rows_before_join,
  (
    SELECT COUNT(*)
    FROM base
    LEFT JOIN `project.dataset.order_items` USING (order_id)
  ) AS rows_after_join
```

:::message
`COUNT(DISTINCT ...)`で集計していると、fan-outで増えた行が重複排除され、**水増しがかえって見えなくなります**。数字が正しく見えるぶん発見が遅れるので、検査には`COUNT(*)`を使ってください。
:::

### NULLの扱い —— 黙って行が消える

BigQueryの`CONCAT`は、引数が1つでもNULLなら**結果全体がNULLになります**。そして`COUNT(DISTINCT ...)`と`SUM`はNULLを集計対象から外します。この2つが重なると、エラーを出さないまま件数や金額が減ります。

実は、次のステップ3で使うセッション数のクエリがまさにこの形をしています（後述のNG例）。自分で書いた記事のサンプルコードでも踏んでいた、それくらい気づきにくい罠です。

対処は、**結合キーと集計列のNULL率を先に測っておく**ことです。

```sql
-- 結合キー・集計列のNULL件数を出す
SELECT
  COUNT(*) AS total_events,
  COUNTIF(user_pseudo_id IS NULL) AS null_user_pseudo_id,
  COUNTIF(
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NULL
  ) AS null_ga_session_id
FROM `project.dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

NULLが0件でなければ、その列を使った集計値はその分だけ実態とずれています。

---

## ステップ3: 既知の値と突き合わせる論理チェック

構文が正しくても、集計ロジックが間違っていることがあります。そこで、GA4管理画面やLooker Studioなど「すでに正しいとわかっている数値」とBigQueryの結果を比較します。

たとえば、GA4管理画面で「先月のセッション数が12,000件」とわかっている場合、BigQueryで同じ期間のセッション数を集計して一致するか確認します。

セッション数は`user_pseudo_id`と`ga_session_id`の組み合わせで数えるのですが、素直に書くとステップ2で触れた罠を踏みます。

```sql
-- NG: 2つの問題がある
--   1. ga_session_idがNULLだとCONCATごとNULLになり、COUNT(DISTINCT)が黙って捨てる
--   2. 区切り文字が無いため、別の組み合わせが同じ文字列に潰れうる
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id, '-',
    CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS STRING
    )
  )) AS total_sessions
FROM `myproject.analytics_123456.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
```

`event_name = 'session_start'`で絞っている間は`ga_session_id`がほぼ入っているため実害が出にくいのですが、**この条件を外した途端に過少カウントが始まります**。しかもエラーは出ません。

区切り文字を入れ、捨てられた行数を指標の隣に並べておけば、沈黙しなくなります。

```sql
-- OK: 区切り文字を入れ、NULLで捨てられた行数を同時に出す
WITH events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `myproject.analytics_123456.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
    AND event_name = 'session_start'
)
SELECT
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS total_sessions,
  COUNTIF(user_pseudo_id IS NULL OR ga_session_id IS NULL) AS dropped_rows
FROM events
```

`dropped_rows`が0でなければ、`total_sessions`はその分だけ少なく出ています。管理画面との差を「サンプリングのせい」で片付ける前に、まずここを見てください。

:::message
GA4管理画面とBigQueryの数値は、サンプリングや処理タイミングの違いから完全には一致しないことがあります。誤差の目安は±5%程度です。それ以上乖離している場合はロジックを再確認してください。
:::

---

## ステップ4: Pythonで自動差分チェックを実装する

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

AIが生成したSQLは「使えるけれど、そのまま信じるのは危険」というのが本記事のメッセージです。とくに怖いのは、エラーも出ずそれらしい数字が返ってくる沈黙エラーです。特にGA4のBigQueryエクスポートのように複雑なスキーマを扱う場合は、以下の点を意識するだけで多くの問題を防げます。

- `ga_session_id`は`UNNEST(event_params)`経由で取得する
- 流入元は`collected_traffic_source.manual_medium / manual_source`を使う
- **JOINする前に結合先のキーが一意か確かめる**（fan-outは指標を水増しするがエラーを出さない）
- **`CONCAT`はNULLが1つ混じると結果全体がNULLになり、`COUNT(DISTINCT)`がそれを黙って捨てる**
- ドライランで構文チェック → 単体検査 → 既知値との照合 → 差分チェックの4ステップで検証する

AIは優秀なアシスタントですが、最終的な品質責任はデータを使う側にあります。本記事で紹介したフレームワークを活用して、AIが生成したSQLを安心して活用できる環境を整えてください。

自社のデータ分析基盤に取り入れるにあたってご不明な点があれば、下記よりお気軽にご相談ください。

:::message
GA4・BigQuery・Looker Studio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)

関連記事: [AIが生成したSQLは正しいか？BigQueryでの検証フレームワークを作った](https://logical-web.jp/blog/ai-generated-sql-validation-framework-bigquery/?utm_source=zenn&utm_medium=article&utm_campaign=related_article)
