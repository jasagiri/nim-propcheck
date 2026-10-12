# G2 変異検出の記録 — propcheck

**対象**: `src/propcheck.nim` **E テスト**: `tests/external/test_propcheck.nim`

**未測定** (2026-10-07 に作った)。push の前に測り、生き残りを ADR-MUTER-0004 §3.3 の 4 種類に分けて理由を書く。

2026-10-12: 設定 `tests/mutation/propcheck.json` とジョブ `.github/workflows/g2.yml` を置き、待ち行列に入れた (nim-muter 0.2.7、ビルドと実行を分け、テストごとの検出を記録する)。元のコードでビルドとテストが通ることは確かめた。結果が出たら、生き残りを 1 件ずつここに書く。
