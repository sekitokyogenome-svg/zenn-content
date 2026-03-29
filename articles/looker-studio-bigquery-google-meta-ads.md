---
title: "Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する"
emoji: "⚖️"
type: "tech"
topics: ["lookerstudio","bigquery","advertising"]
published: false
---

## はじめに

「Google広告とMeta広告（Facebook/Instagram広告）の成果を比較したいが、管理画面を行き来して数字を見比べるのが面倒」という課題を感じたことはないでしょうか。

複数の広告プラットフォームを運用しているEC事業者にとって、プラットフォーム横断での比較分析は予算配分の最適化に不可欠です。しかし、各プラットフォームの管理画面は指標の定義やUIが異なるため、単純に並べて比較するのが難しいです。

この記事では、BigQueryにGoogle広告とMeta広告のデータを集約し、Looker Studioで一画面で比較できるダッシュボードを構築する方法を解説します。

## 全体のアーキテクチャ

```
[Google Ads] → BigQuery Data Transfer → [BigQuery]
                                             ↓
[Meta Ads]  → Fivetran / STITCH / 自作API  → [BigQuery]  → 統合ビュー → Looker Studio
                                             ↑
[GA4]       → BigQuery Export            → [BigQuery]
```

Google広告のデータはBigQuery Data Transferで直接連携できます。Meta広告のデータは、サードパーティETLツールまたは自作スクリプトでBigQueryに取り込みます。

## ステップ1: Google広告データをBigQueryに連携する

### BigQuery Data Transferの設定

1. BigQueryコンソール →「データ転送」→「転送を作成」
2. ソース: 「Google Ads」を選択
3. 表示名: `google_ads_transfer` など
4. スケジュール: 毎日
5. Google広告のカスタマーID（10桁）を入力
6. 転送先データセットを指定

転送が完了すると、以下のようなテーブルが自動作成されます。

| テーブル名 | 内容 |
|---|---|
| `p_CampaignStats_XXXXXXX` | キャンペーン単位の日別統計 |
| `p_AdGroupStats_XXXXXXX` | 広告グループ単位の日別統計 |
| `p_Campaigns_XXXXXXX` | キャンペーンのマスタ情報 |
| `p_AdGroups_XXXXXXX` | 広告グループのマスタ情報 |

## ステップ2: Meta広告データをBigQueryに連携する

Meta広告のデータをBigQueryに取り込む方法は主に3つあります。

### 方法A: サードパーティETLツール（推奨）

| ツール | 月額目安 | 特徴 |
|---|---|---|
| Fivetran | $500〜 | エンタープライズ向け、信頼性高い |
| Stitch | $100〜 | コスト重視の中小向け |
| Airbyte | 無料（OSS） | セルフホスト型、技術力が必要 |
| Supermetrics | $99〜 | マーケター向け、設定が簡単 |

### 方法B: Meta Marketing APIで自作する

コストを抑えたい場合は、Meta Marketing APIを使って自作スクリプトでデータを取得し、BigQueryにロードする方法もあります。

