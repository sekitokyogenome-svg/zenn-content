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

公開時の処理:
    published: false      -> published: true
    publish_queue: true   -> 行ごと削除（公開後の frontmatter を綺麗に保つ）

依存ライブラリなし（標準ライブラリのみ）。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_QUEUE_RE = re.compile(r"^publish_queue:\s*(true|false)\s*$", re.MULTILINE)


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


def find_queued(articles_dir: Path) -> list[Path]:
    """published:false かつ publish_queue:true の記事を、ファイル名昇順で返す。"""
    queued = []
    for path in sorted(articles_dir.glob("*.md")):
        parts = _split_frontmatter(path.read_text(encoding="utf-8"))
        if parts is None:
            continue
        header, _ = parts
        if _flag(header, _PUBLISHED_RE) is False and _flag(header, _QUEUE_RE) is True:
            queued.append(path)
    return queued


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
