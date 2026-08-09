# scripts/ — 収益化パイプライン

記事資産を「集客装置」と「商品の原材料」に分けて運用するためのスクリプト群。
すべて冪等（何度実行しても結果が同じ）なので、記事が増えるたびに再実行してよい。

## 通常の運用サイクル

記事を追加・編集したら、この順で流す。

```bash
python3 scripts/extract_sql.py          # 記事からSQLを抽出しカタログ化
python3 scripts/validate_sql.py         # 構文検証（認証不要・課金ゼロ）
python3 scripts/build_internal_links.py # 内部リンクを張り直す
python3 scripts/bulk_cta.py             # CTAを最新の文言に揃える
```

`build_internal_links.py` は公開済み記事にしかリンクしないため、
下書きが公開されるたびに再実行するとリンク網が育つ。

## 各スクリプト

### bulk_cta.py — 記事末尾CTAの統一

全記事の末尾CTAを1つのテンプレートで管理する。
**文言・価格・リンク先を変えたいときは、このファイル冒頭の「CTA設定」だけを書き換えて再実行する。**

商品を投入したら、ここを商品LPへの導線に差し替える（1コマンドで全記事に反映される）。

```bash
python3 scripts/bulk_cta.py --dry-run
python3 scripts/bulk_cta.py
```

### build_internal_links.py — 内部リンクのクラスタ化

themes.csv の同カテゴリ（+10点）と frontmatter の topics の重なり（+1点/件）で
関連度を採点し、上位4件を「## 関連記事」として生成する。

リンク先は `published: true` の記事のみ。下書きへのリンクは Zenn 上で 404 になるため。

### extract_sql.py — SQLの抽出とカタログ化

記事中の ```sql ブロックを1本1ファイルに切り出し、`assets/sql/` に出力する。
テーブル参照の表記ゆれを `${PROJECT}` / `${DATASET}` に正規化する。

`assets/sql/index.json` に出典（記事・見出し・カテゴリ）が入る。
これが商品①（SQLパック）と商品③（実装キット）の原材料になる。

### validate_sql.py — SQLの検証

**商品価値の核。** 「全SQL動作検証済み」は競合が真似しにくい差別化であり、価格の根拠になる。

```bash
# 構文検証（認証不要・課金ゼロ）
pip3 install sqlglot
python3 scripts/validate_sql.py

# スキーマまで検証（要認証・dry runなので課金ゼロ）
pip3 install google-cloud-bigquery
python3 scripts/validate_sql.py --mode dryrun \
    --project <実プロジェクトID> --dataset <実データセット>
```

失敗は「要修正」と「パーサ未対応（BigQueryでは動く）」に自動分類される。
直すべきは「要修正」だけ。

結果は `assets/sql/validation.json` に出力され、`queue_drafts.py` の品質ゲートになる。

### queue_drafts.py — 下書きの公開キュー投入（品質ゲート付き）

```bash
python3 scripts/queue_drafts.py --dry-run
python3 scripts/queue_drafts.py --max 20
```

**なぜゲートが要るか。**
下書きは AI 一括生成であることが構造上明らかで、Zenn は 2025-06 の規約改定で
「機械により自動生成された文章の投稿」をスパムとして明記している。
公開済み記事の検索流入が収益計画全体の入口である以上、アカウント凍結は最大の事業リスク。

そのため検証を通過した記事だけをキューに入れる。検証レポートが無ければ実行を拒否する。
SQL を含まない散文のみの記事は既定で対象外（`--include-prose` で明示的に含められる）。

投入後は `.github/workflows/zenn-staggered-publish.yml` が日次2本ずつ公開する。

### build_sql_pack.py — 販売用SQLパッケージの組み立て

検証済みSQLから実用的なものを選び、1本ずつに「用途 / 必要なテーブル / コストの注意」を
付けて販売用ドキュメントに束ねる。1つの機構で2種類の商材を作れる。

```bash
# 商品①（フロント・note用）: 50本パック。冒頭3本が無料公開部
python3 scripts/build_sql_pack.py

# 商品③（実装キット同梱）: 全カテゴリのフルカタログ
python3 scripts/build_sql_pack.py \
    --categories all --count 500 --max-per-article 99 --min-lines 5 \
    --preview 0 --title "GA4 × BigQuery 実務SQL 全集" \
    --out assets/products/sql-catalog-full
