#!/usr/bin/env python3
"""記事末尾の CTA ブロックを全記事で統一する。

現状の課題:
    - 198 記事中 66 記事に CTA が無い（収益導線の穴）
    - ココナラのリンク先が 4 つのサービス ID / 12 通りの文言に分散している

このスクリプトは CTA を「1 箇所で定義された 1 つのブロック」に統一する。
文言・価格・リンク先を変えたくなったら下の CTA 設定だけを書き換えて再実行すればよい。

冪等。何度実行しても結果は同じ（既存 CTA を除去してから正準ブロックを付け直す）。

使い方:
    python3 scripts/bulk_cta.py --dry-run   # 差分の件数だけ見る
    python3 scripts/bulk_cta.py             # 実際に書き換える
"""

from __future__ import annotations

import argparse
import csv
import functools
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# CTA 設定 —— 変更したいときはここだけ触る
# ---------------------------------------------------------------------------

# 集約先のココナラサービス（4 つに分散していたものを主力 1 本へ）
COCONALA_URL = "https://coconala.com/services/1791205"
COCONALA_LABEL = "GA4×BigQuery基盤構築サービス"

# 自社サイト。utm は記事フッター経由と分かるように固定
OWNED_URL = (
    "https://logical-web.jp/"
    "?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta"
)
OWNED_LABEL = "ウェブの便利屋（ろじかる）"

# 価格アンカー。商品投入後にここを引き上げる
OFFER_TEXT = (
    "GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています"
    "（中小EC・個人事業主向け／スポット相談1万円〜）。"
    "「自社の場合はどうすれば？」のご相談も歓迎です。"
)

# note 有料マガジンへの導線を出すカテゴリ。
# 読者の関心が最も近い「EC向けデータ分析」だけに絞る。
# 他カテゴリ（Looker Studio・フリーランス等）に出すと文脈が合わず広告色が強く出る。
NOTE_BRIDGE_CATEGORY = "EC向けデータ分析"
NOTE_MAGAZINE_TITLE = "EC データ分析 実務ガイド"
NOTE_URLS_PATH = Path("assets/products/ec-note-magazine/urls.json")

# note のアカウント。urls.json には ID だけ書けばよく、ここから URL を組み立てる。
NOTE_USER = "engawakun"

_NOTE_URL_RE = re.compile(
    r"^https?://note\.com/(?P<user>[^/]+)/(?P<kind>[nm])/(?P<ident>[0-9A-Za-z_-]+)"
)
_NOTE_ID_RE = re.compile(r"^[0-9A-Za-z_-]+$")


def normalize_note_url(value: str, kind: str) -> str:
    """urls.json の値を完全な note URL にする。

    受け付ける形は次の 2 つ。どちらで書いても同じ結果になる。
        - 完全な URL  https://note.com/engawakun/m/mxxxx
        - ID だけ      mxxxx

    別アカウントの URL を渡された場合は例外にする。
    公開済み記事 22 本に他人のリンクを撒くのは、リンク切れより害が大きい。

    kind: "m"（マガジン）/ "n"（記事）
    """
    v = (value or "").strip()
    if not v:
        return ""

    if v.startswith(("http://", "https://")):
        m = _NOTE_URL_RE.match(v)
        if not m:
            raise ValueError(f"note の URL として解釈できません: {v}")
        if m.group("user") != NOTE_USER:
            raise ValueError(
                f"別アカウントの URL です（{m.group('user')} ≠ {NOTE_USER}）: {v}"
            )
        if m.group("kind") != kind:
            expected = "マガジン(/m/)" if kind == "m" else "記事(/n/)"
            raise ValueError(f"{expected} の URL を入れてください: {v}")
        return f"https://note.com/{NOTE_USER}/{kind}/{m.group('ident')}"

    if _NOTE_ID_RE.match(v):
        return f"https://note.com/{NOTE_USER}/{kind}/{v}"

    raise ValueError(f"note の URL / ID として解釈できません: {v}")


