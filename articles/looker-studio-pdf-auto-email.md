---
title: "Looker Studioのレポートを自動でPDF化してメール送信する方法"
emoji: "📧"
type: "tech"
topics: ["lookerstudio","automation","email"]
published: false
---

## はじめに

「毎週月曜日に、Looker Studioのレポートをスクリーンショットで撮ってメールに貼り付けている」という作業をしていないでしょうか。

Looker Studioには標準でメール配信機能があり、レポートをPDF化して自動でメール送信できます。さらに、Google Apps Script（GAS）やCloud Schedulerを組み合わせれば、より柔軟な自動化も可能です。

この記事では、標準機能での設定方法から、GASを使った高度な自動化まで、段階的に解説します。

## 方法1: Looker Studio標準のメール配信スケジュール

Looker Studioには「メール配信のスケジュール設定」が標準で搭載されています。追加のツールなしで自動配信が設定できます。

### 設定手順

1. Looker Studioでレポートを開く（閲覧モード）
2. 右上の「共有」ボタンの隣にある「▼」をクリック
3. 「メール配信のスケジュール」を選択
4. 以下を設定する

```
宛先: 受信者のメールアドレス（複数可）
件名: [自動] EC月次レポート - {{date}}
ページ: 配信するページを選択
開始日: 配信開始日
繰り返し: 毎日/毎週/毎月
時刻: 配信時刻
```

5. 「保存」をクリック

:::message
メール配信スケジュールはレポートの「オーナー」または「編集者」のみが設定できます。閲覧専用の共有リンクでは設定できません。
:::

### 標準機能の制限

| 項目 | 制限 |
|---|---|
| 配信形式 | PDFのみ（CSV等は不可） |
| 配信頻度 | 毎日/毎週/毎月の固定パターン |
| 宛先 | Googleアカウント保有者のみ |
| フィルタの適用 | レポートのデフォルトフィルタが適用される |
| ページ選択 | 配信するページを選択可能 |
| 配信数の上限 | 1レポートにつき20スケジュールまで |

基本的な定期配信であれば、この標準機能で十分対応できます。

### 配信内容をカスタマイズするポイント

メール配信では「レポートのデフォルトの日付範囲」が適用されます。そのため、レポートの日付フィルタのデフォルト値を適切に設定しておくことが重要です。

```
月次レポートの場合: デフォルト日付を「先月」に設定
週次レポートの場合: デフォルト日付を「先週」に設定
```

設定方法:
1. レポート編集画面で日付コントロールを選択
2. 「デフォルトの日付範囲」で「詳細設定」を選択
3. 開始日: 今月の初日からN日前、終了日: 今日からN日前のように設定

## 方法2: Google Apps Script（GAS）で自動化する

Looker Studioの標準機能では対応できない要件がある場合、GASを使ってより柔軟な自動化が可能です。

### GASでできること

- Looker StudioのレポートURLにアクセスしてPDFを取得
- メール本文にKPIサマリーを記載
- 宛先を条件分岐する（売上が閾値以下のときだけ通知など）
- Google DriveにPDFを保存
- Slackに通知

### GASのコード例: レポートPDFをメール送信

```javascript
function sendLookerStudioReport() {
  // レポートのURL（PDF出力用パラメータ付き）
  var reportUrl = 'https://lookerstudio.google.com/reporting/REPORT_ID/page/PAGE_ID';
  var pdfUrl = reportUrl + '/export?format=pdf';

  // PDFをダウンロード
  var options = {
    headers: {
      Authorization: 'Bearer ' + ScriptApp.getOAuthToken()
    },
    muteHttpExceptions: true
  };

  var response = UrlFetchApp.fetch(pdfUrl, options);

  if (response.getResponseCode() === 200) {
    var pdfBlob = response.getBlob().setName('EC_Report_' + Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyyMMdd') + '.pdf');

    // メール送信
    MailApp.sendEmail({
      to: 'manager@example.com',
      subject: 'EC月次レポート - ' + Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy/MM/dd'),
      body: createEmailBody(),
      attachments: [pdfBlob]
    });

    Logger.log('レポート送信完了');
  } else {
    Logger.log('PDFの取得に失敗: ' + response.getResponseCode());
  }
}

function createEmailBody() {
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy年MM月dd日');
  return [
    today + ' のレポートをお送りします。',
    '',
    '添付のPDFにて、以下の内容をご確認ください。',
    '・売上推移',
    '・チャネル別パフォーマンス',
    '・商品カテゴリ別売上',
    '',
    '詳細はLooker Studioでご覧いただけます。',
    'https://lookerstudio.google.com/reporting/REPORT_ID'
  ].join('\n');
}
```

