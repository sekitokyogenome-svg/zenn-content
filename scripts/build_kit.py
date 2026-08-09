#!/usr/bin/env python3
"""商品③「EC データ基盤 実装キット」を組み立てる。

19,800 円を正当化するのは SQL 単体ではなく「動くもの一式」。
記事に散らばった実行可能資産を、そのまま動かせる構成に束ねる。

同梱するもの:
    sql/            検証済み SQL（validate_sql.py の product_ready）
    scripts/        Python 自動化スクリプト（40 行超の実用的なもの）+ requirements.txt
    dbt/            dbt プロジェクト雛形
    looker-studio/  ダッシュボードが参照する BigQuery ビュー層 + フィールド定義書
    prompts/        Claude Code プロンプト集

Looker Studio のレポート本体は同梱できない。
クラウド上の成果物で、GUI で作成してテンプレート共有リンクを発行する必要があり、
ファイルとして書き出す手段がないため。
代わりにレポートが乗るデータ層（ビュー定義・フィールド定義書・接続手順）を用意し、
レポート作成だけを購入者の作業として残す。

冪等。何度実行しても結果は同じ。

使い方:
    python3 scripts/build_kit.py
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_sql_pack import cost_note, required_tables, strip_provenance  # noqa: E402
from bulk_cta import split_frontmatter  # noqa: E402

# Python スクリプトとして同梱する下限。これ未満は断片で、有料商材には薄い。
MIN_PYTHON_LINES = 40

_FENCE_RE = re.compile(r"^```(?P<lang>[a-zA-Z]*)[ \t]*\n(?P<body>.*?)^```[ \t]*$", re.M | re.S)
_TITLE_RE = re.compile(r'^title:\s*"(.*)"\s*$', re.M)
_IMPORT_RE = re.compile(r"^(?:from|import)\s+([A-Za-z_][\w.]*)", re.M)
_PATH_COMMENT_RE = re.compile(r"^\s*(?:--|#)\s*([\w./-]+\.(?:sql|yml|yaml))\s*$", re.M)
_CREATE_VIEW_RE = re.compile(r"CREATE\s+OR\s+REPLACE\s+(VIEW|TABLE)\s+`([^`]+)`", re.I)
_ALIAS_RE = re.compile(r"\bAS\s+([a-z_][a-z0-9_]*)\s*(?:,|$)", re.I | re.M)
# `CREATE ... AS SELECT` や `AS STRUCT` の AS も引っかかるので、SQL キーワードは列として扱わない
_NOT_A_COLUMN = {
    "select", "with", "struct", "array", "string", "int64", "float64", "bool",
    "date", "datetime", "timestamp", "numeric", "bytes", "json", "not",
}
_PROMPT_ASSIGN_RE = re.compile(r'prompt\s*=\s*f?"""(.*?)"""', re.S)

# import 名 → PyPI パッケージ名。requirements.txt の生成に使う。
PACKAGE_MAP = {
    "google": "google-cloud-bigquery",
    "googleapiclient": "google-api-python-client",
    "dotenv": "python-dotenv",
    "slack_sdk": "slack-sdk",
    "facebook_business": "facebook-business",
    "functions_framework": "functions-framework",
    "PIL": "pillow",
    "yaml": "pyyaml",
    "dateutil": "python-dateutil",
    "bs4": "beautifulsoup4",
    "sklearn": "scikit-learn",
    "claude_agent_sdk": "claude-agent-sdk",
    "cv2": "opencv-python",
}
# 標準ライブラリは requirements に入れない
STDLIB = {
    "os", "sys", "json", "re", "csv", "datetime", "time", "pathlib", "typing",
    "subprocess", "logging", "argparse", "collections", "itertools", "math",
    "random", "base64", "hashlib", "hmac", "textwrap", "dataclasses", "functools",
    "urllib", "io", "shutil", "tempfile", "uuid", "decimal", "statistics",
    "warnings", "traceback", "enum", "abc", "contextlib", "glob", "unittest",
    "asyncio", "secrets", "string", "operator", "copy", "pprint", "zipfile",
}


def iter_articles(articles_dir: Path):
    """(slug, title, 本文) を順に返す。"""
    for path in sorted(articles_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        header, body = split_frontmatter(text)
        m = _TITLE_RE.search(header)
        yield path.stem, (m.group(1) if m else path.stem), body


def blocks_of(body: str, lang: str):
    """指定言語のコードブロックを順に返す。"""
    for m in _FENCE_RE.finditer(body):
        if m.group("lang").lower() == lang:
            yield m.group("body")


# ---------------------------------------------------------------------------
# sql/
# ---------------------------------------------------------------------------


def build_sql(sql_dir: Path, out: Path) -> int:
    report = json.loads((sql_dir / "validation.json").read_text(encoding="utf-8"))
    index = {
        e["file"]: e
        for e in json.loads((sql_dir / "index.json").read_text(encoding="utf-8"))["entries"]
    }
    ready = [r for r in report["results"] if r["product_ready"]]

    (out / "sql").mkdir(parents=True, exist_ok=True)
    lines = ["# 収録SQL一覧", "", f"検証を通過し単体で完結する {len(ready)} 本。", ""]
    by_cat: dict[str, list] = {}
    for r in ready:
        by_cat.setdefault(r["category"] or "(未分類)", []).append(r)

    for cat, items in sorted(by_cat.items(), key=lambda x: -len(x[1])):
        lines.append(f"## {cat}（{len(items)}本）")
        lines.append("")
        for r in items:
            meta = index[r["file"]]
            sql = strip_provenance((sql_dir / r["file"]).read_text(encoding="utf-8"))
            name = r["file"]
            (out / "sql" / name).write_text(
                f"-- {meta['title']}\n"
                f"-- 用途: {meta['heading'] or meta['title']}\n"
                f"-- 必要テーブル: {', '.join(required_tables(sql)) or '(なし)'}\n"
                f"-- コスト: {cost_note(sql)}\n"
                f"-- ${{PROJECT}} / ${{DATASET}} を自社の値に置換して実行\n\n" + sql + "\n",
                encoding="utf-8",
            )
            lines.append(f"- `{name}` — {meta['heading'] or meta['title']}")
        lines.append("")

    (out / "sql" / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")
    return len(ready)


# ---------------------------------------------------------------------------
# scripts/
# ---------------------------------------------------------------------------


def build_scripts(articles_dir: Path, out: Path) -> tuple[int, list[str]]:
    dest = out / "scripts"
    dest.mkdir(parents=True, exist_ok=True)
    imports: set[str] = set()
    count = 0
    listing = ["# 収録スクリプト一覧", ""]

    for slug, title, body in iter_articles(articles_dir):
        for i, code in enumerate(blocks_of(body, "python"), start=1):
            if code.count("\n") < MIN_PYTHON_LINES:
                continue
            count += 1
            name = f"{slug}__{i:02d}.py"
            (dest / name).write_text(
                f'"""{title}\n\n出典記事: articles/{slug}.md\n'
                f'実行前に認証情報と ${{PROJECT}} / ${{DATASET}} を設定すること。\n"""\n\n'
                + code.rstrip()
                + "\n",
                encoding="utf-8",
            )
            listing.append(f"- `{name}` — {title}")
            for mod in _IMPORT_RE.findall(code):
                root = mod.split(".")[0]
                if root not in STDLIB:
                    imports.add(PACKAGE_MAP.get(root, root))

    packages = sorted(imports)
    (dest / "requirements.txt").write_text("\n".join(packages) + "\n", encoding="utf-8")
    (dest / "README.md").write_text("\n".join(listing) + "\n", encoding="utf-8")
    return count, packages


