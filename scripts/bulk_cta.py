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

CTA_BLOCK = f"""---

:::message
{OFFER_TEXT}
👉 [{OWNED_LABEL}]({OWNED_URL})
:::

ココナラからのご依頼はこちら → [{COCONALA_LABEL}]({COCONALA_URL})
"""

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


def apply(path: Path) -> tuple[bool, str, str]:
    """1 記事に CTA を適用する。(変更されたか, 状態ラベル, 適用後の全文) を返す。"""
    original = path.read_text(encoding="utf-8")
    header, body = split_frontmatter(original)

    had_cta = any(marker in body for marker in _CTA_MARKERS)
    cleaned = strip_existing_cta(body)
    updated = f"{header}{cleaned}\n\n{CTA_BLOCK}"

    if updated == original:
        return False, "unchanged", original
    return True, ("normalized" if had_cta else "added"), updated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles", help="記事ディレクトリ")
    parser.add_argument(
        "--dry-run", action="store_true", help="書き換えずに件数だけ表示する"
    )
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    stats = {"added": 0, "normalized": 0, "unchanged": 0}

    for path in sorted(articles_dir.glob("*.md")):
        changed, label, updated = apply(path)
        stats[label] += 1
        if changed and not args.dry_run:
            path.write_text(updated, encoding="utf-8")

    total = sum(stats.values())
    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"対象 {total} 記事 {mode}")
    print(f"  CTA を新規追加      : {stats['added']}")
    print(f"  既存 CTA を正準化   : {stats['normalized']}")
    print(f"  変更なし            : {stats['unchanged']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
