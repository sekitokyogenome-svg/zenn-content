---
title: "ZennのGitHub連携の投稿レート制限を、GitHub Actionsの段階公開で回避する"
emoji: "🚦"
type: "tech"
topics: ["zenn", "githubactions", "python", "個人開発"]
published: false
publish_queue: true
---

## 70記事を一気にpushしたら、全部公開されなかった

ZennはGitHubリポジトリと連携でき、`articles/` に Markdown を置いて push すれば記事が公開される。とても快適なのだが、**まとまった数の記事を一度に公開しようとして詰まった**。

`published: true` の記事を一括で push したところ、デプロイのログにこう出た。

> 次の記事は投稿数の上限に達したためデプロイされませんでした: `article-a`, `article-b`, …（十数件）

デプロイ自体は「成功」。なのに記事は公開されない。原因は **Zennのスパム対策レート制限** だった。この記事では、その仕様の整理と、**GitHub Actionsで「1日N本ずつ自動公開」する段階公開スケジューラ**を作って恒久対応した話を、コード付きで書く。

## Zennのレート制限の仕様（実地で分かったこと）

公式FAQに「一定時間内の投稿数上限」とあるが、具体的な数値は公開されていない。実際に踏んで分かった挙動は次のとおり。

- **制限対象は「新規公開」だけ**。`published: false → true` の記事がカウントされる
- **すでに公開済み記事の更新は対象外**。`published: true` のまま本文を直す分にはいくら push しても通る
- **`published: false`（下書き）の push もカウントされない**。公開しないので当然
- 上限を超えた記事は**自動で公開されず保留**され、「しばらく時間をあけて再デプロイ」で順次通る

つまり「一度に公開していい本数」に上限があり、**バッチ公開と相性が悪い**。3本以上をまとめて公開しようとすると引っかかりやすい。

## ヒヤリ：一括で下書きに戻して、危うく公開記事を巻き込む

最初、特定の1本を優先公開したくて「他の記事を一時的に下書きに戻す」一手を打った。これがまずかった。

```bash
# 危険：published: true の記事を“全部”下書きに戻してしまう
sed -i 's/^published: true/published: false/' articles/*.md
```

`git commit` のログが `70 files changed` ——意図したのは保留中の十数本だけだったのに、**すでに公開済みだった記事まで巻き込んで下書き化**しようとしていた。公開済み記事の更新は前述のとおりレート制限を受けずに即反映されるので、**これは公開中の記事を一気に非公開化しかねない操作**だった。

幸い気づいて `git revert` で即復旧した。教訓は2つ。

1. `sed -i ... articles/*.md` のような**全ファイル一括置換は、対象範囲を必ず数えてから**。`git status` の変更ファイル数が想定と合うか確認する
2. 公開状態のような**不可逆に近い操作は、対象を明示的に絞る**（「全部」ではなく「このリストだけ」）

この一件で「手作業で公開状態をいじるのは事故る」と確信し、仕組み化に倒した。

## 解決方針：公開キューを作る

やりたいことはシンプルだ。**「公開待ち」の記事を、1日に数本ずつ自動で公開する**。レート制限の幅に収まるペースで放出すれば、バッチで書いても詰まらない。

設計のキモは「**書きかけの下書きと、公開待ちの完成記事を区別する**」こと。frontmatter に専用フラグを足して、次の2条件を**両方**満たす記事だけを対象にする。

```yaml
published: false      # まだ公開していない
publish_queue: true   # かつ「公開待ちキュー」に入れた
```

`publish_queue` を持たない通常の下書きには**絶対に触らない**。これで「書きかけが勝手に公開される」事故を防ぐ。

公開時はこう書き換える。

| Before | After |
|---|---|
| `published: false` | `published: true` |
| `publish_queue: true` | （行を削除して frontmatter を綺麗に保つ） |

## 実装1：公開スクリプト（依存なし）

標準ライブラリだけで書いた。frontmatter を雑にパースせず、**先頭の `---` ブロックだけを対象に**して本文を巻き込まないようにしている。

