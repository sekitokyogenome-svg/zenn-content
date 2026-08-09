---
title: "広告クリエイティブ別のLTVをBigQueryで追跡して勝ちパターンを見つける"
emoji: "🎨"
type: "idea"
topics: ["bigquery","advertising","ec","googleanalytics","sql"]
published: false
---

## はじめに

「広告費をかけているのに、どのクリエイティブが本当に利益に貢献しているかわからない」という悩みを抱えているEC事業者の方は多いのではないでしょうか。クリック率（CTR）やコンバージョン率（CVR）を指標として最適化するのは一般的ですが、それだけでは「初回購入後に何度もリピートしてくれる優良顧客」をどのクリエイティブが連れてきているかは見えてきません。

LTV（Life Time Value：顧客生涯価値）という視点を加えると、広告の評価軸が大きく変わります。一回の購入金額が低くても、その後リピートを繰り返してくれる顧客を獲得しているクリエイティブのほうが、長期的には大きな利益をもたらします。逆に、CVRが高くてもリピートしない顧客ばかりを集めているクリエイティブは、費用対効果が低い可能性があります。

本記事では、GA4のBigQueryエクスポートデータを活用して、広告クリエイティブ（キャンペーン・クリエイティブ単位）ごとのLTVを追跡し、「勝ちパターン」を発見するSQLの考え方と実装例を紹介します。専門的なエンジニアスキルがなくても概念を理解できるよう、丁寧に解説していきます。

---

## 広告クリエイティブとLTVを紐づける考え方

まず前提として、「クリエイティブ別のLTV追跡」がなぜ難しいのかを整理しておきましょう。

広告クリエイティブとLTVを紐づけるには、「この顧客は、どのクリエイティブを経由して最初にやってきたか」というファーストタッチの情報を、その後の購買履歴とセットで保持しておく必要があります。GA4はセッション単位でUTMパラメータを記録しますが、デフォルトでは複数回の訪問をまたいだ顧客単位の集計は容易ではありません。

BigQueryにGA4データをエクスポートすると、イベント単位の生データが手に入ります。ここから`user_pseudo_id`をキーにして、同一ユーザーの最初のセッション（初回流入）と、その後の購買イベントを結びつけることができます。これにより「どのキャンペーン・クリエイティブ経由で獲得した顧客が、何回・いくら購入したか」を集計できるようになります。

:::message
UTMパラメータの`utm_content`にクリエイティブIDやクリエイティブ名を設定しておくと、BigQuery上でクリエイティブ単位の集計が可能になります。広告配信前にUTM設計を整えておくことが重要です。
:::

---

## BigQueryでの初回流入情報の取得

GA4のBigQueryエクスポートでは、`ga_session_id`はイベントの直接プロパティとしては取得できません。`event_params`配列をUNNESTして取り出す必要があります。また、流入元の情報は`collected_traffic_source`フィールドを使います。

以下のクエリは、各ユーザーの最初のセッションにおける流入情報（UTMパラメータ）を抽出するものです。

```sql
-- ユーザーごとの初回流入情報を取得する
WITH first_touch AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_event_timestamp,
    -- ga_session_id は event_params から取得する（直接参照不可）
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
      LIMIT 1
    ) AS session_id,
    collected_traffic_source.manual_medium   AS first_medium,
    collected_traffic_source.manual_source   AS first_source,
    collected_traffic_source.manual_campaign_name AS first_campaign,
    collected_traffic_source.manual_content  AS first_creative
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    session_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative
),
-- 各ユーザーの最初のセッションのみを残す
first_session AS (
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM first_touch
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id
    ORDER BY first_event_timestamp ASC
  ) = 1
)

SELECT * FROM first_session
LIMIT 100;
```

`your_project.analytics_XXXXXXX`の部分は、実際のプロジェクトIDとGA4プロパティIDに置き換えてください。`_TABLE_SUFFIX`で期間を絞り込むことで、クエリコストを抑えられます。

---

## クリエイティブ別LTVを集計するSQLクエリ

初回流入情報を取得できたら、次はその顧客が後日どれだけ購入したかを集計します。GA4でeコマースイベント（`purchase`）を計測している場合、`event_name = 'purchase'`でフィルタし、購入金額を合計することでLTVを算出できます。

```sql
WITH first_session AS (
  -- （上記のfirst_sessionクエリをここに挿入）
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM (
    SELECT
      user_pseudo_id,
      collected_traffic_source.manual_medium   AS first_medium,
      collected_traffic_source.manual_source   AS first_source,
      collected_traffic_source.manual_campaign_name AS first_campaign,
      collected_traffic_source.manual_content  AS first_creative,
      MIN(event_timestamp) AS first_event_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY user_pseudo_id
        ORDER BY MIN(event_timestamp) ASC
      ) AS rn
    FROM
      `your_project.analytics_XXXXXXX.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name = 'session_start'
      AND collected_traffic_source.manual_medium IS NOT NULL
    GROUP BY
      user_pseudo_id,
      first_medium,
      first_source,
      first_campaign,
      first_creative
  )
  WHERE rn = 1
),

