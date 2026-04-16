```markdown
---
title: "WEBコンサルタントがClaude CodeでSQLを書く時間をゼロにした話"
emoji: "⚡"
type: "idea"
topics: ["claudecode", "bigquery", "ga4", "webコンサル", "業務効率化"]
published: false
---

## 「レポート作成だけで1日が終わる」という地獄

WEBコンサルタントとして独立して3年目。クライアントが増えるのは嬉しいのに、レポート作成に追われて**肝心の「提案」に時間を使えない**というジレンマに陥っていました。

特にGA4×BigQueryのSQL作成。クライアントごとにテーブル構造の確認、クエリの組み立て、結果の検証…1本のレポートに平均2〜3時間かかっていました。月に10社分で約25時間。丸3営業日がSQLを書くだけで消えていたんです。

この記事では、Claude Codeを導入して**SQL作成時間を実質ゼロにした具体的なプロセス**と、ビジネスにどんなインパクトがあったかをお話しします。

## Before：月25時間をSQLに費やしていた内訳

まず、当時の作業内訳を正直に晒します。

| 作業内容 | 1社あたり | 月10社合計 |
|---|---|---|
| SQL設計・記述 | 60分 | 10時間 |
| クエリのデバッグ | 40分 | 6.7時間 |
| 結果の整形・可視化 | 50分 | 8.3時間 |
| **合計** | **150分** | **25時間** |

正直、SQLの記述ミスで30分溶かすなんてザラでした。`UNNEST(event_params)`の書き方を毎回調べたり、`collected_traffic_source.manual_medium`のフィールド名を間違えたり。

## After：Claude Codeで何が変わったか

### 導入1ヶ月目の変化

Claude Codeに「GA4 BigQueryのチャネル別コンバージョン分析のSQLを書いて」と依頼するところから始めました。

最初は半信半疑でしたが、出てくるSQLの精度に驚きました。GA4のBigQueryエクスポートテーブル特有の**ネスト構造を正しく理解している**んです。

実際に依頼して生成されたSQLの一例：

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ))
  ) AS cvr
FROM
  `project.dataset.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250501' AND '20250531'
GROUP BY 1, 2
ORDER BY sessions DESC
```

これ、ほぼそのまま使えるレベルです。

### 3ヶ月後の数字

| 作業内容 | Before | After | 削減率 |
|---|---|---|---|
| SQL設計・記述 | 10時間/月 | 0.5時間/月 | **95%減** |
| クエリのデバッグ | 6.7時間/月 | 1時間/月 | **85%減** |
| 結果の整形・可視化 | 8.3時間/月 | 3時間/月 | 64%減 |
| **合計** | **25時間/月** | **4.5時間/月** | **82%減** |

月20時間以上が浮きました。

## 浮いた20時間で何をしたか——ここが本質

:::message
重要なのは「SQLを書く時間が減った」ことではなく、**「提案の質が上がり、単価が上がった」**ことです。
:::

浮いた20時間の使い道：

- **競合分析・市場調査**に月8時間（これまでほぼゼロだった）
- **施策の仮説立案**に月6時間
- **クライアントとの対話**に月6時間

結果として起きたこと：

1. **レポートの納品スピードが3日→当日に短縮**
2. 「データを見せるだけ」から「データに基づく施策提案」へ進化
3. 顧問契約の月額単価が**平均1.4倍**に上昇（5万円→7万円）
4. 新規クライアントを3社追加で受けられるようになった

月の売上で見ると、**50万円 → 91万円**。Claude Codeの月額費用を差し引いても、ROIは圧倒的でした。

## うまく使うために意識した3つのこと

**① プロンプトに「GA4 BigQueryエクスポート」と明記する**
これだけでネスト構造を前提としたSQLが返ってきます。

**② 期間やテーブル名は変数的に指示する**
「_TABLE_SUFFIXで期間指定して」と伝えるだけで、WHERE句を正しく組んでくれます。

**③ 出力されたSQLは必ず目視チェックする**
AIが生成したSQLを無検証で使うのは危険です。特にフィールド名やJOIN条件は、BigQuery上で実行前に確認するようにしています。

:::message alert
Claude Codeは優秀ですが、万能ではありません。GA4のスキーマ変更やカスタムイベントの設計が特殊な場合は、手動での修正が必要になることもあります。過信せず「優秀なアシスタント」として付き合うのがコツです。
:::

## まとめ：コンサルの価値は「SQLを書くこと」ではない

WEBコンサルタントの本来の価値は、データから**意味を読み取り、行動につながる提案をすること**です。SQLはそのための手段でしかありません。

Claude Codeを使い始めて実感したのは、「作業」と「仕事」は違うということ。手段を効率化することで、本来やるべき仕事に集中できるようになりました。

---

:::message
「GA4のデータはあるけど、活用しきれていない」「BigQueryを導入したいけど何から始めればいいかわからない」——そんなお悩みをお持ちでしたら、GA4×BigQueryの初期設定から分析レポートの構築までサポートしています。まずはお気軽にご相談ください。
👉 [ココナラの相談ページはこちら](https://coconala.com/services/1791205)
:::
```