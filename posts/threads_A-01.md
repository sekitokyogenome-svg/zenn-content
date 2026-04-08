「GA4の管理画面、サンプリングで正確な数値が出ない」「14か月より前のデータが消えてしまう」と感じたことはありませんか。

GA4単体の限界を突破する方法として、BigQueryエクスポートがあります。設定の全手順を整理しました。

- GCPプロジェクトを作成し、BigQuery APIを有効にする
- GA4管理画面からBigQueryリンクを設定（ロケーションは後から変更不可）
- 日次エクスポートから始めるとコストを最小限に抑えられる
- テーブルは events_YYYYMMDD 形式で翌日に自動生成される
- ga_session_id の取得には UNNEST 構文が必須
- 流入元は collected_traffic_source.manual_medium で取得（traffic_source との混同に注意）
- 月間10万PV規模であれば無料枠内で運用できるケースがほとんど

設定手順から典型的なハマりどころまで、実務ベースでまとめています。BigQueryを使ったデータ分析基盤の入口として、ぜひ参考にしてください。

https://zenn.dev/web_benriya/articles/ga4-bigquery-export-setup-guide-2026

#GA4 #BigQuery
