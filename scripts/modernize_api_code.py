#!/usr/bin/env python3
"""記事中の Anthropic API のモデル ID を現行世代へ更新する。

なぜ必要か:
    商材に同梱する Python は Anthropic API を呼ぶ。記事中のモデル ID は全て旧世代で、
    claude-sonnet-4-20250514 に至っては非推奨。
    19,800 円の実装キットを買った人がコピペしてエラーに当たる状態を先に潰す。

    記事（正本）を直せば、商品①・書籍・実装キットにも自動で反映される。

対象を「モデル ID だけ」に絞っている理由:
    当初は temperature / top_p の除去も想定していたが、実測したところ
      - temperature 4 件は全て BigQuery ML の STRUCT(0.0 AS temperature, ...) で Gemini 向け
      - top_p 7 件は全て `top_pages` という関数名への部分一致
    だった。Anthropic 呼び出しでの使用はゼロなので、触ると記事を壊すだけになる。
    同様に `"role": "assistant"` の 1 件も tool-use ループの履歴追加であって
    プレフィル（末尾 assistant ターン）ではないため対象外。

移行先はティアを保つ:
    Sonnet を選んでいる箇所は日次実行など高頻度・コスト重視の用途なので、
    一律 Opus にすると読者の請求額が上がる。Anthropic の移行ガイドの
    対応表どおり、Sonnet は Sonnet へ、Opus は Opus へ移す。

冪等。何度実行しても結果は同じ。

使い方:
    python3 scripts/modernize_api_code.py --dry-run
    python3 scripts/modernize_api_code.py
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# 旧 ID → 現行 ID。ティアを保った対応表。
MODEL_MIGRATION: dict[str, str] = {
    "claude-sonnet-4-20250514": "claude-sonnet-5",
    "claude-sonnet-4-5": "claude-sonnet-5",
    "claude-sonnet-4-6": "claude-sonnet-5",
    "claude-opus-4-5": "claude-opus-5",
    "claude-opus-4-6": "claude-opus-5",
    "claude-opus-4-7": "claude-opus-5",
}

# `model="..."` / `model: "..."` / `"model": "..."` の値だけを対象にする。
# 記事本文でモデル名に言及している箇所は書き換えない（比較記事などが壊れるため）。
_MODEL_ASSIGN_RE = re.compile(
    r"""(?P<prefix>["']?model["']?\s*[:=]\s*)(?P<quote>["'])(?P<id>[^"']+)(?P=quote)"""
)


def migrate_text(text: str) -> tuple[str, dict[str, int]]:
    """モデル ID を更新する。(更新後, 置換内訳) を返す。"""
    counts: dict[str, int] = {}

    def _sub(m: re.Match[str]) -> str:
        old = m.group("id")
        new = MODEL_MIGRATION.get(old)
        if new is None:
            return m.group(0)
        counts[old] = counts.get(old, 0) + 1
        return f"{m.group('prefix')}{m.group('quote')}{new}{m.group('quote')}"

    return _MODEL_ASSIGN_RE.sub(_sub, text), counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    if not articles_dir.is_dir():
        print(f"ディレクトリが見つかりません: {articles_dir}", file=sys.stderr)
        return 1

    changed_files = 0
    totals: dict[str, int] = {}

    for path in sorted(articles_dir.glob("*.md")):
        original = path.read_text(encoding="utf-8")
        updated, counts = migrate_text(original)
        if not counts:
            continue
        changed_files += 1
        for old, n in counts.items():
            totals[old] = totals.get(old, 0) + n
        if not args.dry_run:
            path.write_text(updated, encoding="utf-8")

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"モデル ID の更新 {mode}")
    print(f"  更新した記事 : {changed_files}")
    if totals:
        for old, n in sorted(totals.items()):
            print(f"    {old:28} → {MODEL_MIGRATION[old]:20} {n} 箇所")
    else:
        print("    更新対象なし（既に現行世代）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
