#!/usr/bin/env python3
"""下書きを段階公開キューに投入する（品質ゲート付き）。

背景と、なぜゲートが要るか:
    下書き 104 本は themes.csv による一元管理と一括コミットの履歴から、
    AI で一括生成されたことが構造上明らか。
    Zenn は 2025-06 の規約改定で「機械により自動生成された文章の投稿」を
    スパムとして明記しており、アカウント凍結を含む措置がありうる。

    公開済み 93 記事の検索流入は収益計画全体の入口なので、凍結は最大の事業リスク。
    したがって「検証を通過した記事だけを、日次 2 本のペースで出す」。
    無検証の一括投入は絶対にしない。

ゲートの条件:
    1. published: false であること（公開済みは触らない）
    2. 商材専用フラグが立っていないこと
       book_only: true — Zenn Books として有料販売（J系列25本）
       note_only: true — note 有料マガジンとして販売（I系列25本）
       どちらも無料公開すると商品が売れなくなる
    3. assets/sql/validation.json で「要修正(actionable)な失敗が無い」こと
    4. SQL を含まない散文のみの記事は、既定では対象外
       （検証で品質を示せないため、Zenn のスパム判定リスクが最も高い）
       --include-prose を明示したときだけ対象にする

投入後は .github/workflows/zenn-staggered-publish.yml が
日次 2 本ずつ published: true に変えていく。

使い方:
    python3 scripts/queue_drafts.py --dry-run          # 何が投入されるか確認
    python3 scripts/queue_drafts.py --max 20           # 20 本だけ投入
    python3 scripts/queue_drafts.py                    # 通過分すべて投入
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bulk_cta import split_frontmatter  # noqa: E402

_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_QUEUE_RE = re.compile(r"^publish_queue:\s*(true|false)\s*$", re.MULTILINE)
# 商材専用フラグ。有料で売る記事を無料公開しないための唯一のゲート。
# 商材が増えたらここに足す（フラグ名は <チャネル>_only で揃える）。
_PRODUCT_ONLY_FLAGS = ("book_only", "note_only")
_PRODUCT_ONLY_RE = re.compile(
    rf"^({'|'.join(_PRODUCT_ONLY_FLAGS)}):\s*true\s*$", re.MULTILINE
)


def set_queue_flag(header: str) -> str:
    """frontmatter の publish_queue を true にする。無ければ published の直後に足す。"""
    if _QUEUE_RE.search(header):
        return _QUEUE_RE.sub("publish_queue: true", header)
    return _PUBLISHED_RE.sub(
        lambda m: f"{m.group(0)}\npublish_queue: true", header, count=1
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--report", default="assets/sql/validation.json")
    parser.add_argument("--max", type=int, default=0, help="投入する最大本数（0=無制限）")
    parser.add_argument(
        "--include-prose",
        action="store_true",
        help="SQL を含まない散文のみの記事も対象にする（リスクを理解した上で）",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    report_path = Path(args.report)
    if not report_path.exists():
        print(
            f"検証レポートがありません: {report_path}\n"
            "先に scripts/extract_sql.py と scripts/validate_sql.py を実行してください。\n"
            "無検証での一括投入は Zenn の凍結リスクがあるため実行しません。",
            file=sys.stderr,
        )
        return 1

    report = json.loads(report_path.read_text(encoding="utf-8"))
    verdicts = report["articles"]

    eligible, blocked, prose, already = [], [], [], []
    product_only: dict[str, list[Path]] = {f: [] for f in _PRODUCT_ONLY_FLAGS}

    for path in sorted(articles_dir.glob("*.md")):
        header, _ = split_frontmatter(path.read_text(encoding="utf-8"))
        m = _PUBLISHED_RE.search(header)
        if not m or m.group(1) != "false":
            continue  # 公開済み or frontmatter 無しは触らない

        flag = _PRODUCT_ONLY_RE.search(header)
        if flag:
            # 有料商材として販売する記事。無料公開すると商品が売れなくなる。
            product_only[flag.group(1)].append(path)
            continue

        q = _QUEUE_RE.search(header)
        if q and q.group(1) == "true":
            already.append(path)
            continue

        verdict = verdicts.get(path.stem)
        if verdict is None:
            prose.append(path)
        elif verdict["ok"]:
            eligible.append(path)
        else:
            blocked.append((path, verdict["actionable"]))

    targets = list(eligible)
    if args.include_prose:
        targets += prose
    if args.max:
        targets = targets[: args.max]

    changed = 0
    for path in targets:
        text = path.read_text(encoding="utf-8")
        header, body = split_frontmatter(text)
        updated = set_queue_flag(header) + body
        if updated != text:
            changed += 1
            if not args.dry_run:
                path.write_text(updated, encoding="utf-8")

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"下書きの棚卸し {mode}")
    print(f"  ゲート通過（SQL検証OK）   : {len(eligible)}")
    print(f"  ゲート不通過（要修正あり）: {len(blocked)}")
    print(f"  SQLなし・散文のみ         : {len(prose)}"
          f"{'（--include-prose で対象）' if args.include_prose else '（既定では対象外）'}")
    print(f"  書籍専用(book_only)       : {len(product_only['book_only'])}"
          f"（Zenn Books で有料販売するため公開しない）")
    print(f"  note専用(note_only)       : {len(product_only['note_only'])}"
          f"（note 有料マガジンで販売するため公開しない）")
    print(f"  すでにキュー投入済み      : {len(already)}")
    print(f"\n  今回キューに入れた本数    : {changed}")

    if changed and not args.dry_run:
        print(
            f"  → .github/workflows/zenn-staggered-publish.yml が日次2本ずつ公開します"
            f"（約 {(changed + 1) // 2} 日で消化）"
        )

    if blocked:
        print("\nゲート不通過の記事（先に SQL を直す）:")
        for path, n in blocked:
            print(f"  - {path.name}（要修正 {n} 本）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