-- 購買イベントの集計
purchases AS (
  SELECT
    user_pseudo_id,
    event_timestamp AS purchase_timestamp,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'transaction_id'
      LIMIT 1
    ) AS transaction_id
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
    AND ecommerce.purchase_revenue IS NOT NULL
),

-- 初回流入情報と購買を結合してLTVを計算
user_ltv AS (
  SELECT
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source,
    COUNT(DISTINCT p.transaction_id)          AS purchase_count,
    ROUND(SUM(p.revenue), 2)                  AS total_revenue
  FROM first_session fs
  LEFT JOIN purchases p
    ON fs.user_pseudo_id = p.user_pseudo_id
  GROUP BY
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source
)

-- クリエイティブ別に集計
SELECT
  first_campaign,
  first_creative,
  first_medium,
  first_source,
  COUNT(DISTINCT user_pseudo_id)              AS user_count,
  SUM(purchase_count)                         AS total_orders,
  ROUND(AVG(total_revenue), 2)                AS avg_ltv_per_user,
  ROUND(SUM(total_revenue), 2)                AS total_revenue,
  ROUND(SUM(purchase_count) / NULLIF(COUNT(DISTINCT user_pseudo_id), 0), 2) AS avg_orders_per_user
FROM user_ltv
GROUP BY
  first_campaign,
  first_creative,
  first_medium,
  first_source
ORDER BY
  avg_ltv_per_user DESC;
```

このクエリを実行すると、クリエイティブ（`first_creative`）ごとに、獲得したユーザー数・合計注文数・1人当たりの平均LTV・総売上が出力されます。

:::message
`first_creative`はUTMの`utm_content`パラメータに対応しています。広告配信時に`utm_content=creative_A`のようにクリエイティブIDを設定しておくことで、クリエイティブ単位の分析が可能になります。設定がない場合は`first_campaign`（キャンペーン名）単位での分析に留まります。
:::

---

## 勝ちパターンの見つけ方と改善サイクル

クエリを実行して数値が出たら、次は「どこを見て判断するか」が重要です。単純にLTVが高いクリエイティブを選ぶだけでなく、以下の観点を組み合わせると判断の精度が上がります。

**1. 平均LTV × ユーザー数のバランスを見る**

LTVが高くてもユーザー数（サンプル数）が少ない場合は、統計的な信頼性が低い可能性があります。`user_count`が50件以上のクリエイティブを比較の対象にするとよいでしょう。

**2. 1人当たりの注文回数（リピート率）を見る**

`avg_orders_per_user`が1に近いクリエイティブは「一度きりの購入」が多い傾向があります。2以上であれば、そのクリエイティブが「リピーターを連れてくる」という特性を持つ可能性があります。

**3. 流入媒体ごとにセグメントを切る**

`first_medium`でフィルタすると、「Instagram広告の中でのクリエイティブ比較」「Google広告の中でのクリエイティブ比較」といった媒体内比較ができます。媒体が異なるとユーザー属性も変わるため、媒体をまたいだ比較は慎重に行いましょう。

**4. 改善サイクルへの組み込み**

勝ちパターンが見えてきたら、そのクリエイティブの「何が効いているか」を仮説化します。訴求コピーなのか、画像のビジュアルなのか、オファー内容なのか。仮説をもとに新しいクリエイティブを作成し、同じ分析を繰り返すことで、少しずつ精度が上がっていきます。月次でこのクエリを実行して結果を記録しておくと、長期的なトレンドも見えてきます。

---

## まとめ

本記事では、GA4のBigQueryエクスポートデータを使って広告クリエイティブ別のLTVを追跡する方法を紹介しました。要点を整理します。

- **クリエイティブ×LTVの分析には「初回流入の紐付け」が必要**。`user_pseudo_id`をキーに、ファーストタッチのUTM情報を保持する。
- **`ga_session_id`はUNNEST(event_params)経由で取得**。直接参照はできないため、正しいクエリ設計が必要。
- **流入元は`collected_traffic_source.manual_medium`と`manual_source`を使用**。
- **UTMパラメータの設計が分析の精度を左右する**。`utm_content`にクリエイティブIDを入れる設計を広告配信前に整えておく。
- **LTVだけでなく、リピート回数やユーザー数のバランスも見ながら判断する**。

次のアクションとしては、まず自社のGA4データがBigQueryにエクスポートされているかを確認し、UTMパラメータの命名規則を整備することから始めてみてください。データの蓄積と分析の仕組みを整えることで、広告運用の意思決定をより客観的なデータに基づいて行えるようになります。

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
