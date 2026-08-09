# ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法

## はじめに

ECサイトを運営していると、「送料無料ラインをいくらに設定すべきか」という問いに直面する場面が多いかと思います。競合他社が3,000円以上で無料にしているから、うちも同じにしよう——そのような判断をされているケースも少なくありません。しかし実際のところ、自社の顧客行動データを根拠にした設定でなければ、売上機会の損失や収益の悪化につながるリスクがあります。

送料無料ラインの設定は、客単価・購買頻度・カゴ落ち率に直接影響する重要な施策です。ラインが低すぎると物流コストが増大し、高すぎると購入のハードルが上がってカゴ落ちが増えます。この「ちょうどいい閾値」を勘ではなくデータから導き出すことが、本記事のテーマです。

GA4のBigQueryエクスポートを活用すれば、実際の注文金額の分布や、購入直前に離脱したユーザーの行動パターンを詳細に分析できます。本記事では、BigQueryとSQLを使った具体的な分析手法を、非エンジニアの方にも理解しやすいよう丁寧に解説します。

<!-- ここから有料 -->

## 注文金額の分布を把握する

まず最初に行うべき分析は、既存の注文金額がどのような分布になっているかを把握することです。「送料無料ラインをどこに設定するか」を考えるには、現状の顧客がいくら使っているかを知ることが出発点になります。

GA4のBigQueryエクスポートでは、`purchase`イベントに紐づく`value`パラメータで購入金額を取得できます。以下のSQLを使うことで、注文金額の分布を集計できます。

```sql
WITH purchase_events AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
)

SELECT
  CASE
    WHEN purchase_value < 2000  THEN '〜2,000円未満'
    WHEN purchase_value < 3000  THEN '2,000〜3,000円未満'
    WHEN purchase_value < 4000  THEN '3,000〜4,000円未満'
    WHEN purchase_value < 5000  THEN '4,000〜5,000円未満'
    WHEN purchase_value < 7000  THEN '5,000〜7,000円未満'
    ELSE                             '7,000円以上'
  END AS price_range,
  COUNT(*) AS order_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  purchase_events
WHERE
  purchase_value IS NOT NULL
GROUP BY
  price_range
ORDER BY
  MIN(purchase_value)
```

このクエリを実行することで、どの価格帯に注文が集中しているかが一目でわかります。たとえば「3,000〜4,000円」に注文の30%以上が集中している場合、送料無料ラインを3,500円前後に設定することで、自然に上乗せ購入を促せる可能性があります。

> `your_project.analytics_XXXXXXX` の部分は、ご自身のプロジェクトIDとGA4のデータセットIDに置き換えてください。BigQueryのコンソールから確認できます。

## カゴ落ちセッションの注文金額帯を特定する

注文金額の分布を把握したら、次は「購入に至らなかったユーザー」がどこで離脱しているかを見ていきます。チェックアウトを開始したにもかかわらず購入を完了しなかったセッションは、送料の壁が原因の一つと考えられるため、特に重要な分析対象です。

以下のSQLでは、`begin_checkout`イベントを発生させたセッションのうち、`purchase`イベントが存在しないセッション（カゴ落ちセッション）を抽出し、その際のカート金額分布を集計しています。

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    event_name,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS cart_value
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('begin_checkout', 'purchase')
),

checkout_sessions AS (
  SELECT user_pseudo_id, session_id, MAX(cart_value) AS cart_value
  FROM sessions
  WHERE event_name = 'begin_checkout'
  GROUP BY user_pseudo_id, session_id
),

purchase_sessions AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM sessions
  WHERE event_name = 'purchase'
),

abandoned AS (
  SELECT c.*
  FROM checkout_sessions c
  LEFT JOIN purchase_sessions p
    ON c.user_pseudo_id = p.user_pseudo_id
    AND c.session_id = p.session_id
  WHERE p.session_id IS NULL
)

SELECT
  CASE
    WHEN cart_value < 2000 THEN '〜2,000円未満'
    WHEN cart_value < 3000 THEN '2,000〜3,000円未満'
    WHEN cart_value < 4000 THEN '3,000〜4,000円未満'
    WHEN cart_value < 5000 THEN '4,000〜5,000円未満'
    ELSE                        '5,000円以上'
  END AS cart_range,
  COUNT(*) AS abandoned_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  abandoned
WHERE
  cart_value IS NOT NULL
