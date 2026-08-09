"""Claude CodeでGA4のイベント設計書を自動生成する方法

出典記事: articles/claude-code-ga4-event-design-doc.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

def generate_design_doc(catalog: list[dict]) -> str:
    """イベントカタログからMarkdown設計書を生成する"""
    md = "# GA4 イベント設計書\n\n"
    md += f"更新日: {pd.Timestamp.now().strftime('%Y-%m-%d')}\n\n"

    # カテゴリ別にグループ化
    categories = {}
    for event in catalog:
        cat = event['category']
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(event)

    for cat_name, events in categories.items():
        md += f"## {cat_name}（{len(events)}件）\n\n"
        md += "| イベント名 | 件数 | UU | 初回検出 | 最終検出 |\n"
        md += "|-----------|------|-----|---------|--------|\n"

        for e in events:
            md += (
                f"| `{e['event_name']}` "
                f"| {e['event_count']:,} "
                f"| {e['unique_users']:,} "
                f"| {e['first_seen']} "
                f"| {e['last_seen']} |\n"
            )

        md += "\n"

        # 各イベントのパラメータ詳細
        for e in events:
            if e['params']:
                md += f"### `{e['event_name']}` のパラメータ\n\n"
                md += "| パラメータ | 型 | 出現回数 |\n"
                md += "|-----------|-----|--------|\n"
                for p in e['params'][:10]:  # 上位10件
                    md += f"| `{p['key']}` | {p['type']} | {p['count']:,} |\n"
                md += "\n"

    return md
