---
title: "LINE広告×GA4×BigQueryでCPA・ROASを正確に計測する設定と集計SQL"
emoji: "📱"
type: "tech"
topics: ["bigquery","googleanalytics","advertising","sql","ec"]
published: false
---

## はじめに

「LINE広告を出稿しているのに、本当に効いているのかよくわからない」——こうした悩みを抱えるEC担当者や広告運用者は少なくありません。LINE広告のレポート画面には数字が並んでいるものの、GA4側の数字と合わない、または売上との対応関係がつかめないというケースがよく見受けられます。

原因のひとつは、LINE広告とGA4の計測の仕組みの違いにあります。LINE広告はクリックベースのアトリビューションを採用しており、GA4はセッション単位で流入元を判定します。設定を正しく合わせておかないと、「LINE経由の売上」が正確にGA4へ記録されず、CPA（顧客獲得単価）もROAS（広告費用対効果）も正しく算出できません。

本記事では、LINE広告のリンクにUTMパラメータを設定する方法から、GA4のデータをBigQueryでエクスポートしてSQLで集計する手順まで、実務で使える内容を段階的にご説明します。中小ECの運営者やWebコンサルタントの方を主な読者として想定していますが、SQLの基礎があれば非エンジニアの方にも活用いただける内容です。

---

## LINE広告にUTMパラメータを設定する

GA4でLINE広告の流入を正しく識別するためには、広告のリンクURLにUTMパラメータを付与することが前提となります。LINE広告管理画面でクリエイティブや広告グループを設定する際に、遷移先URLへ以下のようなパラメータを追加してください。

```
https://example.com/lp/?utm_source=line&utm_medium=cpc&utm_campaign=summer2025&utm_content=banner_A
```

各パラメータの意味は次のとおりです。

| パラメータ | 推奨値（例） | 説明 |
|---|---|---|
| utm_source | line | 流入元の識別子 |
| utm_medium | cpc | メディア種別 |
| utm_campaign | summer2025 | キャンペーン名 |
| utm_content | banner_A | クリエイティブの識別 |

LINE広告の管理画面では「リンク先URL」欄に直接UTMパラメータ付きのURLを入力できます。広告グループやクリエイティブごとに`utm_content`や`utm_campaign`を変えておくことで、後からBigQueryで粒度の細かい分析が可能になります。

:::message
LINEのURLスキームやLINE公式アカウントのリッチメニューからの遷移の場合も、同様にUTMパラメータを付与することで計測できます。ただし、LINEアプリ内ブラウザ（LAB）の挙動によっては参照元情報が欠落するケースがあるため、GA4側でデバッグビューを使って計測を事前に確認しておくとよいでしょう。
:::

---

## GA4のBigQueryエクスポートを有効にする

UTMパラメータが設定できたら、GA4のデータをBigQueryへエクスポートする設定を行います。これにより、GA4のイベントデータをSQLで自由に集計できるようになります。

設定手順の概要は以下のとおりです。

1. GA4管理画面の「管理」→「プロパティ設定」→「BigQueryのリンク設定」を開く
2. 連携するGCPプロジェクトを選択し、データのエクスポート頻度（毎日 or ストリーミング）を設定する
3. エクスポート先のデータセットが自動的に作成され、`events_YYYYMMDD`形式のテーブルにデータが蓄積されていく

エクスポートが開始されると、BigQuery上に以下のようなテーブル構造でデータが保存されます。

```
プロジェクトID.analytics_XXXXXXXX.events_20250801
```

このテーブルには、ページビューや購入イベント、セッション開始イベントなどGA4で収集した全イベントが含まれます。

:::message
BigQueryの無料枠（月10GBのクエリ処理）を超える場合は費用が発生します。小規模サイトであれば無料枠内に収まることが多いですが、クエリの`WHERE`句で日付を絞り込む習慣をつけておくことをおすすめします。
:::

---

## BIgQueryでLINE広告の流入セッションを抽出するSQL

BigQueryへデータが蓄積できたら、LINE広告経由のセッションを抽出してみましょう。GA4のBigQueryエクスポートでは、流入元情報は`collected_traffic_source`フィールドに格納されています。また、`ga_session_id`を取得する際は`event_params`をUNNESTする必要があります。

以下のSQLは、LINE広告（utm_medium=cpc, utm_source=line）経由のセッションIDと流入元情報を取得する基本クエリです。

```sql
-- LINE広告経由のセッション一覧を取得
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  MIN(event_timestamp) AS session_start_ts
FROM
  `your_project.analytics_XXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source = 'line'
  AND event_name = 'session_start'
