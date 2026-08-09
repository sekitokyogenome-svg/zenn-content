"""Claude Code × Looker Studio APIでダッシュボードを自動更新する

出典記事: articles/claude-code-looker-studio-api-auto-update.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

from google.cloud import bigquery

def detect_schema_changes(
    project: str, dataset: str, table: str
) -> list:
    """テーブルのスキーマ変更を検知する"""
    client = bigquery.Client()

    # 現在のスキーマを取得
    table_ref = client.get_table(f"{project}.{dataset}.{table}")
    current_schema = [
        {"name": field.name, "type": field.field_type}
        for field in table_ref.schema
    ]

    # 前回のスキーマを読み込む（JSONファイルに保存しておく）
    import json
    schema_file = f"schemas/{dataset}_{table}.json"
    try:
        with open(schema_file, "r") as f:
            previous_schema = json.load(f)
    except FileNotFoundError:
        previous_schema = []

    # 差分を検出
    current_names = {col["name"] for col in current_schema}
    previous_names = {col["name"] for col in previous_schema}

    added = current_names - previous_names
    removed = previous_names - current_names

    # 現在のスキーマを保存
    with open(schema_file, "w") as f:
        json.dump(current_schema, f, indent=2)

    changes = []
    if added:
        changes.append(f"追加カラム: {', '.join(added)}")
    if removed:
        changes.append(f"削除カラム: {', '.join(removed)}")

    return changes
