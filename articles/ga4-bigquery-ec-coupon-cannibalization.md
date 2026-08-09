---
title: "GA4×BigQueryでECクーポン施策のカニバリゼーションを検証する"
emoji: "🎫"
type: "tech"
topics: ["bigquery","googleanalytics","ec","sql","datanalysis"]
published: false
---

## はじめに

クーポンやセール施策を打つたびに「本当に効果があったのか？」という疑問を持ったことはないでしょうか。売上こそ増えているように見えても、実は「元から購入するつもりだった顧客がクーポンを使っただけ」だったとすれば、利益は削られるばかりです。

このような現象を「カニバリゼーション（共食い）」と呼びます。EC施策におけるカニバリゼーションとは、クーポン配布などの販促施策が、新規獲得や購買意欲を高める効果を発揮するのではなく、もともと購入していた顧客の割引負担として機能してしまうことを指します。

本記事では、GA4（Google Analytics 4）のBigQueryエクスポートデータを活用して、クーポン施策のカニバリゼーションを定量的に検証する方法を解説します。SQLは可能な限り丁寧に説明しますので、エンジニアでない方でも「どのような考え方でデータを見ているか」をご理解いただけるように努めます。

---

## クーポンのカニバリゼーションとは何か

カニバリゼーションという言葉は「共食い」を意味し、マーケティングでは「既存の顧客行動や売上を新施策が侵食してしまう現象」を指します。

ECにおけるクーポン施策のカニバリゼーションには、大きく2つのパターンがあります。

**パターン①：定価購入者の割引化**
クーポンがなくても購入していたであろうユーザーがクーポンを使った場合です。たとえば「リピーターへの感謝クーポン」を配布したとき、そのリピーターが今月の購入予定商品をクーポンで割引購入するだけであれば、新たな売上増加は生まれず、利益率の低下だけが残ります。

**パターン②：広告流入クーポンと自然流入の競合**
「広告クリック→クーポン利用→購入」という経路と、「自然検索→通常価格で購入」という経路が本来両立できるはずのところ、クーポン広告が自然流入を食ってしまうケースです。広告費を払っているのに、クーポン分だけ利益が削れてしまいます。

これらを感覚ではなくデータで把握することが、施策改善の第一歩です。

---

## GA4 BigQueryエクスポートのデータ構造を理解する

GA4には「BigQueryエクスポート」という機能があり、サイトで発生した全イベントデータをGoogleのデータウェアハウスであるBigQueryに蓄積することができます。

エクスポートされるテーブルの主な構造は以下のとおりです。

```
プロジェクト.データセット.events_YYYYMMDD
（例）myproject.analytics_123456789.events_20250801
```

各行は1イベントを表し、分析で使用する主なフィールドは次のとおりです。

| フィールド | 内容 |
|---|---|
| event_name | イベント種別（purchase, add_to_cart など）|
| event_params | イベントパラメータ（ARRAY型）|
| user_pseudo_id | 匿名ユーザーID |
| collected_traffic_source.manual_medium | 流入媒体（cpc, organic など）|
| collected_traffic_source.manual_source | 流入元（google, email など）|

:::message
`ga_session_id` はテーブルのトップレベルには存在しません。`UNNEST(event_params)` を使って `event_params` 配列の中から取り出す必要があります。この点は後述のSQLで実際に示します。直接 `ga_session_id` と書いてもエラーになるためご注意ください。
:::

クーポン利用の判定には、`purchase` イベントの `coupon` パラメータを参照します。このパラメータも同様に `UNNEST(event_params)` 経由で取得します。

---

## SQLでカニバリゼーションを数値化する

### ステップ1：クーポン利用有無別の購入数と売上を流入元ごとに集計する

まず、クーポンを使って購入したユーザーと使わずに購入したユーザーの数と売上を、流入元ごとに分けて集計します。

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は UNNEST 経由で取得（直接参照不可）
    (SELECT value.int_value
       FROM UNNEST(event_params)
      WHERE key = 'ga_session_id') AS session_id,
    -- クーポンコードも同様に取得
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    (SELECT value.double_value
       FROM UNNEST(event_params)
      WHERE key = 'value') AS purchase_value,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `myproject.analytics_123456789.events_20250801`
  WHERE
    event_name = 'purchase'
)

SELECT
  CASE
    WHEN coupon_code IS NOT NULL AND coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  medium,
  source,
  COUNT(*)                        AS purchase_count,
  ROUND(SUM(purchase_value), 0)   AS total_revenue
