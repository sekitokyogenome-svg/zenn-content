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

## 現状（最終実行時）

| 指標 | 値 |
|---|---|
| 記事 | 197本（公開93 / 下書き104） |
| 内部リンク | 793本（着手前は9本） |
| CTA設置 | 197本すべて（着手前は132本、ココナラ導線は4分散） |
| 抽出SQL | 504本 |
| 構文検証通過 | 470本（93.3%） |
| 商材に載せられるSQL | 457本 |
| 要修正SQL | 10本 |
| 公開キュー投入可 | 88本（ゲート通過） |
