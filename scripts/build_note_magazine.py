#!/usr/bin/env python3
"""商品④「EC データ分析 実務ガイド」を note 有料マガジン用の原稿として生成する。

なぜ I系列を note に回すか:
    I系列25本は EC 事業者の具体的な困りごとのカタログ（在庫が余る／返品が多い／
    送料無料ラインをどこに引くか／解約予兆／セール効果／同梱チラシ効果）で、
    note の読者層（EC事業者・マーケター）に直結する。
    Zenn（エンジニア向け）とは読者が違うので、書籍とも商品①とも食い合わない。
    25本とも未公開なので独占性がある。

このスクリプトは 2 つのことをする:
    1. 収録記事に `note_only: true` を付ける
       → scripts/queue_drafts.py がこれを見て無料公開の対象から外す。
         これをやらないと有料商材の中身がそのまま無料公開される。
    2. 記事を note 用の原稿へ変換して assets/products/ec-note-magazine/ に出力する

なぜ変換が要るか:
    note のエディタは Zenn 記法を解釈しない。そのまま貼ると
    `:::message` は記号の羅列に、表はパイプ区切りの文字列になって崩れる。
    有料で売る以上、貼った時点で読める状態にしておく。

記事 → note 原稿の変換:
    - frontmatter を除去し、title を先頭の H1 に移す
    - CTA を note 用に差し替え（bulk_cta.py の strip_existing_cta を再利用）
    - 「## 関連記事」を除去（build_internal_links.py の strip_generated を再利用）
      Zenn 記事へのリンクは全てこのセクション内にあるため、
      これで未公開記事を指す 404 リンクも同時に消える
    - `:::message` を引用（>）に変換
    - 表を「見出し＋箇条書き」に変換（note に表組みが無いため）
    - 装飾用の水平線（---）を除去
    - 有料ラインの位置に <!-- ここから有料 --> を挿入

有料ラインの位置:
    最初の ```sql を含む `##` 見出しの直前。
    ただし無料で出すのは「はじめに」＋本題セクション1つまで（3本目以降には引かない）。
    素直に「最初の SQL の直前」で切ると無料部分が 9〜55% とばらつき、
    半分を無料で配る記事が出るため、上限を設けている。

冪等。何度実行しても結果は同じ。

使い方:
    python3 scripts/build_note_magazine.py --dry-run
    python3 scripts/build_note_magazine.py
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_internal_links import strip_generated  # noqa: E402
from bulk_cta import split_frontmatter, strip_existing_cta  # noqa: E402

MAGAZINE_TITLE = "EC データ分析 実務ガイド ― 25の課題と、その解き方"
PRICE_SINGLE = 980
PRICE_MAGAZINE = 6980
NOTE_FEE_RATE = 0.15  # 決済手数料 5% + プラットフォーム利用料 10%

OUT_DIR = Path("assets/products/ec-note-magazine")

PAYWALL_MARKER = "<!-- ここから有料 -->"

# 無料部分の上限。「はじめに」＋本題セクション1つまで（`## ` の 3 本目以降には引かない）。
MAX_FREE_SECTIONS = 2

# note 掲載時のタイトル差し替え。
# 記事のタイトルをそのまま使うのが原則で、実害があるものだけをここに書く。
NOTE_TITLE_OVERRIDES: dict[str, str] = {
    # 元題「2024年問題に備えるデータ基盤―…」。2026年の今「備える」は時制が合わず、
    # 「物流」が抜けていて何の2024年問題か分からない。本文の主張（影響は既に来ている）に揃える。
    "logistics-2026-bigquery-shipping-cost": (
        "物流2024年問題で上がった配送コストを、BigQueryで商品別に可視化する"
    ),
}

# note 用の CTA。note はマークダウンのリンク記法を確実には解釈しないので裸の URL を置く。
NOTE_CTA = f"""---

この記事は「{MAGAZINE_TITLE}」の1本です。
EC の困りごと別に全25本を収録しています。個別に読むよりマガジンの方が安く済みます。

GA4・BigQuery・Looker Studio の構築や設定代行も承っています。
「自社の場合はどうすれば？」のご相談も歓迎です。
ウェブの便利屋（ろじかる） https://logical-web.jp/?utm_source=note&utm_medium=article&utm_campaign=magazine_cta