### GASのトリガー設定

1. GASエディタで「トリガー」（時計アイコン）をクリック
2. 「トリガーを追加」をクリック
3. 以下を設定

```
関数: sendLookerStudioReport
デプロイ: Head
イベントソース: 時間主導型
トリガータイプ: 週ベースのタイマー
曜日: 毎週月曜日
時刻: 午前9時〜10時
```

## 方法3: BigQuery × GASでKPIサマリーメールを送る

PDFだけでなく、メール本文にKPIの数値を直接記載すると、PDFを開かなくても要点が把握できます。

### BigQueryからKPIを取得するGAS

```javascript
function getKpiFromBigQuery() {
  var projectId = 'your-project-id';
  var query = `
    SELECT
      COUNT(DISTINCT CONCAT(
        user_pseudo_id,
        CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
      )) AS sessions,
      COUNTIF(event_name = 'purchase') AS purchases,
      IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
    FROM
      \`project.analytics_XXXXXXX.events_*\`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
        AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  `;

  var request = {
    query: query,
    useLegacySql: false
  };

  var response = BigQuery.Jobs.query(request, projectId);
  var rows = response.rows;

  if (rows && rows.length > 0) {
    return {
      sessions: rows[0].f[0].v,
      purchases: rows[0].f[1].v,
      revenue: rows[0].f[2].v
    };
  }
  return null;
}

function sendWeeklyKpiEmail() {
  var kpi = getKpiFromBigQuery();
  if (!kpi) {
    Logger.log('KPIの取得に失敗');
    return;
  }

  var revenue = Number(kpi.revenue).toLocaleString();
  var cvr = (kpi.purchases / kpi.sessions * 100).toFixed(2);

  var body = [
    '先週のEC KPIサマリー',
    '========================',
    '',
    '売上: ¥' + revenue,
    'セッション: ' + Number(kpi.sessions).toLocaleString(),
    '購入数: ' + kpi.purchases + '件',
    'CVR: ' + cvr + '%',
    '',
    '詳細レポートはこちら:',
    'https://lookerstudio.google.com/reporting/REPORT_ID'
  ].join('\n');

  MailApp.sendEmail({
    to: 'manager@example.com',
    subject: '先週のEC KPIサマリー - 売上¥' + revenue,
    body: body
  });
}
```

:::message
GASからBigQueryを使う場合は、GASエディタの「サービス」から「BigQuery API」を有効化する必要があります。
:::

## Google DriveにPDFを自動保存する

メール配信と合わせて、Google DriveにPDFを保存しておくと、過去のレポートを遡って確認できます。

```javascript
function savePdfToDrive(pdfBlob) {
  var folderId = 'YOUR_FOLDER_ID';
  var folder = DriveApp.getFolderById(folderId);
  var fileName = 'EC_Report_' + Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyyMMdd') + '.pdf';
  folder.createFile(pdfBlob.setName(fileName));
  Logger.log('Google Driveに保存: ' + fileName);
}
```

## 運用のベストプラクティス

### 配信スケジュールの設計

| レポートの種類 | 配信頻度 | 配信曜日・時刻 |
|---|---|---|
| 日次KPIサマリー | 毎日 | 毎朝9:00 |
| 週次レポート | 毎週 | 月曜 10:00 |
| 月次レポート | 毎月 | 月初3営業日目 |

### 配信失敗時の対策

GASのトリガーが失敗した場合、GASエディタの「実行数」タブでエラーログを確認できます。よくある原因は以下の通りです。

- BigQueryのクォータ超過
- Looker Studioのレポートが削除・移動された
- GASの実行時間制限（6分）を超過

### レポートの鮮度を保証する

メール配信されるPDFは、配信時点のキャッシュに基づきます。最新データを保証したい場合は、配信時刻の前にBigQueryのビューが更新されるようにスケジュールを調整してください。

## まとめ

Looker Studioのレポート自動配信は、3つのレベルで実装できます。

1. **標準機能**: 設定画面からスケジュールを指定するだけ（最も簡単）
2. **GAS**: PDF取得＋メール送信を自動化（カスタマイズ可能）
3. **GAS + BigQuery**: KPI数値を本文に含むサマリーメール（最も情報価値が高い）

レポート配信の自動化は、ダッシュボード運用の定着率を大きく向上させます。「見に行く」から「届く」に変えることで、データ活用の習慣が組織に根付きます。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