FROM purchase_events
GROUP BY coupon_flag, medium, source
ORDER BY total_revenue DESC;
```

このクエリを実行すると、「クーポン使用 × 流入元別」の購入数と売上を一覧で確認できます。たとえば「organic × google × クーポン使用」の件数が多い場合、自然検索で訪問したユーザーがクーポンで割引購入しているケースが多いことを示しており、カニバリゼーションの疑いが生じます。

### ステップ2：施策前後でリピーターの購入傾向を比較する

カニバリゼーションの核心は「クーポンがなくても買っていたか否か」です。それを完全に証明することは難しいですが、施策前後でリピーターの購入行動を比較することで傾向を掴めます。

```sql
-- 施策前期間（例：2025-07-01〜07-31）の購入ユーザー
WITH before_period AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count_before
  FROM
    `myproject.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

-- 施策後期間（例：2025-08-01〜08-31）の購入ユーザーとクーポン利用有無
after_period AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    COUNT(*) AS purchase_count_after
  FROM
    `myproject.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250801' AND '20250831'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, coupon_code
)

SELECT
  CASE
    WHEN b.user_pseudo_id IS NOT NULL THEN '既存リピーター'
    ELSE '新規ユーザー'
  END AS user_type,
  CASE
    WHEN a.coupon_code IS NOT NULL AND a.coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  COUNT(*)                              AS user_count,
  ROUND(AVG(a.purchase_count_after), 2) AS avg_purchase_count
FROM after_period a
LEFT JOIN before_period b
  ON a.user_pseudo_id = b.user_pseudo_id
GROUP BY user_type, coupon_flag
ORDER BY user_type, coupon_flag;
```

「既存リピーター × クーポン使用」のユーザー数が多く、「新規ユーザー × クーポン使用」が少ない場合は、クーポンが新規獲得ではなくリピーターの割引に使われている可能性が高いと判断できます。

:::message
分析の精度を高めるには、施策期間と比較期間の長さを揃えること、季節性や曜日の影響を考慮することが重要です。前年同期との比較も合わせて行うと、より信頼性の高い判断につながります。
:::

---

## 分析結果の読み方と次の打ち手

SQLで数値を出した後、どう解釈して施策に活かすかが重要です。

**カニバリゼーション度合いの判断目安**

| 状況 | 考えられる解釈 |
|---|---|
| 既存リピーターのクーポン使用率が高い | カニバリゼーションの可能性が高い |
| 自然検索流入者のクーポン使用率が高い | 広告費が不要なユーザーに割引している可能性 |
| 新規ユーザーのクーポン使用率が高い | 獲得施策として機能している（比較的健全）|
| クーポン期間中に購入頻度が増加している | 購買促進効果が出ている可能性がある |

分析結果としてカニバリゼーションの傾向が見られた場合、次のような施策変更を検討する価値があります。

- **クーポン配布対象をセグメント化する**：初回購入者や長期離脱ユーザー（例：90日以上未購入）のみに配布し、定期購入者への配布を避ける
- **クーポンの有効期間を短く設定する**：「今すぐ使わなければ」という状況を作り出し、予定していた購入とは異なる追加購買を促す
- **配布チャネルを目的別に分ける**：メール・LINEなど関係性のある既存顧客向けと、広告経由の新規獲得向けでクーポンの設計や割引率を変える

いずれの打ち手も、変更後のデータを同じSQLで追跡し、継続的に効果を検証することをお勧めします。

---

## まとめ

本記事では、GA4×BigQueryを活用してECクーポン施策のカニバリゼーションを検証する方法をご紹介しました。要点を整理します。

- **カニバリゼーションとは**：クーポンがなくても購入したであろうユーザーへの割引が、利益を圧迫する現象
- **分析の基本**：`purchase` イベントのクーポンパラメータと流入元（`collected_traffic_source`）を組み合わせて集計する
- **`ga_session_id` の取得**：`UNNEST(event_params)` 経由で取得する（テーブルへの直接参照は不可）
- **施策前後の比較**：既存リピーターと新規ユーザーのクーポン使用率を比較することで傾向を把握できる
- **次のアクション**：カニバリゼーションが確認されたら、配布対象のセグメント化や配布チャネルの見直しを行う

データに基づく意思決定を積み重ねることで、クーポン施策の費用対効果を改善していくことができます。まずは自社のBigQueryデータでステップ1のクエリを実行してみるところからはじめてみてください。

## 関連記事

- [GA4イベントパラメータをUNNESTで展開するSQLパターン集](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)
- [ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する](https://zenn.dev/web_benriya/articles/bigquery-ga4-days-to-purchase-distribution)
- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
