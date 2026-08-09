#!/usr/bin/env python3
"""抽出した SQL を検証する。

商品価値の核。GA4 の BigQuery スキーマは実際に叩くと細部で動かないため
（event_params の型、collected_traffic_source の有無、パーティション指定など）、
「全 SQL 動作検証済み」は競合が真似しにくい差別化になる。

検証は 2 段構え:

    syntax  … sqlglot の BigQuery 方言でパースする。認証不要・課金ゼロ。
              構文エラーだけを検出する。
    dryrun  … BigQuery の dry run にかける。認証が要るが課金はゼロ。
              構文に加えてスキーマ（列名・テーブル存在）まで検証できる。

syntax を通らないものは dryrun でも必ず落ちるので、まず syntax で潰す。

使い方:
    python3 scripts/validate_sql.py                      # 構文検証
    python3 scripts/validate_sql.py --mode dryrun \
        --project my-proj --dataset analytics_123456789  # スキーマまで検証

出力: assets/sql/validation.json
    scripts/queue_drafts.py がこのレポートを品質ゲートとして参照する。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# 検証用のダミー識別子。プレースホルダのままだとパーサが構文エラーにする。
_SYNTAX_PROJECT = "proj"
_SYNTAX_DATASET = "ds"


def substitute(sql: str, project: str, dataset: str) -> str:
    return sql.replace("${PROJECT}", project).replace("${DATASET}", dataset)


def strip_provenance(sql: str) -> str:
    """先頭の出典コメントを取り除く。"""
    lines = sql.splitlines()
    i = 0
    while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()):
        i += 1
    return "\n".join(lines[i:])


# 失敗の分類。パーサの限界（記事としては問題なし）と、
# 商材化するうえで実際に直すべき欠陥を分けるために使う。
#   actionable=True  … 読者がコピペしても動かない。商材に入れる前に要修正。
#   actionable=False … sqlglot が対応していないだけ。BigQuery では動く可能性が高い。
_FAILURE_KINDS: list[tuple[str, str, bool]] = [
    ("jinja", "dbt/Jinja テンプレート（そもそも素の SQL ではない）", False),
    ("incomplete", "省略記号入りで未完成（コピペしても動かない）", True),
    ("not_sql", "SQL ではない内容が ```sql で囲われている", True),
    ("snippet", "式の断片（記事の解説としては正当。単体では動かない）", False),
    ("ai_function", "AI.GENERATE / AI.EMBED 系（sqlglot 未対応）", False),
    ("bq_ml", "BigQuery ML 構文（sqlglot 未対応）", False),
    ("script", "スクリプト構文 DECLARE/FOR/EXECUTE IMMEDIATE（sqlglot 未対応）", False),
    ("multi_statement", "1 ブロックに複数文（NG例/OK例の併記）", False),
    ("syntax_error", "純粋な構文エラー", True),
]

_SQL_KEYWORDS = ("SELECT", "WITH", "CREATE", "INSERT", "UPDATE", "DELETE", "MERGE", "DECLARE")


def classify_failure(sql: str) -> tuple[str, bool]:
    """失敗した SQL を分類し、(種別, 要修正か) を返す。"""
    upper = sql.upper()

    # コメント行を除いた最初の実体行。断片かどうかの判定に使う。
    first = next(
        (
            ln.strip()
            for ln in sql.splitlines()
            if ln.strip() and not ln.strip().startswith("--")
        ),
        "",
    )

    if "{{" in sql or "{%" in sql:
        kind = "jinja"
    elif re.search(r"(?:^|\s)\.\.\.(?:\s|$)", sql, re.MULTILINE) or "（上記" in sql or "省略" in sql:
        kind = "incomplete"
    elif not any(kw in upper for kw in _SQL_KEYWORDS):
        kind = "not_sql"
    elif first.startswith("("):
        # 「(SELECT ... ) AS col」のような列式の断片。記事の解説としては正当。
        kind = "snippet"
    elif re.search(r"\bAI\.(GENERATE|EMBED)", sql, re.IGNORECASE):
        kind = "ai_function"
    elif "CREATE MODEL" in upper or re.search(r"\bML\.[A-Z_]+", upper):
        kind = "bq_ml"
    elif "EXECUTE IMMEDIATE" in upper or re.search(r"^\s*(DECLARE|FOR)\b", upper, re.MULTILINE):
        kind = "script"
    elif len(re.findall(r"^\s*(?:SELECT|WITH|CREATE)\b", sql, re.MULTILINE | re.IGNORECASE)) > 1:
        kind = "multi_statement"
    else:
        kind = "syntax_error"

    actionable = next(a for k, _, a in _FAILURE_KINDS if k == kind)
    return kind, actionable


def validate_syntax(sql: str) -> tuple[bool, str]:
    try:
        import sqlglot
    except ImportError:
        print(
            "sqlglot が必要です:  pip3 install sqlglot",
            file=sys.stderr,
        )
        raise SystemExit(2)

    prepared = substitute(sql, _SYNTAX_PROJECT, _SYNTAX_DATASET)
    try:
        statements = sqlglot.parse(prepared, dialect="bigquery")
    except Exception as exc:  # sqlglot は複数の例外型を投げる
        return False, f"{type(exc).__name__}: {exc}".split("\n")[0][:300]
    if not statements or all(s is None for s in statements):
        return False, "パース結果が空"
    return True, ""


def validate_dryrun(sql: str, project: str, dataset: str, billing_project: str):
    try:
        from google.cloud import bigquery
    except ImportError:
        print(
            "google-cloud-bigquery が必要です:  pip3 install google-cloud-bigquery",
            file=sys.stderr,
        )
        raise SystemExit(2)

    client = bigquery.Client(project=billing_project or None)
    config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
    prepared = substitute(sql, project, dataset)
    try:
        job = client.query(prepared, job_config=config)
    except Exception as exc:
        return False, f"{type(exc).__name__}: {exc}".split("\n")[0][:300], 0
    return True, "", int(job.total_bytes_processed or 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="assets/sql")
    parser.add_argument("--mode", choices=("syntax", "dryrun"), default="syntax")
    parser.add_argument("--project", default="", help="dryrun 時の実プロジェクト ID")
    parser.add_argument("--dataset", default="", help="dryrun 時の実データセット")
    parser.add_argument(
        "--billing-project", default="", help="dryrun のクエリを実行する課金先"
    )
    parser.add_argument("--limit", type=int, default=0, help="先頭 N 件だけ検証")
    args = parser.parse_args()

    sql_dir = Path(args.dir)
    index_path = sql_dir / "index.json"
    if not index_path.exists():
        print(
            f"{index_path} がありません。先に scripts/extract_sql.py を実行してください。",
            file=sys.stderr,
        )
        return 1

    if args.mode == "dryrun" and not (args.project and args.dataset):
        print("dryrun には --project と --dataset が必要です。", file=sys.stderr)
        return 1

    index = json.loads(index_path.read_text(encoding="utf-8"))
    entries = index["entries"]
    if args.limit:
        entries = entries[: args.limit]

    results = []
    passed = failed = 0
    total_bytes = 0

    for entry in entries:
        raw = (sql_dir / entry["file"]).read_text(encoding="utf-8")
        sql = strip_provenance(raw)

        if args.mode == "syntax":
            ok, error = validate_syntax(sql)
            scanned = 0
        else:
            ok, error, scanned = validate_dryrun(
                sql, args.project, args.dataset, args.billing_project
            )
            total_bytes += scanned

        passed, failed = (passed + 1, failed) if ok else (passed, failed + 1)
        kind, actionable = ("", False) if ok else classify_failure(sql)

        # 商材に載せられるのは「検証を通過した、単体で完結するクエリ」だけ。
        # 記事の解説用の断片は除く。商品①(SQL パック)の選定条件になる。
        first = next(
            (
                ln.strip()
                for ln in sql.splitlines()
                if ln.strip() and not ln.strip().startswith("--")
            ),
            "",
        )
        product_ready = ok and bool(
            re.match(r"(?:SELECT|WITH|CREATE|MERGE|INSERT)\b", first, re.IGNORECASE)
        )
        results.append(
            {
                "file": entry["file"],
                "slug": entry["slug"],
                "article": entry["article"],
                "category": entry["category"],
                "published": entry["published"],
                "ok": ok,
                "error": error,
                "kind": kind,
                "actionable": actionable,
                "product_ready": product_ready,
                **({"bytes": scanned} if args.mode == "dryrun" else {}),
            }
        )

    # 記事単位の合否。queue_drafts.py はこれを品質ゲートに使う。
    # ゲートは「要修正(actionable)な失敗が無いこと」。パーサ未対応は落とさない。
    by_article: dict[str, dict] = {}
    for r in results:
        a = by_article.setdefault(
            r["slug"],
            {
                "slug": r["slug"],
                "article": r["article"],
                "total": 0,
                "failed": 0,
                "actionable": 0,
            },
        )
        a["total"] += 1
        if not r["ok"]:
            a["failed"] += 1
            if r["actionable"]:
                a["actionable"] += 1
    for a in by_article.values():
        a["ok"] = a["actionable"] == 0

    report = {
        "mode": args.mode,
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "pass_rate": round(passed / len(results) * 100, 1) if results else 0.0,
        "articles": by_article,
        "results": results,
    }
    out = sql_dir / "validation.json"
    out.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(f"検証モード : {args.mode}")
    print(f"  検証本数 : {len(results)}")
    print(f"  成功     : {passed}")
    print(f"  失敗     : {failed}")
    print(f"  成功率   : {report['pass_rate']}%")
    ok_articles = sum(1 for a in by_article.values() if a["ok"])
    print(f"  要修正なしの記事 : {ok_articles} / {len(by_article)}")

    ready = [r for r in results if r["product_ready"]]
    print(f"\n商材に載せられる SQL（検証通過かつ単体で完結）: {len(ready)} 本")
    cats: dict[str, int] = {}
    for r in ready:
        cats[r["category"] or "(未分類)"] = cats.get(r["category"] or "(未分類)", 0) + 1
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"    {cat:22} {n}")
    if args.mode == "dryrun":
        print(f"  総スキャン量（dry run 実測）: {total_bytes / 1024**3:.2f} GB 相当")
    print(f"  レポート : {out}")

    if failed:
        counts: dict[str, int] = {}
        for r in results:
            if not r["ok"]:
                counts[r["kind"]] = counts.get(r["kind"], 0) + 1

        print("\n失敗の内訳:")
        for kind, label, actionable in _FAILURE_KINDS:
            n = counts.get(kind, 0)
            if n:
                mark = "要修正" if actionable else "許容 "
                print(f"  [{mark}] {n:3}  {label}")

        todo = [r for r in results if not r["ok"] and r["actionable"]]
        print(f"\n商材化の前に直すべき SQL: {len(todo)} 本")
        for r in todo[:10]:
            print(f"  - {r['file']}  ({r['kind']})")
        if len(todo) > 10:
            print(f"  ... 他 {len(todo) - 10} 本")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
