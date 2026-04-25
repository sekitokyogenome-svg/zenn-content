

```markdown
---
title: "Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2025年版】"
emoji: "🤖"
type: "tech"
topics: ["bigquery", "gemini", "ga4", "sql", "ai"]
published: false
---

## 「SQLが書けないから、GA4のデータを活かしきれない…」

EC担当者やWEBマーケターの方で、こんな悩みを抱えていませんか？

- GA4の管理画面だけでは欲しいデータが出せない
- BigQueryにエクスポートしたけどSQLが書けず放置している
- ChatGPTにSQL生成を頼んでいるが、フィールド名が間違っていて動かない

2024年後半から本格的に使えるようになった**Gemini in BigQuery**を活用すれば、BigQueryのコンソール上で自然言語からSQLを直接生成できます。外部ツールとの行き来が不要で、しかもテーブルのスキーマを自動認識してくれるため、フィールド名の間違いが大幅に減ります。

本記事では、GA4 × BigQueryの実務シーンを想定し、Gemini in BigQueryの具体的な使い方と注意点を解説します。

## Gemini in BigQueryとは

Google CloudがBigQueryコンソールに統合したAIアシスタント機能です。主な特徴は以下の通りです。

| 特徴 | 内容 |
|------|------|
| 自然言語→SQL生成 | 日本語の質問からSELECT文を自動生成 |
| スキーマ認識 | 対象テーブルのカラム構造を理解した上でSQL生成 |
| SQL説明・修正 | 既存SQLの意味を解説、エラー修正を提案 |
| コンソール内完結 | BigQueryエディタ上でそのまま使える |

:::message
Gemini in BigQueryの利用には、Google Cloudプロジェクトで「Gemini for Google Cloud」APIの有効化とIAM権限の設定が必要です。無料トライアル枠もあるので、まず試してみることをおすすめします。
:::

## 実践：GA4データに対して自然言語でSQLを生成する

### ステップ1：BigQueryコンソールでGeminiを起動

BigQueryのSQLエディタ上部にある**ペンのアイコン（Generate SQL）**、またはエディタ内に表示される「SQLを生成」プロンプト欄に自然言語を入力します。

### ステップ2：対象テーブルを指定して質問する

例として、以下のような自然言語プロンプトを入力します。

```
テーブル `project_id.analytics_XXXXXX.events_*` から、
2025年1月の購入完了イベント（purchase）のセッション数をチャネル別に集計してください。
```

### ステップ3：生成されたSQLを確認・修正して実行

Geminiが生成するSQLの例は以下のようになります。

```sql
SELECT
  collected_traffic_source.manual_medium AS channel_medium,
  collected_traffic_source.manual_source AS channel_source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS purchase_sessions
FROM
  `project_id.analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND event_name = 'purchase'
GROUP BY
  channel_medium, channel_source
ORDER BY
  purchase_sessions DESC;
```

:::message alert
Geminiが生成するSQLは高精度ですが、GA4のBigQueryエクスポートデータ特有の構造（UNNEST、event_params のネスト構造など）は意図通りに展開されないケースもあります。生成後は必ず目視で確認し、小さなデータ範囲でテスト実行してください。
:::

## 実践プロンプト例：よく使う3パターン

GA4 × BigQueryの実務で使用頻度が高い質問パターンを紹介します。

### パターン①：ランディングページ別セッション数

```
テーブル `project_id.analytics_XXXXXX.events_*` から、
2025年1月のsession_startイベントで、
event_paramsのpage_locationをランディングページとして、
ページ別セッション数を上位20件出してください。
```

### パターン②：商品別購入数と売上

```
テーブル `project_id.analytics_XXXXXX.events_*` から、
2025年1月のpurchaseイベントに紐づくitemsの中から、
商品名（item_name）別の購入数量と合計売上を集計してください。
```

### パターン③：新規とリピーターの比較

```
テーブル `project_id.analytics_XXXXXX.events_*` から、
2025年1月のsession_startイベントで、
event_paramsのga_session_numberが1のセッションを新規、
2以上をリピーターとして分類し、それぞれのセッション数を出してください。
```

## Gemini in BigQueryを使う際の3つの注意点

**1. プロンプトにテーブル名を明示する**
テーブルを指定しないと、Geminiはどのデータを対象にすればよいか分からずに汎用的なSQLを返します。バッククォート付きで正確なテーブル名を含めましょう。

**2. GA4特有のフィールド構造を補足する**
`event_params`や`items`はRECORD型（配列）なので、「UNNESTして取得」「event_paramsのkeyがXXXのvalue.string_valueを使う」のような補足を加えると精度が上がります。

**3. 生成結果を鵜呑みにしない**
Geminiの出力はあくまで「下書き」です。特にWHERE句の条件やデータ型のキャストは、実行前に必ずチェックしてください。

:::message
Gemini in BigQueryは「SQLの初稿を高速で作る」ツールとして捉えるのがベストです。ゼロからSQLを書く時間を8割削減しつつ、最後の仕上げは人間が行う運用が現実的です。
:::

## まとめ

- Gemini in BigQueryを使えば、**自然言語→SQL変換がBigQueryコンソール内で完結**する
- GA4のBigQueryデータに対しては、テーブル名とフィールド構造を補足するのがコツ
- 生成されたSQLは必ず確認・テスト実行してから本番に使う

SQLの壁を感じていた方にとって、Gemini in BigQueryはデータ活用の大きな一歩になるはずです。

---

:::message
**「BigQueryにデータはあるけど、分析の仕組みが作れない」方へ**

GA4 × BigQueryの初期設定からダッシュボード構築、AI活用まで、EC・WEBサイトのデータ分析基盤づくりをサポートしています。

👉 [ココナラでサービスを見る](https://coconala.com/services/1791205)
:::
```