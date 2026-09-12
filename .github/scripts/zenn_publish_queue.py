#!/usr/bin/env python3
"""Zenn 段階公開スケジューラ。

Zenn の GitHub 連携には「一定時間内に新規公開できる記事数」の上限（レート制限）が
あり、大量の記事を一度に published: true で push すると公開が保留される。

このスクリプトは、公開待ちキューに入れた記事を 1 回の実行につき最大 N 本だけ
public 化することで、レート制限に引っかからずに少しずつ公開する。

対象になる記事の条件（両方を満たすもののみ）:
    published: false
    publish_queue: true

書きかけの下書き（publish_queue を持たない記事）は決して触らない。

公開順:
    (publish_order, ファイル名) の昇順。
    publish_order は任意の整数。指定した記事が、指定のない記事より先に公開される。
    連載記事のように順序が意味を持つものに付ける。未指定なら従来どおりファイル名順。

公開時の処理:
    published: false      -> published: true
    publish_queue: true   -> 行ごと削除（公開後の frontmatter を綺麗に保つ）
    publish_order: N      -> 行ごと削除（同上）

依存ライブラリなし（標準ライブラリのみ）。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_QUEUE_RE = re.compile(r"^publish_queue:\s*(true|false)\s*$", re.MULTILINE)
_ORDER_RE = re.compile(r"^publish_order:\s*(\d+)\s*$", re.MULTILINE)

# publish_order を持たない記事に与える順序値。
# 明示的に順序指定された記事を、従来どおりファイル名順で並ぶ記事より先に公開する。
_NO_ORDER = 10**9


def _split_frontmatter(text: str) -> tuple[str, str] | None:
    """先頭の YAML frontmatter を (header, rest) に分割。無ければ None。

    header は開始 '---' から終了 '---' の行までを含む。
    """
    if not text.startswith("---"):
        return None
    # 2 個目の '---' 行の終わりを探す
    m = re.search(r"\n---[ \t]*\r?\n", text)
    if not m:
        return None
    return text[: m.end()], text[m.end():]


def _flag(header: str, regex: re.Pattern) -> bool | None:
    m = regex.search(header)
    if not m:
        return None
    return m.group(1) == "true"


def _order(header: str) -> int:
    """publish_order の値。未指定なら _NO_ORDER。"""
    m = _ORDER_RE.search(header)
    return int(m.group(1)) if m else _NO_ORDER


def find_queued(articles_dir: Path) -> list[Path]:
    """published:false かつ publish_queue:true の記事を公開順に返す。

    並び順は (publish_order, ファイル名) の昇順。
    publish_order を持つ記事が先に公開されるため、連載のように順序が意味を持つ
    記事群を、単発記事より先に・意図した順番で公開できる。
    publish_order を持たない記事同士は従来どおりファイル名昇順。
    """
    queued = []
    for path in sorted(articles_dir.glob("*.md")):
        parts = _split_frontmatter(path.read_text(encoding="utf-8"))
        if parts is None:
            continue
        header, _ = parts
        if _flag(header, _PUBLISHED_RE) is False and _flag(header, _QUEUE_RE) is True:
            queued.append((_order(header), path.name, path))
    queued.sort(key=lambda t: (t[0], t[1]))
    return [path for _, _, path in queued]


def publish(path: Path) -> None:
    """1 記事を公開状態にする（published:true、publish_queue 行を削除）。"""
    text = path.read_text(encoding="utf-8")
    parts = _split_frontmatter(text)
    assert parts is not None
    header, rest = parts
    header = _PUBLISHED_RE.sub("published: true", header, count=1)
    # publish_queue 行を（前の改行ごと）削除
    header = re.sub(r"^publish_queue:\s*(?:true|false)\s*\r?\n", "", header, count=1,
                    flags=re.MULTILINE)
    # publish_order も公開後は不要なので削除し、frontmatter を綺麗に保つ
    header = re.sub(r"^publish_order:\s*\d+\s*\r?\n", "", header, count=1,
                    flags=re.MULTILINE)
    path.write_text(header + rest, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Zenn 記事を段階的に公開する")
    ap.add_argument("--dir", default="articles", help="記事ディレクトリ（既定: articles）")
    ap.add_argument("--max", type=int, default=2, help="1 回で公開する最大本数（既定: 2）")
    ap.add_argument("--dry-run", action="store_true", help="変更せず対象だけ表示")
    args = ap.parse_args(argv)

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    queued = find_queued(articles_dir)
    if not queued:
        print("公開待ちの記事はありません（published:false かつ publish_queue:true が対象）")
        return 0

    targets = queued[: args.max]
    print(f"公開待ち {len(queued)} 本中、今回 {len(targets)} 本を公開します"
          f"（残り {len(queued) - len(targets)} 本）:")
    for path in targets:
        print(f"  - {path.name}")
        if not args.dry_run:
            publish(path)

    if args.dry_run:
        print("（--dry-run のため変更していません）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
