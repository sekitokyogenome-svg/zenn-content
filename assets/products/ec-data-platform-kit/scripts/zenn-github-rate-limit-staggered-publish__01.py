"""ZennのGitHub連携の投稿レート制限を、GitHub Actionsの段階公開で回避する

出典記事: articles/zenn-github-rate-limit-staggered-publish.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

import argparse
import re
import sys
from pathlib import Path

_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_QUEUE_RE = re.compile(r"^publish_queue:\s*(true|false)\s*$", re.MULTILINE)


def _split_frontmatter(text: str):
    """先頭の YAML frontmatter を (header, rest) に分割。無ければ None。"""
    if not text.startswith("---"):
        return None
    m = re.search(r"\n---[ \t]*\r?\n", text)  # 2個目の '---' 行
    if not m:
        return None
    return text[: m.end()], text[m.end():]


def _flag(header: str, regex: re.Pattern):
    m = regex.search(header)
    return None if not m else m.group(1) == "true"


def find_queued(articles_dir: Path) -> list[Path]:
    """published:false かつ publish_queue:true の記事をファイル名昇順で返す。"""
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
    """1記事を公開状態にする（published:true、publish_queue 行を削除）。"""
    header, rest = _split_frontmatter(path.read_text(encoding="utf-8"))
    header = _PUBLISHED_RE.sub("published: true", header, count=1)
    header = re.sub(r"^publish_queue:\s*(?:true|false)\s*\r?\n", "", header,
                    count=1, flags=re.MULTILINE)
    path.write_text(header + rest, encoding="utf-8")
