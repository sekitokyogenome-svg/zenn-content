#!/usr/bin/env python3
"""
zenn_dup_guard.py — 公開済み記事が自サイトと重複していないかを push のたびに点検する

【なぜ必要か】

公開経路が2つあり、ゲートが守っているのは片方だけだった。

  chore: staggered publish of queued Zenn articles
      → zenn-staggered-publish.yml が zenn_publish_queue.py を通す（ゲートあり）

  publish: <記事タイトル>
      → 別セッション（themes.csv ベースの Routine）が published: を直接書き換える
        （**ゲートを通らない**）

2026-09-12 以降の公開コミット12件のうち7件が後者で、そのうち1件が
自サイトと**完全一致（類似1.00）**のまま公開された。

  Zenn     ad-creative-ltv-bigquery-winning-pattern（2026-09-17 公開・のち取り下げ）
  自サイト 同一タイトルを 2026-07-15 に公開済み

Zenn は外部 canonical に非対応のため、同テーマを両方に出すとドメインの強い Zenn が勝ち、
自サイトが検索結果から沈む。これは自サイト＝問い合わせ獲得というチャネル設計の
前提を壊す。

**入口を1つに絞れない以上、出口で見る。** このスクリプトは経路を問わず、
リポジトリに published: true の記事が増えたときに自サイトと照合する。

【判定】

`zenn_publish_queue.py` と同じ関数を使う。判定基準がズレると意味がないので、
類似度の計算はそちらから import する（再実装しない）。

【既定は「この push で新しく公開になったもの」だけを見る】

2026-09-19 に全件監査したところ、公開済み133本のうち **68本が既に自サイトと重複**
していた（うち23本はタイトル完全一致）。これらはゲート導入（2026-09-12）より前に
公開されたもので、ゲートは未来の公開しか守れない。

全件を毎回見ると68本で必ず失敗し、**新しい事故が埋もれる。**
そこで既定では「この push で published: false → true になった記事」だけを検査する。
全件を見たいときは `--all` を付ける（棚卸し用）。

【限界】

- 自サイトの RSS には **blog しか入っていない**（column は対象外）。
  コラムとの重複は検出できない
- RSS が取れないときは警告して通す。ネットワークの一時的な失敗で
  push を止めないため。**したがってこれは保険であって、一次のゲートではない**

【例外の登録】

意図的に重複を許すものは `.github/zenn-dup-allowlist.txt` に slug を1行ずつ書く。
"""

import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
QUEUE_PY = ROOT / ".github" / "scripts" / "zenn_publish_queue.py"
ALLOWLIST = ROOT / ".github" / "zenn-dup-allowlist.txt"
ARTICLES = ROOT / "articles"


def load_queue_module():
    spec = importlib.util.spec_from_file_location("zenn_publish_queue", QUEUE_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def published_at_ref(ref: str, rel: str) -> bool | None:
    """指定リビジョンでの published 値。ファイルが無ければ None。"""
    r = subprocess.run(["git", "show", f"{ref}:{rel}"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    for line in r.stdout[:800].splitlines():
        if line.strip().startswith("published:"):
            return line.split(":", 1)[1].strip().lower() == "true"
    return False


def newly_published(base: str) -> list[Path]:
    """base から見て published: false → true になった（または新規に true で入った）記事。"""
    r = subprocess.run(["git", "diff", "--name-only", base, "--", "articles/"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"::warning title=差分を取れませんでした::base={base}. 全件検査に切り替えます")
        return [p for p in sorted(ARTICLES.glob("*.md")) if is_published(p)]
    out = []
    for rel in r.stdout.split():
        p = ROOT / rel
        if not p.exists() or p.suffix != ".md":
            continue
        if is_published(p) and published_at_ref(base, rel) is not True:
            out.append(p)
    return out


def is_published(path: Path) -> bool:
    head = path.read_text(encoding="utf-8")[:800]
    for line in head.splitlines():
        if line.strip().startswith("published:"):
            return line.split(":", 1)[1].strip().lower() == "true"
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description="Zenn公開記事と自サイトの重複を検査する")
    ap.add_argument("--all", action="store_true",
                    help="公開済み全件を検査する（棚卸し用。既定は新規公開分のみ）")
    ap.add_argument("--base", default="",
                    help="この push の直前のコミット（GitHub Actions の github.event.before）")
    args = ap.parse_args()

    q = load_queue_module()

    allow = set()
    if ALLOWLIST.exists():
        allow = {
            l.strip() for l in ALLOWLIST.read_text(encoding="utf-8").splitlines()
            if l.strip() and not l.startswith("#")
        }

    try:
        hp = q.fetch_hp_titles(q.HP_FEED_DEFAULT)
    except Exception as exc:
        print(f"::warning title=重複チェックをスキップ::自サイトRSSを取得できませんでした: {exc}")
        return 0
    if not hp:
        print("::warning title=重複チェックをスキップ::RSS からタイトルを取得できませんでした")
        return 0

    if args.all or not args.base:
        published = [p for p in sorted(ARTICLES.glob("*.md")) if is_published(p)]
        scope = f"公開済み全 {len(published)} 本"
    else:
        published = newly_published(args.base)
        scope = f"この push で新しく公開になった {len(published)} 本"
    print(f"{scope} を、自サイトRSS {len(hp)} 件と照合（閾値 {q.DUP_THRESHOLD_DEFAULT}）")
    if not published:
        print("検査対象なし。")
        return 0

    hits = []
    for p in published:
        if p.stem in allow:
            continue
        hit = q.find_duplicate(q.article_title(p), hp, q.DUP_THRESHOLD_DEFAULT)
        if hit:
            hits.append((p.stem, q.article_title(p), hit[0], hit[1]))

    if not hits:
        print("重複なし。")
        return 0

    hits.sort(key=lambda x: -x[3])
    print(f"\n重複している公開記事 {len(hits)} 本:")
    for slug, title, hp_title, score in hits:
        print(f"  類似 {score:.2f}  {slug}")
        print(f"    Zenn   : {title}")
        print(f"    自サイト: {hp_title}")

    print(
        "\n::error title=Zennと自サイトで記事が重複しています::"
        f"{len(hits)} 本。Zenn は外部 canonical に非対応のため、"
        "同テーマを両方に出すとドメインの強い Zenn が勝って自サイトが沈みます。"
        "該当記事を published: false に戻すか、意図的なら "
        ".github/zenn-dup-allowlist.txt に slug を追記してください。"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