# ---------------------------------------------------------------------------
# dbt/
# ---------------------------------------------------------------------------

DBT_SOURCES = ("bigquery-ga4-dbt-management-intro", "dbt-bigquery-ga4-reproducible-pipeline")


def build_dbt(articles_dir: Path, out: Path) -> int:
    dest = out / "dbt"
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    profile_name = "ga4_analytics"
    seen_profile = False

    for slug in DBT_SOURCES:
        path = articles_dir / f"{slug}.md"
        if not path.exists():
            continue
        _, body = split_frontmatter(path.read_text(encoding="utf-8"))
        for m in _FENCE_RE.finditer(body):
            lang, code = m.group("lang").lower(), m.group("body").strip()
            if lang not in ("sql", "yaml", "yml") or not code:
                continue

            # 1行目のパスコメント（-- models/staging/stg_events.sql）を配置先に使う
            pm = _PATH_COMMENT_RE.match(code)
            if pm:
                rel = pm.group(1)
            elif lang in ("yaml", "yml") and re.match(r"^[\w-]+:\s*$", code.splitlines()[0]):
                # `ga4_analytics:` 形式はプロファイル。記事が複数あるので最初の1つだけ採る。
                if seen_profile:
                    continue
                seen_profile = True
                profile_name = code.splitlines()[0].rstrip(":").strip()
                rel = "profiles.yml.example"
            elif lang in ("yaml", "yml") and code.startswith("version:"):
                # version: 2 の yaml は sources 定義と models のテスト定義の2種類がある。
                # 同じファイルに書くと片方が消えるので中身で振り分ける。
                rel = (
                    "models/staging/_sources.yml"
                    if re.search(r"^\s*sources:", code, re.M)
                    else "models/staging/schema.yml"
                )
            else:
                continue  # 配置先を決められないものは入れない

            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(code + "\n", encoding="utf-8")
            written += 1

    # dbt_project.yml はどの記事にも無いが、これが無いと dbt が起動しない。
    # プロファイル名を profiles.yml.example と揃えて生成する。
    (dest / "dbt_project.yml").write_text(
        f"""name: '{profile_name}'
version: '1.0.0'
config-version: 2

# profiles.yml の最上位キーと一致させる
profile: '{profile_name}'

model-paths: ["models"]
test-paths: ["tests"]
target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  {profile_name}:
    staging:
      +materialized: view
    mart:
      +materialized: table
""",
        encoding="utf-8",
    )
    written += 1

    return written