```python
import argparse
import re
import sys
from pathlib import Path

_PUBLISHED_RE = re.compile(r"^published:\s*(true|false)\s*$", re.MULTILINE)
_QUEUE_RE = re.compile(r"^publish_queue:\s*(true|false)\s*$", re.MULTILINE)


def _split_frontmatter(text: str):
    """先頭の YAML frontmatter を (header, rest) に分割。無ければ None。"""
    if not text.startswith("---"):
        return None
    m = re.search(r"\n---[ \t]*\r?\n", text)  # 2個目の '---' 行
    if not m:
        return None
    return text[: m.end()], text[m.end():]


def _flag(header: str, regex: re.Pattern):
    m = regex.search(header)
    return None if not m else m.group(1) == "true"


def find_queued(articles_dir: Path) -> list[Path]:
    """published:false かつ publish_queue:true の記事をファイル名昇順で返す。"""
    queued = []
    for path in sorted(articles_dir.glob("*.md")):
        parts = _split_frontmatter(path.read_text(encoding="utf-8"))
        if parts is None:
            continue
        header, _ = parts
        if _flag(header, _PUBLISHED_RE) is False and _flag(header, _QUEUE_RE) is True:
            queued.append(path)
    return queued


def publish(path: Path) -> None:
    """1記事を公開状態にする（published:true、publish_queue 行を削除）。"""
    header, rest = _split_frontmatter(path.read_text(encoding="utf-8"))
    header = _PUBLISHED_RE.sub("published: true", header, count=1)
    header = re.sub(r"^publish_queue:\s*(?:true|false)\s*\r?\n", "", header,
                    count=1, flags=re.MULTILINE)
    path.write_text(header + rest, encoding="utf-8")
```

メイン処理は「対象を集める → 先頭からN本だけ公開」するだけ。`--dry-run` で対象確認、`--max` で本数を絞れるようにした。

```python
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Zenn 記事を段階的に公開する")
    ap.add_argument("--dir", default="articles")
    ap.add_argument("--max", type=int, default=2)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    queued = find_queued(Path(args.dir))
    if not queued:
        print("公開待ちの記事はありません")
        return 0

    targets = queued[: args.max]
    print(f"公開待ち {len(queued)} 本中、今回 {len(targets)} 本を公開します"
          f"（残り {len(queued) - len(targets)} 本）:")
    for path in targets:
        print(f"  - {path.name}")
        if not args.dry_run:
            publish(path)
    return 0
```

ローカルで挙動を確認できる。

```bash
$ python3 zenn_publish_queue.py --dir articles --max 2 --dry-run
公開待ち 18 本中、今回 2 本を公開します（残り 16 本）:
  - ga4-bigquery-product-page-exit-rate.md
  - ga4-bigquery-search-console-organic.md
（--dry-run のため変更していません）
```

書きかけの下書き（`publish_queue` なし）も、公開済み記事（`published: true`）も、対象に入らない。狙ったものだけが動く。

## 実装2：GitHub Actionsで毎日まわす

あとはこれを cron で定期実行し、変更があればリポジトリに push し返すだけ。`GITHUB_TOKEN` に書き込み権限を与えるため `permissions: contents: write` を付ける。

```yaml
name: Zenn staggered publish

on:
  schedule:
    - cron: "0 0 * * *"   # 毎日 00:00 UTC = 09:00 JST
  workflow_dispatch:
    inputs:
      max:
        description: "今回公開する最大本数"
        default: "2"

permissions:
  contents: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Publish queued articles
        run: |
          python3 .github/scripts/zenn_publish_queue.py \
            --dir articles --max "${{ github.event.inputs.max || '2' }}"

      - name: Commit & push if changed
        run: |
          if [ -z "$(git status --porcelain)" ]; then
            echo "公開対象なし。終了します。"; exit 0
          fi
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "chore: staggered publish of queued Zenn articles"
          git push
```

:::message
リポジトリ設定 → Actions → General → **Workflow permissions** を「Read and write permissions」にしておく。これを忘れると Action の `git push` が 403 で落ちる。
:::

## 使い方

公開したい完成記事に、`published: false` のまま `publish_queue: true` を足して push するだけ。

```yaml
---
title: "記事タイトル"
emoji: "📝"
type: "tech"
topics: ["python"]
published: false
publish_queue: true
---
```

あとは毎朝2本ずつ自動で公開される。すぐ出したいときは Actions タブから手動実行（`max` を指定可）。本数を上げてレート制限に触れたら2に戻す、くらいの運用で十分回る。

## まとめ

- Zennの連携には**新規公開のレート制限**がある（更新と下書きは対象外）
- バッチ公開は詰まる。**公開状態の手作業一括変更は事故りやすい**（`*.md` 一括 sed は変更ファイル数を必ず確認）
- `published: false` × `publish_queue: true` を**1日N本ずつ公開**する仕組みで恒久解決
- 標準ライブラリのスクリプト＋GitHub Actionsの cron だけ。依存もインフラも増えない

「書いたら push、あとは勝手に順次公開」になって、執筆のリズムと公開のペースを切り離せた。同じくZenn×GitHub連携で記事を量産している人の参考になれば。

:::message
ちなみにこの記事自体も、`publish_queue: true` を付けて、ここで紹介したスケジューラに公開してもらっています。
:::