GROUP BY
  cart_range
ORDER BY
  MIN(cart_value)
```

カゴ落ちが特定の金額帯に集中している場合、その直上に送料無料ラインを設定することで、購入完了率の改善が期待できます。たとえば「3,000〜4,000円未満」のカゴ落ちが多い場合、送料無料ラインを4,000円から3,800円に下げるといった調整が選択肢になります。

## 流入元別に送料感度を分析する

同じ送料設定でも、流入チャネルによって顧客の価格感度は異なります。たとえば、SEO流入のユーザーは比較検討を経て訪問しているため、送料に敏感なケースが多い傾向があります。一方、指名検索やリピーターはブランドへの信頼があるため、送料に対してやや寛容な場合もあります。

GA4のBigQueryエクスポートでは、`collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` を使って流入元情報を取得できます。

```sql
WITH purchase_source AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
)

SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS order_count,
  ROUND(AVG(purchase_value), 0) AS avg_order_value,
  ROUND(MIN(purchase_value), 0) AS min_order_value,
  ROUND(APPROX_QUANTILES(purchase_value, 100)[OFFSET(50)], 0) AS median_order_value
FROM
  purchase_source
WHERE
  purchase_value IS NOT NULL
GROUP BY
  medium, source
ORDER BY
  order_count DESC
LIMIT 20
```

このクエリで流入元別の平均注文金額・中央値を比較することで、「どのチャネルのユーザーが高単価か」「どのチャネルで送料無料ラインに届かない注文が多いか」を把握できます。メルマガ経由のリピーターは比較的高単価であることが多く、逆に広告流入は単発購入で金額が低めになりがちという傾向も見えてくることがあります。

> `collected_traffic_source` が空になるケースでは、セッション開始時の `session_traffic_source_last_click` フィールドや `traffic_source` フィールドも補完的に活用できます。

## 送料無料ライン変更のA/Bテスト設計と効果測定

分析によって「最適な送料無料ライン候補」が絞り込めたら、次は実際に変更した場合の効果を測定する準備を整えます。BigQueryを使ったA/Bテストの効果測定は、GA4のカスタムディメンションとイベントパラメータを組み合わせることで実現できます。

テスト設計のポイントは以下の通りです。

- **テスト期間**: 購買サイクルを考慮し、最低でも2〜4週間の観測期間を設けることを推奨します
- **対象分割**: ユーザーをランダムに2グループに分割し、一方は現行ライン、もう一方は新ラインを適用します
- **計測指標**: 購入完了率（CVR）、平均注文金額（AOV）、購入件数あたりの粗利益を中心に評価します

テスト終了後の集計は以下のSQLで行えます（カスタムパラメータ `ab_variant` でグループを識別）。

```sql
SELECT
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ab_variant'
  ) AS variant,
  COUNT(*) AS purchase_count,
  ROUND(AVG(
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    )
  ), 0) AS avg_order_value
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240901' AND '20240930'
  AND event_name = 'purchase'
GROUP BY
  variant
```

A/Bテストを経ずに一気に変更するよりも、小規模な検証を先に行うことで、リスクを抑えながら意思決定できます。特に既存顧客の多いECサイトでは、急な変更が顧客体験を損ねる場合もあるため、段階的な検証が有効です。

## まとめ

本記事では、BigQueryとGA4の購買データを活用して、ECサイトの送料無料ラインを最適化するための分析手法を解説しました。要点を整理します。

1. **注文金額の分布分析**: 現状の顧客がいくら使っているかを把握し、注文が集中する価格帯の直上に送料無料ラインを置くことで上乗せ購入を促す
2. **カゴ落ち金額帯の特定**: チェックアウト開始後に離脱したセッションのカート金額を分析し、送料が壁になっている金額帯を特定する
3. **流入元別の送料感度分析**: チャネルごとに顧客の購買傾向が異なるため、流入元別に平均注文金額を把握する
4. **A/Bテストによる効果検証**: 候補ラインを実際に比較検証してから本格適用することで、施策の精度を高める

送料無料ラインの設定は、一度決めたら終わりではありません。季節性やキャンペーンの影響で顧客行動は変化するため、定期的なデータ確認と見直しを習慣化することが継続的な改善につながります。BigQueryを活用すれば、このサイクルを低コストで回し続けることが可能です。

まずは注文金額の分布クエリを実行するところから始めてみてください。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