# ---------------------------------------------------------------------------
# looker-studio/
# ---------------------------------------------------------------------------


def build_looker_studio(sql_dir: Path, out: Path) -> tuple[int, int]:
    dest = out / "looker-studio" / "views"
    dest.mkdir(parents=True, exist_ok=True)
    index = json.loads((sql_dir / "index.json").read_text(encoding="utf-8"))["entries"]

    fields_doc = ["# フィールド定義書", "",
                  "ダッシュボードが参照するビューと、その列の一覧。",
                  "Looker Studio 側のフィールド名はここに合わせる。", ""]
    views = 0
    fields = 0

    for entry in index:
        sql = strip_provenance((sql_dir / entry["file"]).read_text(encoding="utf-8"))
        m = _CREATE_VIEW_RE.search(sql)
        if not m:
            continue
        views += 1
        name = entry["file"]
        (dest / name).write_text(
            f"-- {entry['title']}\n-- 出典: articles/{entry['article']}\n\n" + sql + "\n",
            encoding="utf-8",
        )
        cols = sorted(
            {c for c in _ALIAS_RE.findall(sql) if c.lower() not in _NOT_A_COLUMN}
        )
        fields += len(cols)
        fields_doc.append(f"## `{m.group(2)}`（{name}）")
        fields_doc.append("")
        fields_doc.append(f"出典: {entry['title']}")
        fields_doc.append("")
        if cols:
            fields_doc += [f"- `{c}`" for c in cols]
        else:
            fields_doc.append("- （列エイリアスなし。ビュー定義を直接参照）")
        fields_doc.append("")

    (out / "looker-studio" / "field-definitions.md").write_text(
        "\n".join(fields_doc), encoding="utf-8"
    )
    return views, fields


# ---------------------------------------------------------------------------
# prompts/
# ---------------------------------------------------------------------------


def build_prompts(articles_dir: Path, out: Path) -> int:
    dest = out / "prompts"
    dest.mkdir(parents=True, exist_ok=True)
    doc = ["# Claude Code プロンプト集", "",
           "記事中で実際に使っているプロンプト。",
           "`{}` で囲まれた箇所は自社のデータに置き換えて使う。", ""]
    count = 0

    for slug, title, body in iter_articles(articles_dir):
        found: list[str] = []
        # Python コード内の prompt = f"""...""" 形式
        for code in blocks_of(body, "python"):
            found += [p.strip() for p in _PROMPT_ASSIGN_RE.findall(code)]
        # 「あなたは〜」で始まる text/無印ブロック
        for m in _FENCE_RE.finditer(body):
            block = m.group("body").strip()
            if m.group("lang").lower() in ("", "text") and block.startswith("あなたは"):
                found.append(block)

        for p in found:
            if len(p) < 80:
                continue
            count += 1
            doc.append(f"## {count:02d}. {title}")
            doc.append("")
            doc.append(f"出典: `articles/{slug}.md`")
            doc.append("")
            doc.append("```text")
            doc.append(p)
            doc.append("```")
            doc.append("")

    (dest / "README.md").write_text("\n".join(doc), encoding="utf-8")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--sql-dir", default="assets/sql")
    parser.add_argument("--out", default="assets/products/ec-data-platform-kit")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    sql_dir = Path(args.sql_dir)
    out = Path(args.out)

    if not (sql_dir / "validation.json").exists():
        print(
            "assets/sql/validation.json がありません。"
            "先に extract_sql.py と validate_sql.py を実行してください。",
            file=sys.stderr,
        )
        return 1

    # 書き下ろしのドキュメントは上書きしない（生成物だけ作り直す）
    keep = {}
    for rel in ("README.md", "looker-studio/setup-guide.md", "dbt/README.md"):
        p = out / rel
        if p.exists():
            keep[rel] = p.read_text(encoding="utf-8")
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    n_sql = build_sql(sql_dir, out)
    n_py, packages = build_scripts(articles_dir, out)
    n_dbt = build_dbt(articles_dir, out)
    n_views, n_fields = build_looker_studio(sql_dir, out)
    n_prompts = build_prompts(articles_dir, out)

    for rel, text in keep.items():
        p = out / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    print(f"実装キット: {out}/")
    print(f"  SQL              : {n_sql} 本")
    print(f"  Python スクリプト: {n_py} 本（依存 {len(packages)} パッケージ）")
    print(f"  dbt ファイル     : {n_dbt} 個")
    print(f"  ビュー定義       : {n_views} 個 / フィールド {n_fields} 列")
    print(f"  プロンプト       : {n_prompts} 本")
    if keep:
        print(f"  書き下ろしを保持 : {', '.join(keep)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