@functools.lru_cache(maxsize=1)
def magazine_url() -> str:
    """note マガジンの URL。まだ投稿していなければ空文字。

    空のときは導線を出さない。未確定の URL を公開記事に埋めると 404 を配ることになる。
    値が壊れているときも空を返す（誤ったリンクを配るより、出さない方がまし）。
    """
    try:
        data = json.loads(NOTE_URLS_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    try:
        return normalize_note_url(str(data.get("magazine") or ""), "m")
    except ValueError as exc:
        print(f"[警告] {NOTE_URLS_PATH} の magazine を無視します: {exc}", file=sys.stderr)
        return ""


def cta_block(category: str | None = None) -> str:
    """記事末尾に付ける CTA。カテゴリによって note 導線の有無が変わる。

    定数ではなく関数なのは、カテゴリ別の CTA を「汎用版で上書きしてしまう」事故を
    構造的に防ぐため（以前は CTA_BLOCK 定数を build_internal_links.py が
    そのまま付け直しており、カテゴリ別にすると内部リンクの再生成で消えていた）。
    """
    lines = [OFFER_TEXT, f"👉 [{OWNED_LABEL}]({OWNED_URL})"]

    url = magazine_url() if category == NOTE_BRIDGE_CATEGORY else ""
    if url:
        # 「有料」と明記して誤クリックを防ぐ。Zenn 規約（広告目的の記事）への配慮でもある。
        lines.append(
            f"EC 実務での使い方は有料マガジン"
            f"「{NOTE_MAGAZINE_TITLE}」（note）にまとめています → {url}"
        )

    body = "\n".join(lines)
    return (
        "---\n\n"
        f":::message\n{body}\n:::\n\n"
        f"ココナラからのご依頼はこちら → [{COCONALA_LABEL}]({COCONALA_URL})\n"
    )


def load_categories(csv_path: Path = Path("themes.csv")) -> dict[str, str]:
    """filename(拡張子なし) -> category の対応を返す。"""
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

# ---------------------------------------------------------------------------
# 既存 CTA の除去パターン
# ---------------------------------------------------------------------------

# :::message ... ::: ブロック全体。中身を見て CTA かどうかを判定する。
# 記事本文中の解説用 :::message を巻き込まないよう、除去は _is_cta_block が真のものだけ。
_MESSAGE_BLOCK_RE = re.compile(
    r"^:::message[ \t]*\n(?:(?!^:::).*\n)*?^:::[ \t]*\n?",
    re.MULTILINE,
)

# CTA とみなす目印。既存 CTA には次の 2 系統がある:
#   1) 自社サイト（logical-web.jp）を含む :::message  … 132 記事
#   2) ココナラリンクのみの :::message              … 60 記事
_CTA_MARKERS = ("logical-web.jp", "coconala.com")

# 「ココナラからのご依頼はこちら → ...」の行（リンク形式・生 URL 形式の両方）
_COCONALA_LINE_RE = re.compile(r"^ココナラからのご依頼はこちら.*\n?", re.MULTILINE)

# 末尾に取り残される水平線
_TRAILING_HR_RE = re.compile(r"\n---[ \t]*\n\s*\Z")


def _is_cta_block(block: str) -> bool:
    """:::message ブロックが CTA（宣伝）かどうか。"""
    return any(marker in block for marker in _CTA_MARKERS)


def split_frontmatter(text: str) -> tuple[str, str]:
    """frontmatter と本文に分割する。frontmatter が無ければ ("", text)。"""
    if not text.startswith("---"):
        return "", text
    m = re.search(r"\n---[ \t]*\r?\n", text)
    if not m:
        return "", text
    return text[: m.end()], text[m.end():]


def strip_existing_cta(body: str) -> str:
    """既存の CTA ブロックを本文から取り除く。"""
    body = _MESSAGE_BLOCK_RE.sub(
        lambda m: "" if _is_cta_block(m.group(0)) else m.group(0), body
    )
    body = _COCONALA_LINE_RE.sub("", body)
    # CTA を剥がした結果、末尾に残った区切り線と余分な空行を掃除
    body = body.rstrip()
    body = _TRAILING_HR_RE.sub("", body + "\n")
    return body.rstrip()


def apply(path: Path, category: str | None = None) -> tuple[bool, str, str]:
    """1 記事に CTA を適用する。(変更されたか, 状態ラベル, 適用後の全文) を返す。"""
    original = path.read_text(encoding="utf-8")
    header, body = split_frontmatter(original)

    had_cta = any(marker in body for marker in _CTA_MARKERS)
    cleaned = strip_existing_cta(body)
    updated = f"{header}{cleaned}\n\n{cta_block(category)}"

    if updated == original:
        return False, "unchanged", original
    return True, ("normalized" if had_cta else "added"), updated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles", help="記事ディレクトリ")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument(
        "--dry-run", action="store_true", help="書き換えずに件数だけ表示する"
    )
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    stats = {"added": 0, "normalized": 0, "unchanged": 0}
    categories = load_categories(Path(args.themes))
    bridged = 0

    for path in sorted(articles_dir.glob("*.md")):
        category = categories.get(path.stem)
        changed, label, updated = apply(path, category)
        stats[label] += 1
        if category == NOTE_BRIDGE_CATEGORY and magazine_url():
            bridged += 1
        if changed and not args.dry_run:
            path.write_text(updated, encoding="utf-8")

    total = sum(stats.values())
    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"対象 {total} 記事 {mode}")
    print(f"  CTA を新規追加      : {stats['added']}")
    print(f"  既存 CTA を正準化   : {stats['normalized']}")
    print(f"  変更なし            : {stats['unchanged']}")

    if magazine_url():
        print(f"  note 導線を付与     : {bridged}（カテゴリ『{NOTE_BRIDGE_CATEGORY}』のみ）")
    else:
        n = sum(1 for c in categories.values() if c == NOTE_BRIDGE_CATEGORY)
        print(
            f"  note 導線            : 付けていません"
            f"（{NOTE_URLS_PATH} の magazine が空。埋めると {n} 記事に付きます）"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
