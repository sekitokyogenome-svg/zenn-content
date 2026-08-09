# 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル

## はじめに

定期購入（サブスクリプション）型のECサービスを運営していると、「なぜ急に解約が増えたのか」「どのタイミングで兆候が現れていたのか」という問いに直面することがあります。解約は一度発生してしまうと取り戻すことが難しく、LTV（顧客生涯価値）への影響も大きいため、できるだけ早期に予兆を察知してアプローチすることが重要です。

GA4（Google Analytics 4）は、サイト上でのユーザー行動をイベント単位で記録しており、BigQueryへのデータエクスポート機能を使うことで、より詳細な分析が可能になります。実は、解約する顧客の多くは事前にマイページへのアクセス頻度が落ちる、解約フォームを閲覧する、ヘルプページを何度も訪れるといった行動変化を示しています。これらの行動ログはGA4に蓄積されており、BigQueryでSQLを使って分析することで、解約予兆スコアを算出するモデルを構築できます。

この記事では、GA4のBigQueryエクスポートデータを活用して、定期購入ECの解約予兆を検知する実践的なSQLモデルを紹介します。エンジニアでない方にも概念が伝わるよう、各SQLの意図についても丁寧に解説しています。

<!-- ここから有料 -->

## GA4×BigQueryエクスポートの基本構造を理解する

GA4のBigQueryエクスポートでは、`analytics_<プロパティID>.events_*` というテーブルにデータが日次で蓄積されます。各行は1件のイベント（ページビュー、クリック、購入など）を表しており、ユーザーIDやセッション情報、イベントパラメータが格納されています。

注意点として、`ga_session_id` はカラムとして直接参照できず、`event_params` という配列フィールドをUNNESTして取り出す必要があります。また、流入元の情報は `collected_traffic_source.manual_medium` や `collected_traffic_source.manual_source` を参照します。

以下のクエリは、直近30日間のユーザーごとのセッション数と主要イベントの発生回数を集計する基本的な骨格です。

```sql
-- GA4イベントログの基本集計（直近30日）
SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  event_name,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  event_date
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
```

このクエリを土台にして、解約予兆に関連するシグナルを抽出していきます。

## 解約予兆シグナルとなる行動パターンを定義する

解約予兆の検知において重要なのは、「解約に至ったユーザーが事前にどのような行動をとっていたか」を過去データから学ぶことです。定期購入ECで一般的に観察される解約前行動には以下のものがあります。

- **解約・退会関連ページの閲覧**（例：`/mypage/cancel`、`/unsubscribe`）
- **マイページへのアクセス頻度の低下**
- **商品詳細ページへの訪問が減少し、ヘルプ・FAQ閲覧が増加**
- **メールからの流入（メルマガ）が途絶える**

以下のSQLでは、ユーザーごとに解約関連ページの閲覧回数・マイページ訪問数・ヘルプページ訪問数をカウントします。

```sql
-- ユーザーごとの行動シグナル集計
WITH raw_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    event_name,
    event_date
  FROM
    `your_project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'page_view'
)

SELECT
  user_pseudo_id,
  COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
    AS cancel_page_views,
  COUNTIF(page_location LIKE '%/mypage%')
    AS mypage_views,
  COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
    AS help_page_views,
  COUNT(DISTINCT event_date) AS active_days