```python
"""
meta_ads_to_bq.py
目的: Meta Marketing APIから広告データを取得しBigQueryにロード
作成日: 2026-03-30
依存: facebook-business, google-cloud-bigquery, python-dotenv
"""

import os
from datetime import datetime, timedelta
from dotenv import load_dotenv
from facebook_business.api import FacebookAdsApi
from facebook_business.adobjects.adaccount import AdAccount
from google.cloud import bigquery

load_dotenv()

# Meta API初期化
FacebookAdsApi.init(
    app_id=os.getenv('META_APP_ID'),
    app_secret=os.getenv('META_APP_SECRET'),
    access_token=os.getenv('META_ACCESS_TOKEN')
)

def fetch_meta_ads_data(account_id, start_date, end_date):
    """Meta広告のキャンペーン日別データを取得"""
    account = AdAccount(f'act_{account_id}')
    params = {
        'time_range': {
            'since': start_date,
            'until': end_date
        },
        'time_increment': 1,
        'level': 'campaign'
    }
    fields = [
        'campaign_name',
        'spend',
        'impressions',
        'clicks',
        'actions',
        'action_values'
    ]

    try:
        insights = account.get_insights(params=params, fields=fields)
        rows = []
        for row in insights:
            purchases = 0
            purchase_value = 0
            if 'actions' in row:
                for action in row['actions']:
                    if action['action_type'] == 'purchase':
                        purchases = int(action['value'])
            if 'action_values' in row:
                for av in row['action_values']:
                    if av['action_type'] == 'purchase':
                        purchase_value = float(av['value'])
            rows.append({
                'date': row['date_start'],
                'campaign_name': row['campaign_name'],
                'spend': float(row.get('spend', 0)),
                'impressions': int(row.get('impressions', 0)),
                'clicks': int(row.get('clicks', 0)),
                'purchases': purchases,
                'purchase_value': purchase_value
            })
        return rows
    except Exception as e:
        print(f'Meta API取得エラー: {e}')
        return []

def load_to_bigquery(rows, table_id):
    """BigQueryにデータをロード"""
    client = bigquery.Client()
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField('date', 'DATE'),
            bigquery.SchemaField('campaign_name', 'STRING'),
            bigquery.SchemaField('spend', 'FLOAT'),
            bigquery.SchemaField('impressions', 'INTEGER'),
            bigquery.SchemaField('clicks', 'INTEGER'),
            bigquery.SchemaField('purchases', 'INTEGER'),
            bigquery.SchemaField('purchase_value', 'FLOAT'),
        ]
    )
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()
    print(f'{len(rows)}行をBigQueryにロード完了')
```

:::message
Meta APIのアクセストークンは有効期限があります。長期トークンの取得方法についてはMeta開発者ドキュメントを参照してください。APIキーはコードにハードコードせず、`.env`ファイルで管理します。
:::

## ステップ3: 統合ビューをBigQueryで作成する

Google広告とMeta広告のデータを1つの統合ビューにまとめます。

```sql
CREATE OR REPLACE VIEW `project.dataset.unified_ads_daily` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS spend,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `project.dataset.p_CampaignStats_XXXXXXX` stats
JOIN
  `project.dataset.p_Campaigns_XXXXXXX` campaigns
  ON stats.campaign_id = campaigns.campaign_id
GROUP BY
  date, platform, campaign_name

UNION ALL

-- Meta Ads
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `project.dataset.meta_ads_daily`
GROUP BY
  date, platform, campaign_name
```

### KPI集計ビュー

```sql
CREATE OR REPLACE VIEW `project.dataset.ads_platform_comparison` AS
SELECT
  platform,
  SUM(spend) AS total_spend,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  SUM(conversions) AS total_conversions,
  SUM(conversion_value) AS total_conversion_value,
  SAFE_DIVIDE(SUM(clicks), SUM(impressions)) AS ctr,
  SAFE_DIVIDE(SUM(conversions), SUM(clicks)) AS cvr,
  SAFE_DIVIDE(SUM(spend), SUM(clicks)) AS cpc,
  SAFE_DIVIDE(SUM(spend), SUM(conversions)) AS cpa,
  SAFE_DIVIDE(SUM(conversion_value), SUM(spend)) AS roas
FROM
  `project.dataset.unified_ads_daily`
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  platform
```

## ステップ4: Looker Studioでダッシュボードを構築する

### ページ構成

| ページ | 内容 |
|---|---|
| 1. プラットフォーム比較 | Google vs Meta の主要KPI横並び |
| 2. 時系列トレンド | 日別の費用・ROAS推移を重ねて表示 |
| 3. キャンペーン詳細 | キャンペーン単位のパフォーマンステーブル |

### プラットフォーム比較ページの設計

