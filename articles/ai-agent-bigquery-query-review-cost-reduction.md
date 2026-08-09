---
title: "AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法"
emoji: "🤖"
type: "tech"
topics: ["bigquery","ai","claude","googlecloud","cost"]
published: false
---

## はじめに

「BigQueryの請求額が先月より突然跳ね上がった」「どのクエリがコストの大半を占めているのかわからない」——そのような経験をお持ちの方は少なくないのではないでしょうか。

BigQueryはスキャンしたデータ量に応じて課金される仕組みのため、クエリの書き方ひとつで月額費用が大きく変わります。特にGA4のBigQueryエクスポートデータは日々蓄積され続けるため、何も対策しないまま運用を続けると、想定外の請求が発生するリスクがあります。

かといって、すべてのクエリをエンジニアがひとつひとつ手動でレビューするのは現実的ではありません。そこで筆者が試みたのが、**AIエージェント（Claude）を活用したクエリの自動レビュー**です。本記事では、その仕組みと実際に得られた効果について、非エンジニアの方にも伝わるよう丁寧にご説明します。

---

## BigQueryのコストが膨らむ典型的な原因

BigQueryの費用が高くなる原因は、大きく分けて以下の3つです。

1. **フルスキャン（テーブル全体の読み込み）**：WHERE句による絞り込みが不十分で、必要のない過去データまで読み込んでしまうケース
2. **SELECT \* の多用**：必要なカラムだけでなく、テーブル全列を取得してしまうクエリ
3. **パーティションの未活用**：GA4のエクスポートテーブルはイベント日付ごとにパーティションが切られていますが、これを無視した検索

たとえば、GA4の購入イベントを集計する際、以下のようなクエリは一見シンプルに見えますが、コスト面では問題を抱えています。

```sql
-- コストが高くなりがちな書き方（改善前）
SELECT
  *
FROM
  `project_id.analytics_XXXXXXXXX.events_*`
WHERE
  event_name = 'purchase'
```

このクエリは全カラムを取得しており、日付によるパーティション絞り込みもありません。データが数年分蓄積されている場合、スキャン量が非常に大きくなります。

---

## AIエージェントにクエリレビューを依頼する仕組み

今回構築した仕組みは、PythonスクリプトからClaude APIを呼び出し、BigQueryのクエリをAIに渡してレビューしてもらうというものです。

```python
import anthropic

client = anthropic.Anthropic()

def review_bq_query(query: str) -> str:
    prompt = f"""
以下のBigQueryクエリをコスト最適化の観点でレビューしてください。
改善すべき点があれば、修正後のクエリも合わせて提示してください。

【レビュー観点】
- SELECT * の使用有無
- パーティションの活用状況（_TABLE_SUFFIXまたはevent_dateによる絞り込み）
- 不要なフルスキャンの有無
- JOINの効率性

【クエリ】
{query}
"""
    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=1024,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )
    return message.content[0].text

# 使用例
sample_query = """
SELECT *
FROM `project_id.analytics_XXXXXXXXX.events_*`
WHERE event_name = 'purchase'
"""

result = review_bq_query(sample_query)
print(result)
```

このスクリプトをClaude Code（CLIツール）から呼び出すことで、Gitリポジトリへのコミット前にクエリのレビューを自動実行することも可能です。

---

## AIが提案した最適化クエリの例

上記のサンプルクエリをAIにレビューさせた結果、以下のような改善案が提示されました。

```sql
-- AIが提案した改善後のクエリ
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  ecommerce.purchase_revenue AS revenue
FROM
  `project_id.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
  AND event_name = 'purchase'
```

改善のポイントは以下のとおりです。

- `SELECT *` を廃止し、必要なカラムのみを指定
- `_TABLE_SUFFIX` で対象期間を明示し、パーティションを活用
- `ga_session_id` は `UNNEST(event_params)` を通じて取得（GA4では直接参照できないため）
- 流入元（medium / source）は `collected_traffic_source` フィールドを使用

:::message
GA4のBigQueryエクスポートデータでは、`ga_session_id` はネストされた `event_params` 配列の中に格納されています。`UNNEST()` を使って展開してから参照する必要があります。また、流入元の情報は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` カラムに入っています。
:::

---

## 実際に運用してみて気づいた効果と注意点

この仕組みを導入してから数ヶ月運用した経験をもとに、率直な所感をお伝えします。

**よかった点**

- SQLに詳しくないチームメンバーが書いたクエリでも、AIが問題点を日本語でわかりやすく説明してくれるため、レビューコストが下がった
- 「なぜコストが高いのか」の説明が自動生成されるため、本人が学習する機会にもなった
- 改善前後でBigQueryの「ドライラン（実行前スキャン量推定）」機能と組み合わせることで、削減効果を数値で確認できた

**注意が必要な点**

- AIが提案するクエリが、業務要件を満たしているかどうかは人間が判断する必要があります。SQLの書き方は改善されても、集計ロジック自体が変わっていないかを確認してください。
- Claude APIの利用にも費用が発生します。大量のクエリを一括レビューする場合は、API呼び出し回数とコストのバランスを考慮してください。
- クエリにプロジェクトID・テーブル名など機密情報が含まれる場合は、APIに送信するデータの取り扱いについて社内ポリシーを確認したうえで運用してください。

BigQueryのスキャン量削減については、以下のコマンドでドライランを実行することで改善前後の差異を確認できます。

```bash
bq query \
  --use_legacy_sql=false \
  --dry_run \
  'SELECT event_date, user_pseudo_id
   FROM `project_id.analytics_XXXXXXXXX.events_*`
   WHERE _TABLE_SUFFIX BETWEEN "20250101" AND "20250731"
   AND event_name = "purchase"'
```

---

## まとめ

本記事では、AIエージェント（Claude）を活用してBigQueryクエリのレビューを自動化する取り組みについてご紹介しました。

要点を整理すると以下のとおりです。

- BigQueryのコスト増加は、`SELECT *` の多用やパーティション活用不足が主な原因になりやすい
- Claude APIを使ったPythonスクリプトで、クエリのレビューと改善案の提示を自動化できる
- GA4のBigQueryエクスポートデータでは、`ga_session_id` の取得方法や流入元フィールドに注意が必要
- AIの提案は参考情報として活用しつつ、最終的な判断は人間が行う運用を推奨する

次のアクションとしては、まず小規模なクエリ1〜2本をAIにレビューさせてみることをお勧めします。Claude APIは無料トライアルから始められるため、費用をかけずに効果を確認していただけます。

既にBigQueryを活用されている方は、Google Cloud コンソールの「BigQuery Studio」から過去のジョブ履歴を確認し、スキャン量が多かったクエリを見つけるところから始めてみてください。

## 関連記事

- [Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】](https://zenn.dev/web_benriya/articles/gemini-bigquery-pricing-complete-guide)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
