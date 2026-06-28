---
title: "BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた"
emoji: "📊"
type: "idea"
topics: ["bigquery", "ec", "marketing"]
published: false
---

## はじめに

「全顧客に同じメルマガを送っている」――そういうEC事業者は少なくないと思います。自分が支援していた某アパレル系ECでも、月2回のメルマガは全会員に同一内容で配信していました。

開封率は徐々に下がり、配信停止が増える。でも、「セグメント分けしたほうがいいのはわかっているけど、どう分ければいいかわからない」という状態だったんです。

そこで実施したのがRFM分析です。BigQueryに蓄積されたGA4の購買データを使って顧客をセグメント分類し、セグメントごとにメルマガの内容と頻度を変えた事例を紹介します。

---

## RFM分析とは

RFM分析は、顧客を3つの指標でスコアリングする手法です。

| 指標 | 意味 | 高スコア |
|------|------|----------|
| **R**ecency | 最終購入からの経過日数 | 最近購入した |
| **F**requency | 購入回数 | 何度も購入している |
| **M**onetary | 累計購入金額 | 多く購入している |

この3軸を掛け合わせることで、「優良顧客」「休眠顧客」「新規で1回だけ買った顧客」などを分類できます。

:::message
RFM分析は古典的な手法ですが、「どの顧客にどんなアプローチをすべきか」の判断材料としては今でも有効です。高度な機械学習モデルを持ち出す前に、まずRFMで全体像を掴むのがおすすめです。
:::

---

## RFMスコアを算出するSQL

GA4のBigQueryエクスポートデータから、ユーザーごとのR・F・Mを算出します。

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS revenue
  FROM `beeracle.analytics_263425816.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20250401' AND '20260331'
    AND ecommerce.purchase_revenue > 0
),
user_rfm AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(CURRENT_DATE(), MAX(purchase_date), DAY) AS recency,
    COUNT(DISTINCT CONCAT(CAST(purchase_date AS STRING), '-', CAST(ga_session_id AS STRING))) AS frequency,
    SUM(revenue) AS monetary
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  recency,
  frequency,
  monetary,
  NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
  NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
  NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
FROM user_rfm;
```

`NTILE(5)` で各指標を5段階にスコアリングしています。Recencyは値が小さいほど良いため `ASC`、FrequencyとMonetaryは大きいほど良いため `DESC` で並べている点に注意してください。

---

## セグメント分類SQL

RFMスコアの組み合わせで顧客をセグメントに分類します。

```sql
WITH rfm_scores AS (
  -- 前述のクエリでr_score, f_score, m_scoreを取得済み
  SELECT *
  FROM user_rfm_scored
)
SELECT
  user_pseudo_id,
  r_score,
  f_score,
  m_score,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP顧客'
    WHEN r_score >= 4 AND f_score >= 3 THEN 'アクティブ優良'
    WHEN r_score >= 4 AND f_score <= 2 THEN '新規・単発'
    WHEN r_score <= 2 AND f_score >= 3 THEN '休眠リスク'
    WHEN r_score <= 2 AND f_score <= 2 THEN '離脱済み'
    ELSE 'その他'
  END AS segment
FROM rfm_scores;
```

セグメントの定義は事業特性によって変わります。上の例はあくまで一つの型で、自分の案件ではクライアントと相談しながら閾値を調整しました。

---

## セグメント別の集計

各セグメントに何人いるか、平均的なRFM値はどうかを確認します。

```sql
SELECT
  segment,
  COUNT(*) AS user_count,
  ROUND(AVG(recency), 0) AS avg_recency_days,
  ROUND(AVG(frequency), 1) AS avg_frequency,
  ROUND(AVG(monetary), 0) AS avg_monetary
FROM rfm_segmented
GROUP BY segment
ORDER BY avg_monetary DESC;
```

某アパレル系ECでの集計結果はこんな感じでした。

| セグメント | ユーザー数 | 平均R（日） | 平均F（回） | 平均M（円） |
|-----------|-----------|------------|------------|------------|
| VIP顧客 | 約120名 | 15 | 8.2 | 128,400 |
| アクティブ優良 | 約350名 | 22 | 4.1 | 52,300 |
| 新規・単発 | 約800名 | 18 | 1.1 | 6,200 |
| 休眠リスク | 約280名 | 95 | 3.8 | 45,600 |
| 離脱済み | 約450名 | 180 | 1.3 | 8,100 |

---

## セグメント別メルマガ戦略

分析結果をもとに、セグメントごとにメルマガの内容と頻度を変えました。

### VIP顧客（R高・F高・M高）

- **頻度**: 週1回
- **内容**: 新商品の先行案内、限定クーポン、お礼メッセージ
- **ポイント**: 特別感を演出する。売り込みより「大切にしている」感を出す

### アクティブ優良（R高・F中〜高）

- **頻度**: 週1回
- **内容**: おすすめ商品、レビュー紹介、コーディネート提案
- **ポイント**: 購入頻度をもう一段上げるための提案型コンテンツ

### 新規・単発（R高・F低）

- **頻度**: 月2回
- **内容**: 初回購入者向けの使い方ガイド、2回目購入の動機づけ
- **ポイント**: 離脱する前にリピートのきっかけを作る

### 休眠リスク（R低・F中〜高）

- **頻度**: 月1回
- **内容**: 「お久しぶりです」系のリマインド、再購入クーポン
- **ポイント**: 過去に何度も買ってくれた顧客なので、戻ってくる可能性は高い

### 離脱済み（R低・F低）

- **頻度**: 月1回以下（またはリスト除外）
- **内容**: 大型セール時のみ配信
- **ポイント**: 配信停止のリスクが高いので、送りすぎに注意

---

## 施策実施後の変化

セグメント配信を開始してから3ヶ月後の数値変化です。

| 指標 | 一斉配信時 | セグメント配信後 |
|------|-----------|----------------|
| メルマガ開封率 | 18.2% | 27.5% |
| クリック率 | 2.1% | 4.8% |
| 配信停止率（月間） | 1.8% | 0.6% |
| メルマガ経由売上 | 月82万円 | 月134万円 |

特に「休眠リスク」セグメントへの再購入クーポン施策が効果的で、このセグメントだけで月20万円以上の売上が復活しました。

---

## BigQueryでの定期更新

RFMスコアは定期的に更新しないと意味がありません。顧客の行動は日々変わるためです。

自分の場合は、BigQueryのスケジュールクエリ機能を使って週次でRFMスコアを再計算し、セグメント分類テーブルを更新していました。

```sql
-- スケジュールクエリとして登録する
CREATE OR REPLACE TABLE `project.dataset.rfm_segments` AS
-- 前述のRFM算出＋セグメント分類のクエリをここに記述
```

メルマガ配信ツール側でセグメントIDを参照できるようにしておくと、配信の自動化まで一気通貫でつなげられます。

---

## まとめ

RFM分析は「全員に同じメッセージを送る」から脱却するための最初の一歩です。BigQueryにGA4のデータが蓄積されているなら、SQLを数本書くだけで顧客セグメントが見えてきます。

自分としては、RFM分析の価値は「分類すること」そのものよりも、「セグメントごとに何をすべきかを考えるきっかけになること」だと感じています。

皆さんのECサイトでは、メルマガのセグメント配信はどの程度実施できていますか？

:::message
「ECサイトのデータ分析基盤を構築したい」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