FROM raw_events
GROUP BY user_pseudo_id
```

このようにシグナルを数値化することで、次のステップとなるスコアリングへの入力データを準備できます。

## 解約予兆スコアをSQLで算出する

各シグナルに重みをつけてスコアを計算します。重みの設定はあくまで仮のものであり、実際には過去の解約ユーザーのデータと照合してチューニングすることが望ましいです。

以下のモデルでは「解約ページを見た回数」を最も重視し、「アクティブ日数の少なさ」を解約リスクの底上げ要因として扱っています。

```sql
-- 解約予兆スコアの算出
WITH behavior_signals AS (
  -- （前述のCTEを再利用）
  SELECT
    user_pseudo_id,
    COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
      AS cancel_page_views,
    COUNTIF(page_location LIKE '%/mypage%')
      AS mypage_views,
    COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
      AS help_page_views,
    COUNT(DISTINCT event_date) AS active_days
  FROM (
    SELECT
      user_pseudo_id,
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location') AS page_location,
      event_date
    FROM
      `your_project.analytics_XXXXXXX.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
      AND event_name = 'page_view'
  )
  GROUP BY user_pseudo_id
)

SELECT
  user_pseudo_id,
  cancel_page_views,
  mypage_views,
  help_page_views,
  active_days,
  -- スコアリング（重みは要チューニング）
  ROUND(
    (cancel_page_views * 40)
    + (GREATEST(0, 5 - active_days) * 5)
    + (help_page_views * 3)
    + (GREATEST(0, 10 - mypage_views) * 2)
  , 1) AS churn_risk_score
FROM behavior_signals
ORDER BY churn_risk_score DESC
```

スコアが高いユーザーほど解約リスクが高いと判断できます。このリストをLooker Studioに連携して可視化したり、CSVエクスポートしてメール配信ツールのリストとして活用したりすることが可能です。

> スコアの閾値（例：40点以上をハイリスク）は、実際の解約データと照合しながら調整することをお勧めします。まずは過去の解約ユーザーにこのスコアを遡って当てはめ、どの閾値が実態に合っているか確認してみてください。

## 流入チャネル別に解約リスクを分析する

解約予兆スコアに流入チャネルの情報を組み合わせると、「どの集客経路からきたユーザーが解約しやすいか」という傾向が見えてきます。たとえば、広告経由で獲得したユーザーがオーガニック流入に比べて短期解約しやすい、という仮説を検証できます。

```sql
-- 流入チャネル別の解約リスク分布
SELECT
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS avg_session_count,
  COUNTIF(
    EXISTS(
      SELECT 1
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'page_location'
        AND ep.value.string_value LIKE '%/cancel%'
    )
  ) AS users_with_cancel_view
FROM
  `your_project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  traffic_medium,
  traffic_source
ORDER BY
  users_with_cancel_view DESC
```

このクエリにより、解約ページ閲覧者の流入元比率を把握できます。特定のキャンペーンや媒体から流入したユーザーに解約リスクが集中しているようであれば、獲得施策そのものの見直しにつながります。

## 検知後のアクションプランを設計する

スコアリングで解約リスクユーザーを特定した後、どのようなアクションを取るかが施策の核心です。以下の対応フローが参考になります。

**ハイリスクユーザー（スコア40以上）への対応例：**

1. **パーソナライズメールの送信**：「ご利用状況のご確認」という名目で、継続特典やサポート案内を送る
2. **マイページでのポップアップ表示**：解約フォームへの遷移前に「休止オプション」「プラン変更」を提示する
3. **カスタマーサポートからのアウトバウンド**：高単価プランのユーザーであれば、電話やチャットでの個別フォローも検討する

> 解約を検知してから対応するのではなく、解約手続きの完了前に介入できる設計（解約フォームへの誘導前に代替提案を挟む）がLTV向上に効果的です。GA4のイベント設計とBigQueryの組み合わせは、こうした施策の精度を高めるために活用できます。

BigQueryのスケジュールクエリ機能を使えば、このスコアリングを毎日自動実行してLooker Studioのダッシュボードに反映させることも可能です。

## まとめ

この記事では、GA4のBigQueryエクスポートデータを活用した定期購入EC向けの解約予兆検知モデルを紹介しました。要点を整理します。

- `event_params` をUNNESTすることで、GA4の各種パラメータ（セッションIDやページURL）を取得できる
- 解約ページ閲覧・マイページ訪問低下・ヘルプページ増加が主要な解約シグナルとなる
- シグナルに重みをつけてスコアリングすることで、リスクユーザーを優先順位付きで抽出できる
- 流入チャネルとの掛け合わせにより、獲得施策の課題も可視化できる
- スコアリング結果をメール配信やポップアップ施策と連携することで、解約を事前に防ぐアプローチが取れる

次のアクションとしては、まず自社のGA4データをBigQueryにエクスポートした上で、解約ページのURLパターンを確認し、上記のSQLをカスタマイズして試してみることをお勧めします。小規模なテスト分析から始めることで、自社データにフィットした予兆モデルに育てていけます。

---

この記事は「EC データ分析 実務ガイド ― 25の課題と、その解き方」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
