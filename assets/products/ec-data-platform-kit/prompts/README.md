# Claude Code プロンプト集

記事中で実際に使っているプロンプト。
`{}` で囲まれた箇所は自社のデータに置き換えて使う。

## 01. AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法

出典: `articles/ai-agent-bigquery-query-review-cost-reduction.md`

```text
以下のBigQueryクエリをコスト最適化の観点でレビューしてください。
改善すべき点があれば、修正後のクエリも合わせて提示してください。

【レビュー観点】
- SELECT * の使用有無
- パーティションの活用状況（_TABLE_SUFFIXまたはevent_dateによる絞り込み）
- 不要なフルスキャンの有無
- JOINの効率性

【クエリ】
{query}
```

## 02. AI×BigQueryでEC商品説明文のA/Bテスト結果を自動分析・改善提案する仕組み

出典: `articles/ai-bigquery-ec-product-desc-ab-test-auto.md`

```text
以下は「{product_name}」の商品説明文A/Bテスト結果（過去30日）です。

{ab_result_csv}

このデータをもとに、以下の観点で分析と提案をしてください。
1. どちらのバリアントがより良いパフォーマンスを示しているか
2. 購入率・カート追加率の差異から読み取れる仮説
3. 次のA/Bテストに向けた具体的な改善案（商品説明文の観点から3点）

なお、サンプル数が少ない場合はその旨も言及してください。
回答は日本語で、箇条書きを交えて読みやすくまとめてください。
```

## 03. BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】

出典: `articles/bigquery-claude-code-anomaly-detection-alert.md`

```text
以下のEC売上異常データについて、日本語で簡潔なアラートメッセージを作成してください。
考えられる原因候補を3つ挙げてください。

日付: {row['event_date']}
セッション数: {row['sessions']}（7日平均: {row['avg_sessions_7d']:.0f}）
売上: ¥{row['revenue']:,.0f}（7日平均: ¥{row['avg_revenue_7d']:,.0f}）
検出された異常: {', '.join(alerts)}

フォーマット:
- 1行目にサマリ
- 箇条書きで原因候補
- 最後に推奨アクション
```

## 04. BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み

出典: `articles/bigquery-claude-code-monthly-business-report.md`

```text
以下のKPIデータから月次事業報告書をMarkdown形式で作成してください。

## データ
{json.dumps(kpi_data, ensure_ascii=False, indent=2)}

## レポート要件
1. エグゼクティブサマリ（3行以内）
2. 主要KPIの前月比較（上昇/下降の矢印付き）
3. チャネル別パフォーマンスのテーブル
4. 課題と改善提案（3つ以内）
5. 来月のアクションアイテム

数値にはカンマ区切りを使い、割合は小数点1桁まで表示してください。
```

## 05. Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った

出典: `articles/claude-code-bigquery-ad-budget-optimization.md`

```text
以下のEC広告チャネル別パフォーマンスデータに基づき、
予算配分の見直し提案書をMarkdown形式で作成してください。

## データ
{json.dumps(analysis_data, ensure_ascii=False, indent=2)}

## 提案書の構成
1. エグゼクティブサマリ（3行以内）
2. 現状分析
   - チャネル別ROAS一覧（テーブル）
   - 課題のあるチャネルの特定
3. 予算再配分の提案
   - 現在の配分と推奨配分の比較テーブル
   - 増額チャネルの根拠
   - 減額チャネルの根拠
4. 期待される効果
   - 推定売上増加額
   - 推定ROAS改善幅
5. 実行上の注意点

金額はカンマ区切り、割合は小数点1桁まで表示してください。
数値のインパクトが伝わるように記載してください。
```

## 06. Claude Code × BigQuery MCPでGA4分析を完全自動化する方法【EC事業者向け実践ガイド】

出典: `articles/claude-code-bigquery-mcp-ga4.md`

```text
本日（{date.today()}）のECサイトの状況を以下の形式でレポートしてください。

1. 昨日のセッション数・CV数・CVR
2. チャネル別の昨日の流入数（上位5チャネル）
3. 昨日の売上金額（purchaseイベントのrevenueから集計）
4. 前週同日との比較
5. 気になる変化があれば指摘

BigQueryのデータセット: analytics_XXXXXXXXX
データはBigQueryから取得してください。
```

## 07. Claude Codeで売上が下がった原因をBigQueryから自動で仮説生成させる

出典: `articles/claude-code-bigquery-revenue-drop-hypothesis.md`

```text
あなたはEC事業のデータアナリストです。
以下のルールで売上低下の原因を分析してください。

1. まず全体の売上変化を数値で確認する
2. チャネル・デバイス・ページの3軸で分解する
3. 変化が大きい軸を特定し、仮説を生成する
4. 各仮説に「根拠となる数値」と「次のアクション」を必ず含める
5. 仮説は具体的に書く（「何かが悪い」ではなく「○○が△△した可能性」）
6. 季節要因やイベント影響も考慮する
```

## 08. Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計

出典: `articles/claude-code-ga4-anomaly-detection-prompt.md`

```text
以下はGA4の流入元別日次データです。
直近7日と前の7日を比較し、±20%以上の変動がある行を抽出して、
原因仮説を広告要因・サイト内要因・外部要因の3軸で各3つ提示してください。

{csv_text}
```

## 09. Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った

出典: `articles/claude-code-mcp-ga4-slack-daily-report.md`

```text
以下はGA4の日次レポート（{yesterday}分）です。
経営者向けに、3〜5行で要点を日本語でまとめてください。
特に前日比で大きな変化があれば強調してください。

データ:
{json.dumps(data, ensure_ascii=False, indent=2, default=str)}
```

## 10. Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術

出典: `articles/claude-code-monthly-kpi-insight-prompt-design.md`

```text
あなたはECサイトのアナリストです。以下のKPIデータをもとに、月次レポート用の考察を作成してください。

【サービス概要】
- 業種: アパレルEC（30〜50代女性向け）
- 今月の施策: メールマガジン配信強化、Instagram広告テスト実施

【KPIデータ（流入元別・前月比較）】
| medium | source | 先月sessions | 今月sessions | 先月CV | 今月CV | 先月CVR | 今月CVR |
|--------|--------|------------|------------|-------|-------|--------|--------|
| organic | google | 3200 | 2750 | 64 | 58 | 2.00% | 2.11% |
| cpc | google | 890 | 1050 | 22 | 31 | 2.47% | 2.95% |
| email | (none) | 410 | 680 | 18 | 34 | 4.39% | 5.00% |
| social | instagram | 120 | 310 | 3 | 9 | 2.50% | 2.90% |

【出力形式】
1. 全体サマリー（2〜3文）
2. チャネル別の変化と要因の考察（各チャネル2〜4文）
3. 来月に向けた施策提案（箇条書き3〜5項目）
```

## 11. Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う

出典: `articles/claude-code-python-review-sentiment-nps.md`

```text
以下の顧客レビューを感情分析してください。
結果をJSON形式のみで出力してください（説明文は不要）。

フォーマット:
{{"score": 数値(-1.0〜1.0), "label": "positive/neutral/negative", "reason": "理由を20文字以内で"}}

レビュー:
{review_text}
```

## 12. ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法

出典: `articles/ec-cs-inquiry-bigquery-product-improvement.md`

```text
以下のECサイトへの問い合わせ文を、次のカテゴリのいずれか1つに分類してください。
カテゴリ: 返品・交換, 配送遅延, 商品不良, サイズ・仕様確認, その他
問い合わせ: {inquiry_text}
カテゴリ名のみ返答してください。
```