GROUP BY
  1, 2, 3, 4, 5
```

`collected_traffic_source.manual_source`と`collected_traffic_source.manual_medium`が、それぞれUTMパラメータの`utm_source`と`utm_medium`に対応しています。このフィールドはGA4側でセッション開始時に記録されるため、セッション内の最初のイベントに付与された流入情報を取得できます。

---

## CPA・ROASをSQLで集計する

続いて、LINE広告経由のセッションに紐づく購入イベントを集計し、CPA・ROASを算出するSQLを作成します。GA4のeコマース計測が設定されていれば、`purchase`イベントの`event_params`に購入金額が含まれています。

```sql
-- LINE広告のCPA・ROASを集計（月次）
WITH line_sessions AS (
  -- LINE広告経由のセッションを特定
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `your_project.analytics_XXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'line'
),

purchases AS (
  -- 購入イベントとセッションIDを紐付け
  SELECT
    e.user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(e.event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT value.double_value
      FROM UNNEST(e.event_params)
      WHERE key = 'value'
    ) AS purchase_revenue
  FROM
    `your_project.analytics_XXXXXXXX.events_*` AS e
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND e.event_name = 'purchase'
)

SELECT
  COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)) AS conversions,
  SUM(p.purchase_revenue)                                              AS total_revenue,
  -- 広告費は手動で入力（例: 50000円）
  50000                                                                AS ad_spend,
  ROUND(50000 / NULLIF(COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)), 0), 0) AS cpa,
  ROUND(SUM(p.purchase_revenue) / NULLIF(50000, 0), 2)                AS roas
FROM
  purchases AS p
INNER JOIN
  line_sessions AS ls
  ON p.user_pseudo_id = ls.user_pseudo_id
  AND p.ga_session_id  = ls.ga_session_id
```

このSQLでは、LINE広告のセッションに紐づく`purchase`イベントを内部結合で絞り込み、コンバージョン数・売上合計・CPA・ROASをまとめて算出しています。広告費は現状BigQuery側には入らないため、手動で定数として記述するか、別途広告費テーブルを用意してJOINする構成にするとより実用的です。

:::message
`event_params`の`value`キーに格納される値の型は、設定によって`double_value`または`int_value`が使われる場合があります。実際のデータを`SELECT event_params FROM ...`で確認し、適切な型フィールドを参照してください。
:::

---

## Looker Studioでダッシュボードを作成してモニタリングする

BigQueryでSQLが完成したら、Looker Studio（旧データポータル）と接続してダッシュボード化しておくと、毎月の確認作業が大幅に効率化されます。BigQueryコネクタを使えば、作成したSQLをカスタムクエリとして直接読み込むことができます。

ダッシュボードに含めると便利な指標の例を挙げます。

- **コンバージョン数の推移**（折れ線グラフ）
- **CPA・ROASの月次比較**（表 or スコアカード）
- **キャンペーン別のROAS比較**（棒グラフ）
- **デバイス別（PC/スマホ）のコンバージョン率**（ドーナツグラフ）

Looker Studioはデータの更新頻度をスケジュール設定できるため、毎朝自動でレポートが更新されるようにしておくことで、手動でのデータ抽出作業を省くことができます。

LINE広告のレポート画面に表示されるコンバージョン数とGA4側の数値は、計測の仕組みの違いにより一致しないことがほとんどです。「LINE広告レポート上のCV数」と「GA4で計測したCV数」を並べて把握しておくと、乖離の大きさから計測漏れや設定ミスを発見しやすくなります。

---

## まとめ

本記事では、LINE広告の効果をGA4・BigQueryを使って正確に計測するための手順をご説明しました。要点を整理します。

- **UTMパラメータの付与**：LINE広告のリンク先URLに`utm_source=line&utm_medium=cpc`を設定し、GA4に流入元情報を渡す
- **BigQueryエクスポートの活用**：GA4のデータをBigQueryへ連携することで、SQLによる柔軟な集計が可能になる
- **流入元の参照先**：`collected_traffic_source.manual_source / manual_medium`を使用し、`ga_session_id`は`UNNEST(event_params)`経由で取得する
- **CPA・ROASの算出**：セッションIDをキーにして購入イベントと紐付け、広告費と組み合わせて指標を計算する
- **Looker Studioで可視化**：定期的なモニタリングをダッシュボードで自動化する

広告計測の精度が上がると、予算配分の判断がしやすくなり、運用改善の仮説も立てやすくなります。まずはUTMパラメータの設定とBigQueryエクスポートの有効化から始めてみてください。

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