掲載の SQL は BigQuery の構文検証を通しています。ただしスキーマはプロパティごとに違うため、
自社のデータで動かして数字が想定と合うかは必ずご確認ください。
本記事の制作には生成 AI を利用し、構成と説明を確認したうえで公開しています。
"""

_TITLE_RE = re.compile(r'^title:\s*"(.*)"\s*$', re.MULTILINE)
_NOTE_ONLY_RE = re.compile(r"^note_only:\s*(true|false)\s*$", re.MULTILINE)
_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)

_MESSAGE_OPEN_RE = re.compile(r"^:::message\b[ \t]*(\w+)?[ \t]*$")
_TABLE_SEP_RE = re.compile(r"^\|[\s:|-]+\|[ \t]*$")
_HR_RE = re.compile(r"^-{3,}[ \t]*$")


def load_series(themes: Path, prefix: str) -> list[dict[str, str]]:
    """themes.csv から系列の行を公開順（priority 昇順 → ID 順）で返す。"""
    with themes.open(encoding="utf-8") as fh:
        rows = [r for r in csv.DictReader(fh) if r["id"].startswith(prefix)]
    return sorted(rows, key=lambda r: (int(r["priority"] or 9), r["id"]))


def mark_note_only(path: Path) -> bool:
    """記事に note_only: true を付ける。付いていれば何もしない。"""
    text = path.read_text(encoding="utf-8")
    header, body = split_frontmatter(text)
    if _NOTE_ONLY_RE.search(header):
        updated = _NOTE_ONLY_RE.sub("note_only: true", header)
    else:
        updated = _PUBLISHED_RE.sub(
            lambda m: f"{m.group(0)}\nnote_only: true", header, count=1
        )
    if updated == header:
        return False
    path.write_text(updated + body, encoding="utf-8")
    return True


def convert_message_blocks(lines: list[str]) -> tuple[list[str], int]:
    """:::message ブロックを引用に変換する。コードブロック内は触らない。"""
    out: list[str] = []
    in_fence = False
    converted = 0
    i = 0

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_fence = not in_fence
            out.append(line)
            i += 1
            continue

        m = None if in_fence else _MESSAGE_OPEN_RE.match(line)
        if m is None:
            out.append(line)
            i += 1
            continue

        # 閉じの ::: まで集める。見つからなければ変換せずそのまま通す。
        j = i + 1
        while j < len(lines) and lines[j].rstrip() != ":::":
            j += 1
        if j >= len(lines):
            out.append(line)
            i += 1
            continue

        inner = [ln.rstrip() for ln in lines[i + 1 : j]]
        while inner and not inner[0]:
            inner.pop(0)
        while inner and not inner[-1]:
            inner.pop()
        if inner and m.group(1) == "alert":
            inner[0] = f"⚠️ {inner[0]}"

        out.extend(f"> {ln}" if ln else ">" for ln in inner)
        converted += 1
        i = j + 1

    return out, converted


def _cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def convert_tables(lines: list[str]) -> tuple[list[str], int]:
    """マークダウンの表を見出し＋箇条書きに変換する。

    note には表組みが無く、貼るとパイプ区切りの文字列がそのまま出る。
    2 列なら「**項目**：値」、3 列以上なら項目名を太字にして列ごとに箇条書きにする。
    """
    out: list[str] = []
    in_fence = False
    converted = 0
    i = 0

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_fence = not in_fence
            out.append(line)
            i += 1
            continue

        is_table = (
            not in_fence
            and line.lstrip().startswith("|")
            and i + 1 < len(lines)
            and _TABLE_SEP_RE.match(lines[i + 1].lstrip())
        )
        if not is_table:
            out.append(line)
            i += 1
            continue

        header = _cells(line)
        j = i + 2
        rows: list[list[str]] = []
        while j < len(lines) and lines[j].lstrip().startswith("|"):
            rows.append(_cells(lines[j]))
            j += 1

        for row in rows:
            label = row[0] if row else ""
            rest = [
                (header[k] if k < len(header) else "", row[k])
                for k in range(1, len(row))
                if row[k]
            ]
            if len(header) <= 2:
                value = rest[0][1] if rest else ""
                out.append(f"- **{label}**：{value}" if value else f"- **{label}**")
            else:
                out.append(f"**{label}**")
                out.extend(f"- {h}: {v}" if h else f"- {v}" for h, v in rest)
                out.append("")
        if out and out[-1] == "":
            out.pop()
        converted += 1
        i = j

    return out, converted


def drop_decorative_rules(lines: list[str]) -> list[str]:
    """装飾用の水平線を落とす。note では区切り線として解釈されないため。"""
    out: list[str] = []
    in_fence = False
    for line in lines:
        if line.startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if not in_fence and _HR_RE.match(line):
            continue
        out.append(line)
    return out


def paywall_position(lines: list[str]) -> int | None:
    """有料ラインを引く行番号を返す。決められなければ None。"""
    in_fence = False
    heads: list[int] = []
    first_sql: int | None = None

    for i, line in enumerate(lines):
        if line.startswith("```"):
            if not in_fence and first_sql is None and line[3:].strip().lower() == "sql":
                first_sql = i
            in_fence = not in_fence
            continue
        if not in_fence and line.startswith("## "):
            heads.append(i)

    if len(heads) < 2:
        return None
    if first_sql is None:
        return heads[1]

    # 最初の SQL を含む見出しの直前。ただし無料は MAX_FREE_SECTIONS 個まで。
    owner = max((k for k, h in enumerate(heads) if h < first_sql), default=1)
    return heads[min(max(owner, 1), MAX_FREE_SECTIONS)]


def to_note(article_text: str, title: str) -> tuple[str, dict[str, int | float | None]]:
    """記事 1 本を note 原稿に変換する。"""
    _, body = split_frontmatter(article_text)
    body = strip_existing_cta(body)
    body = strip_generated(body)

    lines = body.strip().splitlines()
    lines, n_msg = convert_message_blocks(lines)
    lines, n_tbl = convert_tables(lines)
    lines = drop_decorative_rules(lines)

    # 変換で空行が続くことがあるので詰める
    squeezed: list[str] = []
    for line in lines:
        if not line and squeezed and not squeezed[-1]:
            continue
        squeezed.append(line)
    lines = squeezed

    pos = paywall_position(lines)
    ratio = None
    if pos is not None:
        # 行数ではなく文字数で測る。1 段落 = 1 行で書かれているので、
        # 行数だと「短い見出しが多い箇所」が過大に、地の文が過小に出る。
        total = sum(len(ln) for ln in lines)
        ratio = round(100 * sum(len(ln) for ln in lines[:pos]) / total) if total else 0
        lines[pos:pos] = [PAYWALL_MARKER, ""]

    text = f"# {title}\n\n" + "\n".join(lines).strip() + "\n\n" + NOTE_CTA
    return text, {"messages": n_msg, "tables": n_tbl, "free_pct": ratio}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument("--out", default=str(OUT_DIR))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    out_dir = Path(args.out)
    rows = load_series(Path(args.themes), "I-")
    if not rows:
        print("themes.csv に I系列が見つかりません", file=sys.stderr)
        return 1

    # 書き下ろしは再実行で失わないよう退避する
    keep = {}
    for name in ("README.md", "magazine-description.md"):
        p = out_dir / name
        if p.exists():
            keep[name] = p.read_text(encoding="utf-8")

    if not args.dry_run:
        if out_dir.exists():
            shutil.rmtree(out_dir)
        (out_dir / "articles").mkdir(parents=True)

    stats = []
    marked = 0

    for order, row in enumerate(rows, start=1):
        slug = row["filename"].removesuffix(".md")
        src = articles_dir / f"{slug}.md"
        if not src.exists():
            print(f"記事が見つかりません: {src}", file=sys.stderr)
            return 1

        text = src.read_text(encoding="utf-8")
        header, _ = split_frontmatter(text)
        m = _TITLE_RE.search(header)
        title = NOTE_TITLE_OVERRIDES.get(slug) or (m.group(1) if m else slug)

        note_text, info = to_note(text, title)
        if not args.dry_run:
            (out_dir / "articles" / f"{order:02d}-{slug}.md").write_text(
                note_text, encoding="utf-8"
            )
            if mark_note_only(src):
                marked += 1

        stats.append({"order": order, "id": row["id"], "slug": slug, "title": title, **info})

    if not args.dry_run:
        index = [
            f"# {MAGAZINE_TITLE} ― 収録一覧",
            "",
            "`scripts/build_note_magazine.py` が生成する。手で編集しない。",
            "",
            f"個別 {PRICE_SINGLE:,} 円 / マガジン {PRICE_MAGAZINE:,} 円。"
            f"公開順は themes.csv の priority 昇順。",
            "",
            "| 順 | ファイル | 無料% | タイトル |",
            "|---|---|---|---|",
        ] + [
            f"| {s['order']} | `{s['order']:02d}-{s['slug']}.md` | "
            f"{'―' if s['free_pct'] is None else str(s['free_pct']) + '%'} | {s['title']} |"
            for s in stats
        ] + [
            "",
            "「無料%」は `<!-- ここから有料 -->` より前が全体の何割か（文字数ベース）。",
        ]
        (out_dir / "INDEX.md").write_text("\n".join(index) + "\n", encoding="utf-8")

        for name, content in keep.items():
            (out_dir / name).write_text(content, encoding="utf-8")

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    net = round(PRICE_MAGAZINE * (1 - NOTE_FEE_RATE))
    print(f"note マガジン: {MAGAZINE_TITLE} {mode}")
    print(f"  出力先        : {out_dir}/articles/")
    print(f"  記事数        : {len(stats)}")
    print(f"  価格          : 個別 {PRICE_SINGLE:,} 円 / マガジン {PRICE_MAGAZINE:,} 円"
          f"（手取り 約{net:,} 円）")
    if not args.dry_run:
        print(f"  note_only を付与: {marked} 記事（無料公開の対象から外れる）")

    print(f"\n{'順':>3} {'ID':6} {'無料%':>6} {'引用':>5} {'表':>4}  タイトル")
    for s in stats:
        pct = "―" if s["free_pct"] is None else f"{s['free_pct']}%"
        print(f"{s['order']:>3} {s['id']:6} {pct:>6} {s['messages']:>5} {s['tables']:>4}"
              f"  {s['title'][:44]}")

    missing = [s["id"] for s in stats if s["free_pct"] is None]
    if missing:
        print(f"\n有料ラインを決められなかった記事: {missing}（見出しが少なすぎる）")
    wide = [s["id"] for s in stats if (s["free_pct"] or 0) > 35]
    if wide:
        print(f"\n無料部分が 35% を超える記事: {wide}（無料で配りすぎ。要確認）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
