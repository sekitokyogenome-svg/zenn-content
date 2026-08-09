#!/usr/bin/env python3
"""商品②「GA4×BigQuery データ基盤 運用ガイド」を Zenn Books として生成する。

なぜ J系列を書籍にするか:
    同じ内容を無料公開しながら 3,900 円で売ることはできない。買う理由が成立しない。
    J系列25本は全て未公開なので、書籍専用にすれば独占性を確保できる。
    内容もスケジュールクエリ・IAM・コスト管理・dbt・Terraform といった「運用」で、
    Zenn のエンジニア読者層に最も合う。

このスクリプトは 2 つのことをする:
    1. 収録する記事に `book_only: true` を付ける
       → scripts/queue_drafts.py がこれを見て無料公開の対象から外す。
         これをやらないと書籍の中身がそのまま無料公開されてしまう。
    2. articles/ の記事を Zenn Books のチャプターへ変換して books/ に出力する

記事 → チャプターの変換:
    - frontmatter を書き換える（記事用の emoji/type/topics/published は消し、
      チャプター用の title と free だけにする）
    - 記事末尾の CTA ブロックを除去（bulk_cta.py の実装を再利用）
    - 「## 関連記事」を除去（build_internal_links.py の実装を再利用）
    - 本文中の J系列記事へのリンクを、書籍内のチャプターリンクに変換
      （変換しないと未公開記事へのリンク＝404 になる）

冪等。何度実行しても結果は同じ。

使い方:
    python3 scripts/build_book.py --dry-run
    python3 scripts/build_book.py
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_internal_links import ZENN_USER, strip_generated  # noqa: E402
from bulk_cta import split_frontmatter, strip_existing_cta  # noqa: E402

BOOK_SLUG = "bigquery-ga4-operations-guide"
BOOK_TITLE = "GA4×BigQuery データ基盤 運用ガイド"
BOOK_SUMMARY = (
    "GA4 の BigQuery エクスポートを「動かし続ける」ための運用ガイドです。"
    "スケジュールクエリの監視、クエリコストの制御、パーティション設計、"
    "IAM でのアクセス制御、dbt と Terraform でのコード管理まで、"
    "分析基盤を壊さず・安く・再現可能に保つ実務を 25 章にまとめました。"
)
BOOK_TOPICS = ["bigquery", "googleanalytics", "googlecloud", "dataengineering", "sql"]
BOOK_PRICE = 3900

PREFACE_SLUG = "preface"

# 部構成。Zenn Books のチャプターは平坦なので、
# タイトルに部を前置して 25 章を辿りやすくする。
PARTS: list[tuple[str, list[str]]] = [
    ("第1部 データの入れ方とモデリング", ["J-11", "J-06", "J-21"]),
    ("第2部 コストを制御する", ["J-02", "J-13", "J-19", "J-03", "J-24", "J-25"]),
    ("第3部 自動化とパイプライン", ["J-01", "J-05", "J-20", "J-17"]),
    ("第4部 高速化", ["J-04", "J-10", "J-16"]),
    ("第5部 品質と復旧", ["J-18", "J-07", "J-09", "J-22"]),
    ("第6部 チーム運用とガバナンス", ["J-12", "J-14", "J-15", "J-08", "J-23"]),
]

# 無料公開するチャプター。部分無料公開は個別ページが検索結果に出るため集客も兼ねる。
FREE_CHAPTERS = {PREFACE_SLUG, "J-02"}

# 記事として書かれた文面を書籍の文面に直す。
# 「この記事では」のまま出すと記事の寄せ集めに見え、有料書籍として成立しない。
# 長い表現から順に当てる（「この記事では」を「この記事で」より先に処理する）。
_ARTICLE_PHRASES: list[tuple[str, str]] = [
    ("この記事では", "本章では"),
    ("本記事では", "本章では"),
    ("この記事でも", "本章でも"),
    ("本記事でも", "本章でも"),
    ("この記事は", "本章は"),
    ("本記事は", "本章は"),
    ("この記事の", "本章の"),
    ("本記事の", "本章の"),
    ("この記事で", "本章で"),
    ("本記事で", "本章で"),
    ("この記事を", "本章を"),
    ("本記事を", "本章を"),
]

_TITLE_RE = re.compile(r'^title:\s*"(.*)"\s*$', re.MULTILINE)
_BOOK_ONLY_RE = re.compile(r"^book_only:\s*(true|false)\s*$", re.MULTILINE)
_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_CHAPTER_NAME_RE = re.compile(r"^[a-z0-9_-]{1,50}$")


def load_j_series(themes: Path) -> dict[str, str]:
    """J-ID -> slug（拡張子なし）"""
    mapping = {}
    with themes.open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            if row["id"].startswith("J-") and row.get("filename"):
                mapping[row["id"]] = row["filename"].removesuffix(".md")
    return mapping


def mark_book_only(path: Path) -> bool:
    """記事に book_only: true を付ける。付いていれば何もしない。"""
    text = path.read_text(encoding="utf-8")
    header, body = split_frontmatter(text)
    if _BOOK_ONLY_RE.search(header):
        updated_header = _BOOK_ONLY_RE.sub("book_only: true", header)
    else:
        updated_header = _PUBLISHED_RE.sub(
            lambda m: f"{m.group(0)}\nbook_only: true", header, count=1
        )
    if updated_header == header:
        return False
    path.write_text(updated_header + body, encoding="utf-8")
    return True


def chapter_body(article_text: str, slug_to_chapter: dict[str, str]) -> str:
    """記事本文をチャプター本文へ変換する。"""
    _, body = split_frontmatter(article_text)
    body = strip_existing_cta(body)
    body = strip_generated(body)

    # J系列記事へのリンクは書籍内チャプターへ向け直す。
    # 変換しないと未公開記事を指すリンク＝404 になる。
    def _relink(m: re.Match[str]) -> str:
        slug = m.group(1)
        chapter = slug_to_chapter.get(slug)
        if chapter is None:
            return m.group(0)  # J系列以外は記事URLのまま残す
        return f"https://zenn.dev/{ZENN_USER}/books/{BOOK_SLUG}/viewer/{chapter}"

    body = re.sub(
        rf"https://zenn\.dev/{re.escape(ZENN_USER)}/articles/([a-z0-9_-]+)", _relink, body
    )

    for before, after in _ARTICLE_PHRASES:
        body = body.replace(before, after)

    return body.strip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument("--books-dir", default="books")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    j_series = load_j_series(Path(args.themes))

    ordered = [(part, jid) for part, ids in PARTS for jid in ids]
    missing = [jid for _, jid in ordered if jid not in j_series]
    if missing:
        print(f"themes.csv に見つからない ID: {missing}", file=sys.stderr)
        return 1
    if len(ordered) != len(j_series):
        print(
            f"部構成の収録数({len(ordered)}) と J系列の総数({len(j_series)}) が一致しません。"
            "PARTS を見直してください。",
            file=sys.stderr,
        )
        return 1

    slug_to_chapter = {slug: slug for slug in j_series.values()}

    book_dir = Path(args.books_dir) / BOOK_SLUG
    preface_path = book_dir / f"{PREFACE_SLUG}.md"
    preface_text = preface_path.read_text(encoding="utf-8") if preface_path.exists() else None

    if not args.dry_run:
        if book_dir.exists():
            shutil.rmtree(book_dir)
        book_dir.mkdir(parents=True)

    chapters: list[str] = [PREFACE_SLUG]
    marked = 0
    invalid: list[str] = []

    for part, jid in ordered:
        slug = j_series[jid]
        src = articles_dir / f"{slug}.md"
        if not src.exists():
            print(f"記事が見つかりません: {src}", file=sys.stderr)
            return 1
        if not _CHAPTER_NAME_RE.match(slug):
            invalid.append(slug)

        text = src.read_text(encoding="utf-8")
        header, _ = split_frontmatter(text)
        m = _TITLE_RE.search(header)
        title = m.group(1) if m else slug

        free = jid in FREE_CHAPTERS
        fm = ['---', f'title: "【{part}】{title}"']
        if free:
            fm.append("free: true")
        fm.append("---")

        if not args.dry_run:
            (book_dir / f"{slug}.md").write_text(
                "\n".join(fm) + "\n\n" + chapter_body(text, slug_to_chapter),
                encoding="utf-8",
            )
            if mark_book_only(src):
                marked += 1
        chapters.append(slug)

    if invalid:
        print(f"チャプター名として不正な slug: {invalid}", file=sys.stderr)
        return 1

    # まえがきは書き下ろし。既にあれば内容を保持する。
    if not args.dry_run:
        if preface_text is None:
            preface_text = (
                "---\n"
                f'title: "はじめに ─ この本の使い方"\n'
                "free: true\n"
                "---\n\n"
                "（まえがきは scripts/build_book.py が上書きしません。"
                "このファイルを直接編集してください）\n"
            )
        preface_path.write_text(preface_text, encoding="utf-8")

        config = [
            f'title: "{BOOK_TITLE}"',
            f'summary: "{BOOK_SUMMARY}"',
            "topics: [" + ", ".join(f'"{t}"' for t in BOOK_TOPICS) + "]",
            "published: false",
            f"price: {BOOK_PRICE}",
            "chapters:",
        ] + [f"  - {c}" for c in chapters]
        (book_dir / "config.yaml").write_text("\n".join(config) + "\n", encoding="utf-8")

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"書籍: {BOOK_TITLE} {mode}")
    print(f"  出力先          : {book_dir}/")
    print(f"  チャプター数    : {len(chapters)}（まえがき + J系列 {len(ordered)}）")
    print(f"  無料チャプター  : {len([c for c in FREE_CHAPTERS])}")
    print(f"  価格            : {BOOK_PRICE:,} 円")
    if not args.dry_run:
        print(f"  book_only を付与: {marked} 記事（無料公開の対象から外れる）")
    print("\n  公開するには config.yaml の published を true にする")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
