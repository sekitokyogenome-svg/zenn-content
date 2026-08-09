#!/usr/bin/env python3
"""記事間の内部リンク（関連記事セクション）を自動生成する。

現状の課題:
    197 記事あるのに内部リンクが 9 本しかなく、トピッククラスタが形成されていない。
    検索エンジンから見ると各記事が孤立しており、サイト全体の評価が積み上がらない。

このスクリプトは各記事の末尾（CTA の直前）に「## 関連記事」を生成する。

リンク先の選び方:
    1. themes.csv の同カテゴリを最優先（+10 点）
    2. frontmatter の topics の重なり（1 つにつき +1 点）
    上位 N 件を採用する。

リンク先は「公開済み（published: true）の記事」に限る。
下書きへリンクすると Zenn 上で 404 になるため。
下書きが公開されるたびに再実行すればリンク網は自動的に育つ。

冪等。既存の生成セクションを作り直すので何度実行してもよい。
手書きの「### 関連記事」（h3）は h2 のみを対象にするため巻き込まない。

使い方:
    python3 scripts/build_internal_links.py --dry-run
    python3 scripts/build_internal_links.py
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from bulk_cta import (  # noqa: E402
    cta_block,
    load_categories,
    split_frontmatter,
    strip_existing_cta,
)

ZENN_USER = "web_benriya"
ARTICLE_URL = "https://zenn.dev/{user}/articles/{slug}"

# 1 記事あたりのリンク本数。多すぎるとスパム的に見えるため控えめに。
MAX_LINKS = 4

SECTION_HEADING = "## 関連記事"

# 生成済みセクション（h2 のみ）。次の h2 見出しか本文末尾まで。
_SECTION_RE = re.compile(
    rf"^{re.escape(SECTION_HEADING)}[ \t]*\n(?:(?!^## ).*\n?)*",
    re.MULTILINE,
)

_TITLE_RE = re.compile(r'^title:\s*"(.*)"\s*$', re.MULTILINE)
_TOPICS_RE = re.compile(r"^topics:\s*\[(.*)\]\s*$", re.MULTILINE)
_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)


class Article:
    def __init__(self, path: Path):
        self.path = path
        self.slug = path.stem
        text = path.read_text(encoding="utf-8")
        self.header, self.body = split_frontmatter(text)

        m = _TITLE_RE.search(self.header)
        self.title = m.group(1) if m else self.slug

        m = _PUBLISHED_RE.search(self.header)
        self.published = bool(m and m.group(1) == "true")

        m = _TOPICS_RE.search(self.header)
        self.topics: set[str] = set()
        if m:
            self.topics = {
                t.strip().strip('"').strip("'") for t in m.group(1).split(",") if t.strip()
            }

        self.category: str | None = None

    @property
    def url(self) -> str:
        return ARTICLE_URL.format(user=ZENN_USER, slug=self.slug)


def score(source: Article, target: Article) -> int:
    """source から見た target の関連度。"""
    points = 0
    if source.category and source.category == target.category:
        points += 10
    points += len(source.topics & target.topics)
    return points


def pick_related(source: Article, candidates: list[Article]) -> list[Article]:
    """関連度の高い公開済み記事を最大 MAX_LINKS 件選ぶ。"""
    scored = []
    for target in candidates:
        if target.slug == source.slug:
            continue
        points = score(source, target)
        if points <= 0:
            continue
        # 同点は slug 順で安定させる（再実行時に並びが揺れないように）
        scored.append((-points, target.slug, target))
    scored.sort()
    return [t for _, _, t in scored[:MAX_LINKS]]


def render_section(related: list[Article]) -> str:
    lines = [SECTION_HEADING, ""]
    lines += [f"- [{a.title}]({a.url})" for a in related]
    return "\n".join(lines)


def strip_generated(body: str) -> str:
    """CTA と生成済み関連記事セクションを取り除いた本文を返す。

    CTA の除去は bulk_cta.strip_existing_cta() に委譲する。
    以前は CTA_BLOCK 定数との完全一致で切っていたが、CTA がカテゴリ別になると
    一致しなくなり、EC 系記事の CTA を切り落とせずに二重付与になっていた。
    マーカー判定なら文言が変わっても効く。
    """
    body = strip_existing_cta(body)
    body = _SECTION_RE.sub("", body)
    return body.rstrip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    articles = [Article(p) for p in sorted(articles_dir.glob("*.md"))]
    categories = load_categories(Path(args.themes))
    for a in articles:
        a.category = categories.get(a.slug)

    published = [a for a in articles if a.published]

    changed = 0
    total_links = 0
    no_links = []

    for a in articles:
        related = pick_related(a, published)
        total_links += len(related)
        if not related:
            no_links.append(a.slug)

        core = strip_generated(a.body)
        parts = [core]
        if related:
            parts.append(render_section(related))
        # カテゴリ別の CTA を付け直す。汎用版を固定で付けると
        # bulk_cta.py が付けた note 導線をここで消してしまう。
        parts.append(cta_block(a.category))
        updated = a.header + "\n\n".join(parts)

        original = a.header + a.body
        if updated != original:
            changed += 1
            if not args.dry_run:
                a.path.write_text(updated, encoding="utf-8")

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"対象 {len(articles)} 記事 / 公開済み {len(published)} 記事がリンク先候補 {mode}")
    print(f"  生成した内部リンク : {total_links} 本")
    print(f"  更新した記事       : {changed}")
    print(f"  リンク先が無い記事 : {len(no_links)}")
    if no_links:
        print("    （同カテゴリ・共通topicsの公開済み記事がまだ無い記事）")
        for slug in no_links[:5]:
            print(f"      - {slug}")
        if len(no_links) > 5:
            print(f"      ... 他 {len(no_links) - 5} 件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
