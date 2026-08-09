#!/usr/bin/env python3
"""商品④（note 有料マガジン）の告知文を生成する。

なぜ必要か:
    note は記事単位の SEO が弱く、告知しなければ人目に触れない。
    posts/ にある告知文 100 本は全て A〜G系列（Zenn 記事向け）で、
    note に出す I系列の分は 1 本も無い。原稿を作っても流入経路が無い状態だった。

URL の扱い（重要）:
    note の URL は投稿しないと確定しない。
    assets/products/ec-note-magazine/urls.json をレジストリとして置き、
    空欄のままなら告知文にプレースホルダを残して未入力件数を報告する。
    同じファイルを bulk_cta.py も読み、magazine が空なら Zenn 側に導線を出さない
    （未確定の URL を公開記事に埋めると 404 を配ることになるため）。

素材は記事から機械抽出する（実測に基づく）:
    - フック    : 「はじめに」冒頭の1文。25本中22本が「〜」の症状引用で始まる
    - 箇条書き  : `## ` 見出し（はじめに・まとめ・関連記事を除く）。1本あたり4〜5個
    - タグ      : frontmatter の topics ＋ EC 固定タグ

    冒頭が重複する数本だけ HOOK_OVERRIDES で差し替える。25本を手書きはしない。

冪等。何度実行しても結果は同じ。urls.json の既存の値は保持する。

使い方:
    python3 scripts/build_note_promo.py --dry-run
    python3 scripts/build_note_promo.py
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_note_magazine import (  # noqa: E402
    MAGAZINE_TITLE,
    PRICE_MAGAZINE,
    PRICE_SINGLE,
    load_series,
)
from bulk_cta import NOTE_URLS_PATH, split_frontmatter  # noqa: E402

OUT_DIR = Path("posts")
URL_PLACEHOLDER = "【note に投稿したら urls.json に URL を追記して再実行】"

# 箇条書きに使わない見出し
_SKIP_HEADINGS = {"はじめに", "まとめ", "関連記事", "おわりに", "参考"}

# topics（frontmatter）→ note のハッシュタグ。
# note の読者は EC 事業者なので、技術タグだけでなく EC 側のタグを必ず混ぜる。
_TAG_MAP = {
    "bigquery": "#BigQuery",
    "googleanalytics": "#GA4",
    "ga4": "#GA4",
    "ec": "#EC",
    "sql": "#SQL",
    "lookerstudio": "#LookerStudio",
    "shopify": "#Shopify",
    "googlecloud": "#GoogleCloud",
    "dataengineering": "#データ分析",
    "datanalysis": "#データ分析",
    "dataanalysis": "#データ分析",
    "gtm": "#GTM",
    "marketing": "#マーケティング",
}
# 読者層のタグを先頭に固定する。note で探しているのは EC 事業者であって、
# BigQuery で検索して来る人はほとんどいない。
_FIXED_TAGS = ["#EC", "#ネットショップ"]
_MAX_TAGS = 5

# 冒頭が他と重複する記事だけ、フックを書き下ろす。
# 「ECサイトを運営していると」で始まる3本が該当（実測）。
HOOK_OVERRIDES: dict[str, str] = {
    "I-06": (
        "「先月も返品対応に追われた」「特定の商品だけ返品が多い気がする」——"
        "感覚はあるのに、どのカテゴリで・どの流入経路から来た人が返品しやすいのかは、"
        "意外と数字で押さえられていないものです。"
    ),
    "I-14": (
        "「送料無料ラインをいくらに設定すべきか」。"
        "競合が3,000円にしているから自社も——という決め方をしていないでしょうか。"
        "低すぎれば物流コストが膨らみ、高すぎればカゴ落ちが増えます。"
    ),
    "I-25": (
        "「チラシを同梱してみたが、実際にどれだけ効果があったのか分からない」。"
        "同梱チラシやクーポンはリピート促進に効く一方で、"
        "効果測定だけが抜け落ちたまま続いている施策の代表格です。"
    ),
}

CLOSING = (
    f"個別記事は{PRICE_SINGLE:,}円、マガジン（全25本）は{PRICE_MAGAZINE:,}円です。"
    f"7本以上読むならマガジンの方が安く済みます。"
)

_TOPICS_RE = re.compile(r"^topics:\s*\[(.*)\]\s*$", re.MULTILINE)


def first_sentence(body: str) -> str:
    """本文の最初の段落から、フックに使う 1〜2 文を取り出す。"""
    paragraphs = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.startswith(("#", ">", "-", "|", "```", ":::"))
    ]
    if not paragraphs:
        return ""
    text = paragraphs[0]
    sentences = [s for s in re.split(r"(?<=。)", text) if s]
    if not sentences:
        return text
    hook = sentences[0]
    # 1 文が短すぎると症状が伝わらないので 2 文目まで足す
    if len(hook) < 40 and len(sentences) > 1:
        hook += sentences[1]
    return hook


def bullet_points(body: str) -> list[str]:
    """本題の `## ` 見出しを箇条書きにする。コードブロック内は無視する。"""
    points: list[str] = []
    in_fence = False
    for line in body.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not line.startswith("## "):
            continue
        heading = line[3:].strip()
        if heading in _SKIP_HEADINGS:
            continue
        points.append(heading)
    return points


def hashtags(header: str) -> list[str]:
    m = _TOPICS_RE.search(header)
    topics = []
    if m:
        topics = [t.strip().strip("\"'") for t in m.group(1).split(",") if t.strip()]

    tags: list[str] = list(_FIXED_TAGS)
    for topic in topics:
        tag = _TAG_MAP.get(topic.lower())
        if tag and tag not in tags:
            tags.append(tag)
    return tags[:_MAX_TAGS]


def load_urls(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"magazine": "", "articles": {}}
    data.setdefault("magazine", "")
    data.setdefault("articles", {})
    return data


def render(
    hook: str, points: list[str], url: str, tags: list[str], magazine: str
) -> str:
    lines = [hook, "", "記事では以下の内容を解説しています。", ""]
    lines += [f"・{p}" for p in points]
    closing = CLOSING if not magazine else f"{CLOSING}\n{MAGAZINE_TITLE} → {magazine}"
    lines += ["", closing, "", url, "", " ".join(tags)]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="articles")
    parser.add_argument("--themes", default="themes.csv")
    parser.add_argument("--out", default=str(OUT_DIR))
    parser.add_argument("--urls", default=str(NOTE_URLS_PATH))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    articles_dir = Path(args.dir)
    out_dir = Path(args.out)
    urls_path = Path(args.urls)

    rows = load_series(Path(args.themes), "I-")
    if not rows:
        print("themes.csv に I系列が見つかりません", file=sys.stderr)
        return 1

    urls = load_urls(urls_path)
    registry = urls["articles"]

    written = 0
    missing_url = 0
    hooks: dict[str, str] = {}
    short_bullets: list[str] = []

    for order, row in enumerate(rows, start=1):
        slug = row["filename"].removesuffix(".md")
        src = articles_dir / f"{slug}.md"
        if not src.exists():
            print(f"記事が見つかりません: {src}", file=sys.stderr)
            return 1

        header, body = split_frontmatter(src.read_text(encoding="utf-8"))
        hook = HOOK_OVERRIDES.get(row["id"]) or first_sentence(body)
        hooks[row["id"]] = hook

        points = bullet_points(body)
        if len(points) < 3:
            short_bullets.append(row["id"])

        registry.setdefault(row["id"], "")
        url = str(registry.get(row["id"]) or "").strip()
        if not url:
            url = URL_PLACEHOLDER
            missing_url += 1

        text = render(hook, points, url, hashtags(header), urls["magazine"])
        if not args.dry_run:
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / f"note_{row['id']}.md").write_text(text, encoding="utf-8")
        written += 1

    if not args.dry_run:
        urls["articles"] = registry
        urls_path.parent.mkdir(parents=True, exist_ok=True)
        urls_path.write_text(
            json.dumps(urls, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    # フックの重複は「同じ書き出しの告知が並ぶ」ことを意味するので必ず潰す
    seen: dict[str, list[str]] = {}
    for jid, hook in hooks.items():
        seen.setdefault(hook[:14], []).append(jid)
    dupes = {k: v for k, v in seen.items() if len(v) > 1}

    mode = "（dry-run：書き換えていません）" if args.dry_run else ""
    print(f"note 告知文 {mode}")
    print(f"  出力先          : {out_dir}/note_I-*.md")
    print(f"  生成            : {written} 本")
    print(f"  URL 未入力      : {missing_url} 本"
          f"{'（プレースホルダを入れています）' if missing_url else ''}")
    print(f"  レジストリ      : {urls_path}"
          f"{'（マガジンURL未入力）' if not urls['magazine'] else ''}")

    if dupes:
        print("\n書き出しが重複しています（HOOK_OVERRIDES で差し替える）:")
        for prefix, ids in dupes.items():
            print(f"  {ids} … 「{prefix}…」")
    if short_bullets:
        print(f"\n箇条書きが3項目未満: {short_bullets}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