```

出力される `README.md` はそのまま note に貼れる形式。
コストの注意は静的解析（`_TABLE_SUFFIX` の有無、`SELECT *` の有無）で判定している。
BigQuery の dry run を通したあとは、実測スキャン量に差し替えるとより強い訴求になる。

### build_book.py — 商品②（Zenn Books）の生成

`articles/` のJ系列25本から `books/bigquery-ga4-operations-guide/` を生成する。

```bash
python3 scripts/build_book.py --dry-run
python3 scripts/build_book.py
```

**なぜJ系列を書籍にするか**: 同じ内容を無料公開しながら3,900円で売ることはできない。
J系列25本は全て未公開なので、書籍専用にすれば独占性が作れる。
内容もスケジュールクエリ・IAM・コスト管理・dbt・Terraform といった「運用」で、
Zennのエンジニア読者層に最も合う。I系列（EC実務・175,195字）は将来のnote商材用に温存。

このスクリプトは記事に `book_only: true` を付ける。
`queue_drafts.py` がこれを見て無料公開の対象から外す。**これが無いと書籍の中身が無料公開される。**

記事→チャプターの変換で、CTA・関連記事の除去、frontmatterの入れ替え、
J系列記事へのリンクの章間リンク化、「この記事では」→「本章では」の語彙変換を行う。

まえがき（`preface.md`）は唯一の書き下ろしで、再実行しても上書きされない。

公開するには `config.yaml` の `published` を `true` にする。

### modernize_api_code.py — Anthropic モデルIDの現行化

```bash
python3 scripts/modernize_api_code.py --dry-run
python3 scripts/modernize_api_code.py
```

記事中の `model=` の値だけを対象に、旧世代のモデルIDを現行世代へ移す。ティアは保つ
（Sonnet→Sonnet / Opus→Opus）。日次実行など高頻度の用途で一律 Opus にすると
読者の請求額が上がるため。本文中のモデル名への言及や Gemini の model 指定は書き換えない。

`temperature` / `top_p` は**対象外**。実測したところ temperature は全て BigQuery ML の
`STRUCT(0.0 AS temperature, ...)`（Gemini向け）、top_p は全て `top_pages` という
関数名への部分一致で、Anthropic 呼び出しでの使用はゼロだった。触ると記事を壊すだけになる。

### build_kit.py — 商品③（実装キット）の生成

```bash
python3 scripts/build_kit.py
```

`assets/products/ec-data-platform-kit/` に SQL・Pythonスクリプト・dbt雛形・
Looker Studio のデータ層・プロンプト集を生成する。

`README.md` / `looker-studio/setup-guide.md` / `dbt/README.md` は書き下ろしのため
再実行しても上書きされない。

**Looker Studio のレポート本体は生成できない。** クラウド上の成果物で、GUI で作成して
テンプレート共有リンクを発行する必要があり、ファイルとして書き出す手段がないため。
代わりにレポートが乗るデータ層（ビュー定義47個・フィールド定義書・接続手順）を同梱し、
レポート作成だけを購入者の作業として残している。

`dbt_project.yml` はどの記事にも無いのでスクリプトが生成する。
プロファイル名は `profiles.yml.example` の最上位キーと自動で揃う。

## 現状（最終実行時）

| 指標 | 着手前 | 現在 |
|---|---|---|
| 記事 | 197本（公開93 / 下書き104） | 同左 |
| 内部リンク | 9本 | **793本** |
| CTA設置 | 132本・ココナラ導線4分散 | **197本すべて・導線1本** |
| 抽出SQL | — | 503本 |
| 構文検証通過 | — | **479本（95.2%）** |
| 商材に載せられるSQL | — | 466本 |
| 要修正SQL | 10本 | **0本** |
| 要修正なしの記事 | 158/167 | **167/167** |
| 公開キュー投入可 | 88本 | **70本**（J系列25本は書籍専用のため除外） |

### 商材の生成物

| 商材 | 場所 | 内容 |
|---|---|---|
| 商品① SQL 50本パック | `assets/products/sql-pack-50/` | 50本（BigQuery×GA4 25 / EC分析25）、収録元28記事 |
| 商品② Zenn Books | `books/bigquery-ga4-operations-guide/` | 26章・137,314字・SQL64個、3,900円 |
| 商品③ 実装キット | `assets/products/ec-data-platform-kit/` | SQL466 / Python33 / dbt10 / ビュー47 / プロンプト12、19,800円 |
| （参考）フルカタログ | `assets/products/sql-catalog-full/` | 456本（全10カテゴリ）、収録元164記事 |

収録SQLは個別に再パースして NG 0件、キット内の Python 33本は `py_compile` を通過済み。
**Python の実行検証は BigQuery・各種API の認証が要るため未実施**で、その旨をキットの
README に明記している（SQL を「構文検証済み」と正直に書いているのと同じ扱い）。

**商品①にJ系列を入れないこと。** 書籍専用の内容をより安い商材（1,980円）に入れると
書籍（3,900円）が売れなくなる。再生成は必ず除外オプション付きで：

```bash
python3 scripts/build_sql_pack.py \
    --categories "EC向けデータ分析" "BigQuery×GA4" \
    --exclude-categories "データ基盤設計・運用Tips"
```
