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
import unicodedata
import urllib.request
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


# ---------------------------------------------------------------------------
# 自サイト（logical-web.jp）との重複チェック
# ---------------------------------------------------------------------------
# Zenn は外部 canonical に対応していない（frontmatter は title/emoji/type/topics/
# published/published_at のみ）。そのため同じテーマの記事を Zenn と自サイトの両方に
# 出すと重複コンテナになり、ドメインの強い Zenn が勝って自サイト側が沈む。
#
# 2026-09-12 時点の下書き 75 本のうち 70 本が自サイトに同テーマ記事を持っていた。
# 人手で選別し続けるのは事故のもとなので、公開直前に機械的に弾く。
#
# 判定は自サイトの公開 RSS（常に最新）のタイトルと、記事タイトルの
# 文字bigram Jaccard 類似度。実データ 75 本で較正したところ、
# 重複ありは最小 0.40 / 重複なしは最大 0.19 と完全に分離したため既定値は 0.30。

HP_FEED_DEFAULT = "https://logical-web.jp/rss.xml"
DUP_THRESHOLD_DEFAULT = 0.30

_TITLE_RE = re.compile(r"^title:\s*(.+?)\s*$", re.MULTILINE)


def _normalize(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).lower()
    return re.sub(r"[^0-9a-z\u3040-\u30ff\u4e00-\u9fff]", "", text)


def _bigrams(text: str) -> set[str]:
    norm = _normalize(text)
    return {norm[i:i + 2] for i in range(len(norm) - 1)} or {norm}


def similarity(a: str, b: str) -> float:
    """文字bigram の Jaccard 係数。日本語タイトルでも語分割不要で効く。"""
    ba, bb = _bigrams(a), _bigrams(b)
    union = ba | bb
    return len(ba & bb) / len(union) if union else 0.0


def fetch_hp_titles(url: str) -> list[str]:
    """自サイトの RSS から記事タイトルを取得する。

    User-Agent を明示する。既定の "Python-urllib/x.y" は Cloudflare に
    403 で弾かれ、重複チェックが常に失敗して公開が止まるため。
    """
    req = urllib.request.Request(url, headers={
        "User-Agent": "logical-web-jp-publish-queue/1.0 (+https://logical-web.jp/)",
        "Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.8",
    })
    with urllib.request.urlopen(req, timeout=30) as res:
        xml = res.read().decode("utf-8", errors="replace")
    items = re.findall(r"<item>(.*?)</item>", xml, re.S)
    titles = []
    for item in items:
        m = re.search(r"<title>(?:<!\[CDATA\[(.*?)\]\]>|(.*?))</title>", item, re.S)
        if m:
            titles.append((m.group(1) or m.group(2) or "").strip())
    return [t for t in titles if t]


def article_title(path: Path) -> str:
    parts = _split_frontmatter(path.read_text(encoding="utf-8"))
    if parts is None:
        return path.stem
    m = _TITLE_RE.search(parts[0])
    return m.group(1).strip().strip('"\'') if m else path.stem


def find_duplicate(title: str, hp_titles: list[str], threshold: float) -> tuple[str, float] | None:
    """自サイトに同テーマ記事があれば (タイトル, 類似度) を返す。無ければ None。"""
    best_title, best_score = "", 0.0
    for hp in hp_titles:
        score = similarity(title, hp)
        if score > best_score:
            best_title, best_score = hp, score
    return (best_title, best_score) if best_score >= threshold else None


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
    ap.add_argument("--hp-feed", default=HP_FEED_DEFAULT,
                    help=f"自サイトのRSS（重複チェック用・既定: {HP_FEED_DEFAULT}）")
    ap.add_argument("--dup-threshold", type=float, default=DUP_THRESHOLD_DEFAULT,
                    help=f"重複とみなす類似度（既定: {DUP_THRESHOLD_DEFAULT}）")
    ap.add_argument("--no-dup-check", action="store_true",
                    help="重複チェックを行わない（非常時のみ。既定では必ず行う）")
    args = ap.parse_args(argv)

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    queued = find_queued(articles_dir)
    if not queued:
        print("公開待ちの記事はありません（published:false かつ publish_queue:true が対象）")
        return 0

    # 自サイトと同テーマの記事を Zenn に出すと重複コンテンツになるため、公開直前に弾く。
    # 取得に失敗したときは「検証できないまま公開する」ほうが危険なので中断する（fail-closed）。
    hp_titles: list[str] = []
    if not args.no_dup_check:
        try:
            hp_titles = fetch_hp_titles(args.hp_feed)
        except Exception as exc:  # noqa: BLE001 - 原因を問わず公開を止める
            print(f"自サイトのRSSを取得できませんでした: {exc}", file=sys.stderr)
            print("重複チェックができないため公開を中止します"
                  "（緊急時のみ --no-dup-check で回避可）。", file=sys.stderr)
            return 1
        if not hp_titles:
            print(f"RSS からタイトルを1件も取得できませんでした: {args.hp_feed}", file=sys.stderr)
            return 1
        print(f"重複チェック: 自サイト {len(hp_titles)} 本と照合"
              f"（閾値 {args.dup_threshold}）")

    published_count = 0
    skipped: list[tuple[str, str, float]] = []
    for path in queued:
        if published_count >= args.max:
            break
        if hp_titles:
            hit = find_duplicate(article_title(path), hp_titles, args.dup_threshold)
            if hit:
                skipped.append((path.name, hit[0], hit[1]))
                continue
        print(f"  - 公開: {path.name}")
        if not args.dry_run:
            publish(path)
        published_count += 1

    if skipped:
        print()
        print(f"重複のためスキップした記事 {len(skipped)} 本"
              "（自サイトに同テーマ記事あり。Zenn に出すと共倒れになる）:")
        for name, hp_title, score in skipped:
            print(f"  - {name}\n      類似 {score:.2f} : 自サイト「{hp_title}」")
        print("  → 技術寄りに書き直して切り口を変えるか、publish_queue を false にしてください。")

    print()
    print(f"公開待ち {len(queued)} 本中、{published_count} 本を公開しました"
          f"（スキップ {len(skipped)} 本）")
    if published_count == 0 and queued:
        print("::warning title=公開なし::公開待ちはありますが、すべて自サイトと重複していました。")
    if args.dry_run:
        print("（--dry-run のため変更していません）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
