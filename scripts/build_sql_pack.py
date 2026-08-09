#!/usr/bin/env python3
"""検証済み SQL を販売用パッケージに組み立てる。

買い手が払うのは知識ではなく時間短縮。SQL は記事に散らばっていて
「探す・繋ぐ・動くか検証する」コストがかかる。そこを肩代わりしたものが商品になる。

検証済み SQL の中から実用的なものを選び、1 本ずつに
「用途 / 必要なテーブル / コストの注意」を付けて 1 つのドキュメントに束ねる。

選定の条件:
    - validate_sql.py の product_ready（検証通過かつ単体で完結）
    - 指定カテゴリ（'all' で全カテゴリ）
    - --min-lines 未満の断片は除外（有料にするには薄い）
    - 1 記事あたり --max-per-article 本まで（内容の重複を避ける）
    - カテゴリ間はラウンドロビンで選抜（スコア順だけだと集計系の多い
      EC 分析に偏り、基盤運用がほとんど入らなくなるため）

使い方:

    # 商品①: フロント商品の 50 本パック（冒頭 3 本は無料公開部）
    python3 scripts/build_sql_pack.py

    # 商品③: 実装キットに同梱するフルカタログ
    python3 scripts/build_sql_pack.py \\
        --categories all --count 500 --max-per-article 99 --min-lines 5 \\
        --preview 0 --title "GA4 × BigQuery 実務SQL 全集" \\
        --out assets/products/sql-catalog-full
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

DEFAULT_CATEGORIES = ("EC向けデータ分析", "データ基盤設計・運用Tips")

MIN_LINES = 10
MAX_PER_ARTICLE = 2

_TABLE_RE = re.compile(r"\$\{PROJECT\}\.\$\{DATASET\}\.([A-Za-z0-9_*]+)")


def strip_provenance(text: str) -> str:
    lines = text.splitlines()
    i = 0
    while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()):
        i += 1
    return "\n".join(lines[i:]).strip()


def required_tables(sql: str) -> list[str]:
    return sorted(set(_TABLE_RE.findall(sql)))


def cost_note(sql: str) -> str:
    """静的解析でスキャン量の注意点を出す。dry run が無くても言えることだけ書く。"""
    notes = []
    upper = sql.upper()
    has_suffix = "_TABLE_SUFFIX" in upper
    scans_events = bool(re.search(r"events_\*", sql))

    if scans_events and not has_suffix:
        notes.append("`_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください")
    elif has_suffix:
        notes.append("`_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です")
    if re.search(r"SELECT\s+\*", upper):
        notes.append("`SELECT *` を含みます。必要な列だけに絞るとコストが下がります")
    if not notes:
        notes.append("スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください")
    return " / ".join(notes)


def usefulness(sql: str, lines: int) -> int:
    """実用性の目安。集計・結合を伴う実務的なクエリを上位に。"""
    upper = sql.upper()
    score = 0
    if "GROUP BY" in upper:
        score += 3
    if " JOIN " in upper:
        score += 2
    if "WITH " in upper:
        score += 2
    if "OVER (" in upper or "OVER(" in upper:
        score += 2
    if "_TABLE_SUFFIX" in upper:
        score += 1  # コスト意識のあるクエリ
    if "SAFE_DIVIDE" in upper:
        score += 1
    # 短すぎず長すぎない実務レンジを優遇
    if 15 <= lines <= 60:
        score += 2
    return score


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sql-dir", default="assets/sql")
    parser.add_argument("--out", default="assets/products/sql-pack-50")
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--preview", type=int, default=3, help="無料公開部の本数")
    parser.add_argument(
        "--categories",
        nargs="*",
        default=list(DEFAULT_CATEGORIES),
        help="対象カテゴリ。'all' で全カテゴリ",
    )
    parser.add_argument(
        "--exclude-categories",
        nargs="*",
        default=[],
        help="除外するカテゴリ。書籍専用にした系列を安い商材に入れないために使う",
    )
    parser.add_argument(
        "--max-per-article",
        type=int,
        default=MAX_PER_ARTICLE,
        help="1記事から採用する上限。フルカタログを作るときは大きくする",
    )
    parser.add_argument("--title", default="GA4 × BigQuery 分析SQL 50本パック")
    parser.add_argument("--min-lines", type=int, default=MIN_LINES)
    args = parser.parse_args()

    all_categories = args.categories == ["all"]

    sql_dir = Path(args.sql_dir)
    report = json.loads((sql_dir / "validation.json").read_text(encoding="utf-8"))
    index = {
        e["file"]: e
        for e in json.loads((sql_dir / "index.json").read_text(encoding="utf-8"))["entries"]
    }

    candidates = []
    for r in report["results"]:
        if not r["product_ready"]:
            continue
        if not all_categories and r["category"] not in args.categories:
            continue
        if r["category"] in args.exclude_categories:
            continue
        meta = index[r["file"]]
        if meta["lines"] < args.min_lines:
            continue
        sql = strip_provenance((sql_dir / r["file"]).read_text(encoding="utf-8"))
        candidates.append(
            {
                "file": r["file"],
                "slug": r["slug"],
                "title": meta["title"],
                "heading": meta["heading"] or meta["title"],
                "category": r["category"],
                "lines": meta["lines"],
                "sql": sql,
                "score": usefulness(sql, meta["lines"]),
            }
        )

    # スコア降順。同点は file 名で安定させる。
    candidates.sort(key=lambda c: (-c["score"], c["file"]))

    # カテゴリごとの待ち行列を作り、順番に取り出す（ラウンドロビン）。
    # 単純なスコア順だと集計系の多い EC 分析に偏り、
    # 基盤運用まわりがほとんど入らなくなるため。
    queues: dict[str, list[dict]] = {}
    for c in candidates:
        queues.setdefault(c["category"], []).append(c)

    picked: list[dict] = []
    per_article: dict[str, int] = {}
    while len(picked) < args.count and any(queues.values()):
        for cat in list(queues):
            if len(picked) >= args.count:
                break
            queue = queues[cat]
            while queue:
                c = queue.pop(0)
                if per_article.get(c["slug"], 0) >= args.max_per_article:
                    continue
                per_article[c["slug"]] = per_article.get(c["slug"], 0) + 1
                picked.append(c)
                break

    # 最終的な並びはカテゴリでまとめ、その中はスコア順にする
    picked.sort(key=lambda c: (c["category"], -c["score"], c["file"]))

    # 商品としての見出しを決める。
    # 記事内の見出しは「Step 2:」「方法1:」のように単体では意味をなさないものが多いので、
    # 記事タイトルを主ラベルにし、見出しは「何が分かるか」側に回す。
    # 同じ記事から複数採用した場合だけ、見出しを括弧で添えて区別する。
    title_counts: dict[str, int] = {}
    for c in picked:
        title_counts[c["title"]] = title_counts.get(c["title"], 0) + 1
    for c in picked:
        if title_counts[c["title"]] > 1 and c["heading"] != c["title"]:
            c["label"] = f"{c['title']}（{c['heading']}）"
        else:
            c["label"] = c["title"]

    # 同じ記事の同じ見出しから複数採用した場合はまだ衝突するので通し番号で分ける
    seen: dict[str, int] = {}
    for c in picked:
        seen[c["label"]] = seen.get(c["label"], 0) + 1
    numbering: dict[str, int] = {}
    for c in picked:
        if seen[c["label"]] > 1:
            numbering[c["label"]] = numbering.get(c["label"], 0) + 1
            c["label"] = f"{c['label']} その{numbering[c['label']]}"

    out_dir = Path(args.out)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "sql").mkdir(parents=True)

    doc: list[str] = []
    doc.append(f"# {args.title}\n")
    doc.append(
        f"GA4 の BigQuery エクスポートを前提にした、実務で使う分析SQLを {len(picked)} 本まとめたものです。\n"
        "**全てのSQLは BigQuery の方言でパース検証済み**で、"
        "コピーして `${PROJECT}` と `${DATASET}` を自社の値に置き換えればそのまま動きます。\n"
    )
    doc.append(
        "GA4 の BigQuery スキーマは、実際に叩くと細部で動きません。"
        "`event_params` の型、`collected_traffic_source` の有無、パーティションの指定。"
        "収録したSQLは、その「動かない」を先に潰してあります。\n"
    )
    doc.append("## 収録内容\n")
    cats: dict[str, int] = {}
    for c in picked:
        cats[c["category"]] = cats.get(c["category"], 0) + 1
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        doc.append(f"- {cat}: {n} 本")
    doc.append("")
    doc.append("## 使い方\n")
    doc.append(
        "各SQLの `${PROJECT}` を GCP プロジェクトID、`${DATASET}` を "
        "GA4 のデータセット（`analytics_XXXXXXXXX`）に置き換えてください。\n"
        "実行前に必ずドライランでスキャン量を確認することをおすすめします。\n"
    )
    doc.append("```bash")
    doc.append("bq query --dry_run --use_legacy_sql=false '<SQLをここに貼る>'")
    doc.append("```\n")

    if args.preview:
        doc.append("---\n")
        doc.append(f"## サンプル（{args.preview}本を無料公開）\n")

    for i, c in enumerate(picked, start=1):
        if args.preview and i == args.preview + 1:
            doc.append("---\n")
            doc.append("## ここから先は購入者限定\n")

        doc.append(f"### {i:02d}. {c['label']}\n")
        if c["heading"] and c["heading"] != c["title"]:
            doc.append(f"**用途**: {c['heading']}\n")
        tables = required_tables(c["sql"])
        if tables:
            doc.append(
                "**必要なテーブル**: "
                + ", ".join(f"`${{DATASET}}.{t}`" for t in tables)
                + "\n"
            )
        doc.append(f"**コストの注意**: {cost_note(c['sql'])}\n")
        doc.append("```sql")
        doc.append(c["sql"])
        doc.append("```\n")

        name = f"{i:02d}_{c['slug']}.sql"
        (out_dir / "sql" / name).write_text(
            f"-- {i:02d}. {c['label']}\n"
            f"-- 用途: {c['heading']}\n"
            f"-- ${{PROJECT}} / ${{DATASET}} を自社の値に置換して実行\n\n"
            + c["sql"]
            + "\n",
            encoding="utf-8",
        )

    (out_dir / "README.md").write_text("\n".join(doc), encoding="utf-8")

    print(f"候補 {len(candidates)} 本 → 採用 {len(picked)} 本")
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {cat:22} {n}")
    print(f"  収録元の記事数 : {len(per_article)}")
    print(f"  出力           : {out_dir}/README.md（note にそのまま貼れる）")
    print(f"                   {out_dir}/sql/ に個別ファイル {len(picked)} 本")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
