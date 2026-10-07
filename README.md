# nim-propcheck

性質にもとづくテスト。入力を種から生成して性質を確かめ、破れたら、破れる最小の入力まで縮めて示す。

```nim
import std/[unittest, sequtils]
import propcheck

test "並べ替えても要素の数は変わらない":
  let outcome = check(seqOf(intIn(-100, 100), 0, 30),
    proc(xs: seq[int]): bool {.raises: [CatchableError].} = mySort(xs).len == xs.len)
  checkpoint describe(outcome)
  check outcome.passed
```

- 生成器は `intIn`・`boolean`・`pick`・`seqOf`・`stringOf` と、それを組む `map`・`pair`。自分で書くなら `drawUpTo` を使い、小さい引きが単純な値になるようにする。
- 縮小は、値ではなく、値を作るときの引きの列に対して行う。型ごとの縮小器は要らず、生成器が保証すること (偶数である、長さの範囲、など) は縮めた後も保たれる。
- 種は既定で固定 (0)。同じテストは毎回同じ入力で走り、失敗は再現する。
- 性質が例外を上げたら、それは反例である。
- `distinguish(gen, f, g)` は、二つの実装の結果が分かれる最小の入力を探す。

仕様と設計の理由は `docs/adr/ADR-PCK-0001-property-based-testing.md`。依存は標準ライブラリだけ。

```
make test            # 外部仕様テスト
make spec-coverage   # 仕様 ID ごとのテストの有無 (docs/quality/g1-spec-coverage.md)
```
