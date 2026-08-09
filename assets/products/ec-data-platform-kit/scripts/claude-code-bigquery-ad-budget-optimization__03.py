"""Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った

出典記事: articles/claude-code-bigquery-ad-budget-optimization.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import anthropic
import os
import json
from dotenv import load_dotenv

load_dotenv()

def generate_proposal(analysis_data: dict) -> str:
    """予算配分の提案書を自動生成する"""
    client = anthropic.Anthropic(
        api_key=os.getenv("ANTHROPIC_API_KEY")
    )

    prompt = f"""
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
"""

    message = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=4096,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )
    return message.content[0].text
