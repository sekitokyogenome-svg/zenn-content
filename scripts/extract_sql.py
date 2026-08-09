#!/usr/bin/env python3
"""記事中の SQL ブロックを抽出してカタログ化する。

背景:
    504 個の SQL が 167 記事に散在しており、実務で使うには
    「探す・繋ぐ・動くか検証する」コストがかかる。
    このコストを肩代わりしたものが商品になる。

このスクリプトは各 SQL を 1 ファイルに切り出し、出自（記事・見出し）と
必要なプレースホルダを index.json に記録する。
切り出した SQL は scripts/validate_sql.py で BigQuery のドライラン検証にかける。

プレースホルダの正規化:
    記事中のテーブル参照は表記が揺れている（実測）。
        your-project.analytics_XXXXXXXXX.events_*   162
        your_project.analytics_XXXXXXXXX.events_*    73
        your_project.analytics_XXXXXXX.events_*      71
        project.dataset.events_*                     18  ...ほか
    これらを ${PROJECT} / ${DATASET} に統一し、検証時に実値へ差し替える。

使い方:
    python3 scripts/extract_sql.py
    python3 scripts/extract_sql.py --out assets/sql
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bulk_cta import split_frontmatter  # noqa: E402

PROJECT_TOKEN = "${PROJECT}"
DATASET_TOKEN = "${DATASET}"

_SQL_BLOCK_RE = re.compile(r"^```sql[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)
_HEADING_RE = re.compile(r"^#{2,4} +(.+?)[ \t]*$", re.MULTILINE)
_TITLE_RE = re.compile(r'^title:\s*"(.*)"\s*$', re.MULTILINE)
_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)

# プロジェクト側のプレースホルダ表記ゆれ。
# 区切り文字なしの myproject / yourproject もあるため [-_]? は省略可にする。
_PROJECT_ALIASES = (
    r"(?:your[-_]?project(?:[-_]?id)?|my[-_]?project|project[-_]?id|project)"
)
# GA4 のデータセット表記ゆれ（X の桁数が 6〜9 でばらつき、実 ID 風の数字もある）
_DATASET_ALIASES = r"(?:analytics_[X0-9]+|your[-_]?dataset|dataset|datamart)"

# `proj.dataset.table` 形式のテーブル参照。
# - 左の否定先読みで識別子の途中から match しないようにする
#   （これが無いと myproject の project だけが match して `my` が取り残される）
# - バッククォートは match 対象に含めない。元の位置のまま温存されるため、
#   `proj.ds.tbl` でも proj.ds.tbl でも正しく置換できる
# - rest は INFORMATION_SCHEMA.COLUMNS のような 4 分割参照も拾う
# - EXECUTE IMMEDIATE FORMAT() 内の %s も許容する
_TABLE_REF_RE = re.compile(
    r"(?<![A-Za-z0-9_.-])"
    rf"{_PROJECT_ALIASES}\.{_DATASET_ALIASES}\."
    r"(?P<rest>[A-Za-z0-9_*]+(?:\.[A-Za-z0-9_*]+)*|%s)",
    re.IGNORECASE,
)


def normalize_placeholders(sql: str) -> tuple[str, bool]:
    """テーブル参照のプレースホルダを統一する。(正規化後, 置換したか)"""
    replaced = False

    def _sub(m: re.Match[str]) -> str:
        nonlocal replaced
        replaced = True
        return f"{PROJECT_TOKEN}.{DATASET_TOKEN}.{m.group('rest')}"

    return _TABLE_REF_RE.sub(_sub, sql), replaced


def nearest_heading(text: str, pos: int) -> str:
    """指定位置より前にある直近の見出しを返す。"""
    last = ""
    for m in _HEADING_RE.finditer(text, 0, pos):
        last = m.group(1)
    return last


def load_categories(csv_path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    if not csv_path.exists():
        return mapping
    with csv_path.open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            filename = (row.get("filename") or "").strip()
            category = (row.get("category") or "").strip()
            if filename and category:
                mapping[filename.removesuffix(".md")] = category
    return mapping


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument("--out", default="assets/sql")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    out_dir = Path(args.out)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    categories = load_categories(Path(args.themes))
    out_dir.mkdir(parents=True, exist_ok=True)

    # 前回の生成物を掃除（冪等にするため）
    for stale in out_dir.glob("*.sql"):
        stale.unlink()

    entries = []
    articles_with_sql = 0

    for path in sorted(articles_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        header, body = split_frontmatter(text)

        m = _TITLE_RE.search(header)
        title = m.group(1) if m else path.stem
        m = _PUBLISHED_RE.search(header)
        published = bool(m and m.group(1) == "true")

        blocks = list(_SQL_BLOCK_RE.finditer(body))
        if blocks:
            articles_with_sql += 1

        for i, block in enumerate(blocks, start=1):
            sql = block.group(1).rstrip()
            normalized, replaced = normalize_placeholders(sql)
            heading = nearest_heading(body, block.start())

            name = f"{path.stem}__{i:02d}.sql"
            provenance = (
                f"-- 出典: {title}\n"
                f"-- 記事: articles/{path.name}"
                + (f"（{heading}）" if heading else "")
                + "\n"
                f"-- {PROJECT_TOKEN} / {DATASET_TOKEN} は実行前に実値へ置換すること\n\n"
            )
            (out_dir / name).write_text(provenance + normalized + "\n", encoding="utf-8")

            entries.append(
                {
                    "file": name,
                    "article": path.name,
                    "slug": path.stem,
                    "title": title,
                    "heading": heading,
                    "category": categories.get(path.stem),
                    "published": published,
                    "index": i,
                    "lines": normalized.count("\n") + 1,
                    "has_placeholder": replaced,
                }
            )

    index_path = out_dir / "index.json"
    index_path.write_text(
        json.dumps(
            {
                "project_token": PROJECT_TOKEN,
                "dataset_token": DATASET_TOKEN,
                "count": len(entries),
                "entries": entries,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    without = sum(1 for e in entries if not e["has_placeholder"])
    print(f"抽出した SQL : {len(entries)} 本（{articles_with_sql} 記事）")
    print(f"  プレースホルダを正規化 : {len(entries) - without}")
    print(f"  テーブル参照なし        : {without}（DDL・関数定義など）")
    print(f"  出力先                  : {out_dir}/ と {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