```
┌──────────────────────────────────────────────────┐
│  日付フィルタ  |  プラットフォームフィルタ            │
├──────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │   Google Ads      │  │   Meta Ads       │     │
│  │   費用: ¥500K     │  │   費用: ¥300K    │     │
│  │   ROAS: 3.5       │  │   ROAS: 2.8      │     │
│  │   CPA: ¥3,200     │  │   CPA: ¥4,100    │     │
│  │   CTR: 2.1%       │  │   CTR: 1.5%      │     │
│  └──────────────────┘  └──────────────────┘     │
│                                                  │
├──────────────────────────────────────────────────┤
│  [費用 vs ROAS の散布図（プラットフォーム別色分け）]  │
│                                                  │
├──────────────────────────────────────────────────┤
│  [日別ROAS推移 - 折れ線グラフ（2本線）]              │
│                                                  │
└──────────────────────────────────────────────────┘
```

### Looker Studioでの実装ポイント

**スコアカードをプラットフォーム別に分ける:**

1. スコアカードを追加
2. データソースに `unified_ads_daily` ビューを指定
3. フィルタで `platform = 'Google Ads'` を設定
4. 同じ構成でMeta Ads用のスコアカードも追加

**時系列グラフでプラットフォームを色分けする:**

1. 折れ線グラフを追加
2. ディメンション: `date`
3. 内訳ディメンション: `platform`
4. 指標: `ROAS`（計算フィールド）

これにより、Google AdsとMeta Adsの線が色分けされて表示されます。

## 指標の定義を統一する際の注意点

### コンバージョンの定義の違い

| 項目 | Google Ads | Meta Ads |
|---|---|---|
| コンバージョンウィンドウ | 30日（デフォルト） | 7日クリック/1日ビュー（デフォルト） |
| ビュースルーCV | 含まない（デフォルト） | 含む（デフォルト） |
| 重複カウント | 可能性あり | 可能性あり |

この違いにより、同じ「コンバージョン数」でも数値の意味が異なります。ダッシュボード上で「Google Adsは30日クリックCV」「Meta Adsは7日クリック+1日ビューCV」と注記しておくことを推奨します。

### 費用の通貨

Google AdsもMeta Adsも、アカウントの通貨設定に基づいてデータが記録されます。両方とも日本円（JPY）で運用している場合は問題ありませんが、Meta Adsをドル建てで運用している場合は為替変換が必要です。

## 予算配分の最適化に活用する

横断ダッシュボードの最大の価値は、プラットフォーム間の予算配分を最適化できることです。

### 判断基準の例

```
ROASが高いプラットフォームに予算を寄せる:
  Google Ads ROAS: 3.5 → 予算増額を検討
  Meta Ads ROAS: 2.8 → 現状維持 or クリエイティブ改善

CPAが低いプラットフォームを優先する:
  Google Ads CPA: ¥3,200 → 効率的
  Meta Ads CPA: ¥4,100 → 改善の余地あり
```

ただし、ROASやCPAだけでなく、以下の観点も考慮してください。

- **スケーラビリティ**: ROASが高くても、検索ボリュームに上限があるGoogle Adsでは予算を増やしても成果が伸びない場合がある
- **認知効果**: Meta Adsはブランド認知に強みがあり、直接CVには結びつかなくてもアシストコンバージョンに貢献している可能性がある
- **ファーストパーティデータ**: GA4のアトリビューション分析も合わせて参照する

## まとめ

Google広告とMeta広告を一画面で比較するダッシュボードは、以下の手順で構築できます。

1. **データ連携**: Google AdsはData Transfer、Meta AdsはETLツールまたは自作スクリプトでBigQueryに集約
2. **統合ビュー**: UNION ALLで両プラットフォームのデータを1つのテーブルにまとめる
3. **Looker Studio**: プラットフォーム別のスコアカード、時系列比較、キャンペーン詳細テーブルを構成
4. **活用**: ROAS・CPA・CTRの比較から予算配分を最適化

広告費の最適化は、EC事業の利益率に直結します。感覚ではなくデータに基づいた意思決定ができる環境を構築してみてください。

:::message
「Looker Studioのダッシュボード構築を依頼したい」という方は、お気軽にご相談ください。
👉 [Looker Studioダッシュボード作成サービス](https://coconala.com/services/419062)
:::
