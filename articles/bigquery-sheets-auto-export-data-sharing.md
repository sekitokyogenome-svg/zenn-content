---
title: "BigQueryからGoogleスプレッドシートに自動出力して非エンジニアとデータ共有する"
emoji: "📋"
type: "tech"
topics: ["bigquery","googlecloud","sql","googleanalytics","dataengineering"]
published: false
book_only: true
---

## はじめに

「BigQueryでSQLを書けるようになったはいいけれど、結果を社内の担当者や取引先に渡す方法がわからない」——そういった悩みを抱えていませんか？

BigQueryはデータ分析の強力なツールですが、SQLに不慣れな非エンジニアのメンバーが直接クエリを実行するのはハードルが高いものです。かといって、分析担当者が毎日手動でCSVをエクスポートしてSlackやメールで送るのは、時間がかかる上にミスの温床にもなります。

そこで有効なのが、BigQueryのクエリ結果をGoogleスプレッドシートに自動的に出力するしくみです。スプレッドシートであれば、ExcelライクなUIで誰でもデータを確認でき、グラフ作成やフィルタリングも直感的に操作できます。本記事では、BigQueryからスプレッドシートへの自動出力方法を、GA4のBigQueryエクスポートデータを例にとりながら丁寧に解説します。

---

## BigQueryとGoogleスプレッドシートを連携させる方法の全体像

BigQueryのデータをスプレッドシートに渡す方法は、大きく3つあります。

1. **BigQueryに接続されたスプレッドシートの「コネクテッドシート」機能を使う**
2. **スケジュールされたクエリ（Scheduled Query）でGCSやBigQueryテーブルに出力し、スプレッドシートからインポートする**
3. **Google Apps Script（GAS）でBigQuery APIを呼び出して定期実行する**

中小EC・Webコンサル向けに実用的なのは、**1のコネクテッドシート**と**3のGAS定期実行**の組み合わせです。コネクテッドシートはGoogleが提供する公式機能で、追加のコーディングなしにスプレッドシート上でBigQueryのデータを参照・集計できます。GASによる自動化は、毎朝9時に最新データを自動更新してチームメンバーに共有する、といった運用に向いています。

まずはコネクテッドシートの基本を押さえてから、GASによる自動化の手順へと進みましょう。

---

## コネクテッドシートでBigQueryを直接参照する

Googleスプレッドシートには「コネクテッドシート（Connected Sheets）」という機能があり、BigQueryのテーブルやクエリ結果をスプレッドシートのピボットテーブル・グラフとして可視化できます。利用にはBigQueryの課金が有効になっていること、およびGoogle Workspaceのビジネスプラン以上が必要です。

### 設定手順

1. Googleスプレッドシートを新規作成し、メニューから **データ → データコネクタ → BigQueryに接続** を選択します。
2. プロジェクト・データセット・テーブルを選択するか、カスタムクエリを入力します。
3. 「接続」をクリックすると、スプレッドシート上にBigQueryのデータソースが追加されます。
4. そのままピボットテーブルやグラフとして分析できます。

### GA4データをコネクテッドシートで参照するカスタムクエリ例

以下は、GA4のBigQueryエクスポートテーブルから流入元ごとのセッション数と購入数を集計するクエリです。

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `your_project.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  1, 2
ORDER BY
  sessions DESC
LIMIT 100
```

:::message
`your_project.analytics_XXXXXXXXX` の部分は、ご自身のGCPプロジェクトIDとGA4プロパティIDに置き換えてください。コネクテッドシートのカスタムクエリ入力欄にそのまま貼り付けて使用できます。
:::

---

## Google Apps Scriptで毎朝スプレッドシートを自動更新する

コネクテッドシートは手動で「更新」を押さないと最新データに切り替わりません。チームへの定期レポートには、GASで自動更新するしくみが便利です。

### GASスクリプトの概要

スプレッドシートのツールメニューから **Apps Script** を開き、以下のコードを貼り付けます。

