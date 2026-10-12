"""Zenn が保存に失敗する frontmatter を、push 前に検出する。

Zenn は articles/ の1本でも保存に失敗すると、デプロイ全体を中断する（2026-10-10 に発生）。
そのため変更分だけでなく、全記事を毎回検査する。

検査内容:
  - title は 70 文字以内（Zenn のエラー文言: 「Titleには最大70文字まで使用できます」）
    JavaScript の文字列長（UTF-16 の単位）で数える。絵文字などは2と数える。
  - slug（ファイル名）は半角英数字・ハイフン・アンダースコアで 12〜50 文字
  - topics は 5 個まで

slug と topics の基準は Zenn の公式ドキュメント上の記述に基づく（2026-10-12 時点で
このリポジトリの全記事が満たしていることを確認済み）。
"""
import glob
import os
import re
import sys

TITLE_MAX = 70
SLUG_RE = re.compile(r"^[a-z0-9_-]{12,50}$")
TOPICS_MAX = 5


def utf16_len(s):
    return len(s.encode("utf-16-le")) // 2


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""


def main():
    errors = []
    files = sorted(glob.glob("articles/*.md"))
    for f in files:
        slug = os.path.splitext(os.path.basename(f))[0]
        head = frontmatter(open(f, encoding="utf-8").read())
        if not SLUG_RE.match(slug):
            errors.append((f, f"slug は半角英数字・ハイフン・アンダースコアで12〜50文字（現在 {len(slug)} 文字: {slug}）"))
        m = re.search(r'^title:\s*(.*)$', head, re.M)
        if not m:
            errors.append((f, "title がありません"))
        else:
            title = m.group(1).strip()
            if title[:1] in "\"'" and title[-1:] == title[:1]:
                title = title[1:-1]
            n = utf16_len(title)
            if n > TITLE_MAX:
                errors.append((f, f"title が {n} 文字です（Zenn の上限は {TITLE_MAX} 文字）: {title}"))
        t = re.search(r'^topics:\s*\[(.*)\]', head, re.M)
        if t:
            k = len([x for x in t.group(1).split(",") if x.strip()])
            if k > TOPICS_MAX:
                errors.append((f, f"topics が {k} 個です（上限 {TOPICS_MAX} 個）"))
    print(f"{len(files)} 本を検査")
    for f, msg in errors:
        print(f"::error file={f},title=Zenn が保存に失敗する記事::{msg}")
    if errors:
        print(f"\n{len(errors)} 件。1本でもあるとデプロイ全体が中断します。")
        sys.exit(1)
    print("問題なし")


if __name__ == "__main__":
    main()