```javascript
function exportBigQueryToSheet() {
  const projectId = 'your-gcp-project-id';
  const spreadsheetId = SpreadsheetApp.getActiveSpreadsheet().getId();
  const sheetName = 'GA4レポート';

  const query = `
    SELECT
      collected_traffic_source.manual_medium AS medium,
      collected_traffic_source.manual_source AS source,
      COUNT(DISTINCT
        (SELECT value.string_value
         FROM UNNEST(event_params) AS ep
         WHERE ep.key = 'ga_session_id')
      ) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases
    FROM
      \`${projectId}.analytics_XXXXXXXXX.events_*\`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    GROUP BY 1, 2
    ORDER BY sessions DESC
    LIMIT 100
  `;

  const request = {
    query: query,
    useLegacySql: false,
    timeoutMs: 30000
  };

  const response = BigQuery.Jobs.query(request, projectId);
  const rows = response.rows;

  if (!rows || rows.length === 0) return;

  const sheet = SpreadsheetApp.getActiveSpreadsheet()
    .getSheetByName(sheetName) ||
    SpreadsheetApp.getActiveSpreadsheet().insertSheet(sheetName);

  sheet.clearContents();
  sheet.appendRow(['流入メディア', '流入ソース', 'セッション数', '購入数']);

  rows.forEach(row => {
    sheet.appendRow(row.f.map(cell => cell.v));
  });
}
```

### 定期実行の設定

GASエディタの左メニューから **トリガー（時計アイコン）** を選択し、以下のように設定します。

- 実行する関数: `exportBigQueryToSheet`
- イベントのソース: 時間主導型
- 時間ベースのトリガーのタイプ: 日付ベースのタイマー
- 時刻: 午前8時〜9時

これにより、毎朝9時前に前日までのデータが自動でスプレッドシートに書き込まれます。

:::message
GASからBigQueryを呼び出すには、Apps ScriptのサービスとしてBigQuery APIを有効にする必要があります。GASエディタの左メニュー「サービス」から「BigQuery API」を追加してください。また、実行アカウントにBigQueryのジョブ実行権限（`roles/bigquery.jobUser`）が付与されていることをご確認ください。
:::

---

## スプレッドシートを非エンジニアが使いやすい形に整える

データが自動で書き込まれても、見やすくなければ活用されません。以下のひと工夫で、非エンジニアのメンバーが自走できるレポートシートになります。

### 条件付き書式でデータを色分けする

購入数が0のセッションは赤系、10以上は緑系に色分けするだけで、どの流入チャネルが貢献しているかが一目でわかります。スプレッドシートの **書式 → 条件付き書式** から設定できます。

### ドロップダウンフィルターを追加する

流入メディア列の上にフィルタービューを設定しておくと、非エンジニアのメンバーが「オーガニック検索だけ見たい」「SNS流入だけ抽出したい」といった操作を自力でできるようになります。

### 共有設定と更新通知

スプレッドシートの共有設定で、報告相手に「閲覧者」または「コメント可」の権限を付与します。GASスクリプトの末尾に以下を追加すれば、データ更新後にSlackやメールで通知することも可能です。

```javascript
// メール通知を追加する場合
MailApp.sendEmail({
  to: 'team@example.com',
  subject: '【GA4レポート】本日のデータが更新されました',
  body: 'スプレッドシートを確認してください: https://docs.google.com/spreadsheets/d/' + spreadsheetId
});
```

---

## まとめ

本記事では、BigQueryのデータをGoogleスプレッドシートに自動出力して非エンジニアと共有する方法を解説しました。

- **コネクテッドシート**を使えば、コーディングなしでBigQueryのデータをスプレッドシートのピボットテーブル・グラフに活用できます
- **Google Apps Script**を使えば、毎日決まった時刻にデータを自動更新し、チームへの通知まで自動化できます
- スプレッドシート側の条件付き書式やフィルタービューを整えることで、非エンジニアのメンバーが自走できるレポート環境になります

GA4のBigQueryエクスポートデータと組み合わせることで、流入チャネル別のセッション数や購入数を毎朝自動で可視化する体制が構築できます。まずはコネクテッドシートで手軽に試してみて、定期配信が必要になったらGASへステップアップするのがおすすめです。

## 関連記事

- [BigQueryでGA4のページ別滞在時間を正しく集計する方法](https://zenn.dev/web_benriya/articles/bigquery-ga4-page-time-on-page)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)
- [Claude CodeでBigQueryのSQLを自然言語から自動生成する](https://zenn.dev/web_benriya/articles/claude-code-bigquery-sql-auto-generate)
- [BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）](https://zenn.dev/web_benriya/articles/ga4-bigquery-bounce-rate-calculation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
