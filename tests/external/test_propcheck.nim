## External tests of propcheck (ADR-PCK-0001).

import std/[unittest, strutils, sequtils, sets]
import propcheck

proc simplest[T](gen: Gen[T]): T =
  ## The value a generator makes when every draw is the smallest.
  replay(gen, @[])

proc samples[T](gen: Gen[T]; count: int; seed = 0'i64): seq[T] =
  let found = check(gen, proc(x: T): bool {.raises: [CatchableError].} = true,
                    CheckConfig(runs: 1, seed: seed, maxShrinks: 0))
  doAssert found.passed
  var collected: seq[T]
  discard check(gen, proc(x: T): bool {.raises: [CatchableError].} =
                  collected.add x
                  true,
                CheckConfig(runs: count, seed: seed, maxShrinks: 0))
  collected

proc holds[T](x: T): bool {.raises: [CatchableError].} = true

suite "generators":
  # SPEC: GEN-01
  test "Given a range, When integers are generated, Then each is within it, and both ends and more than a few values come up":
    let values = samples(intIn(-3, 5), 400)
    check values.allIt(it >= -3 and it <= 5)
    check -3 in values
    check 5 in values
    check values.toHashSet.len == 9

  # SPEC: GEN-01
  test "Given ranges that hold 0, lie above it, or lie below it, When the simplest value is asked for, Then it is 0, or the end nearest 0":
    check simplest(intIn(-3, 5)) == 0
    check simplest(intIn(7, 20)) == 7
    check simplest(intIn(-20, -7)) == -7
    check simplest(intIn(4, 4)) == 4

  # SPEC: GEN-01
  test "Given the whole range of int, When generated, Then values of both signs come up and nothing overflows":
    let values = samples(intIn(low(int), high(int)), 200)
    check values.anyIt(it < 0)
    check values.anyIt(it > 0)

  # SPEC: GEN-01
  test "Given a range whose low end is above its high end, When the generator is made, Then it is refused":
    expect ValueError: discard intIn(5, 4)

  # SPEC: GEN-02
  test "Given lengths from 2 to 5, When sequences are generated, Then every length is within them and each comes up; the simplest is two simplest elements":
    let values = samples(seqOf(intIn(1, 9), 2, 5), 300)
    check values.allIt(it.len >= 2 and it.len <= 5)
    check values.mapIt(it.len).toHashSet == [2, 3, 4, 5].toHashSet
    check values.allIt(it.allIt(it >= 1 and it <= 9))
    check simplest(seqOf(intIn(1, 9), 2, 5)) == @[1, 1]
    check simplest(seqOf(intIn(1, 9), 0, 5)).len == 0

  # SPEC: GEN-02
  test "Given lengths out of order or below 0, When the generator is made, Then it is refused":
    expect ValueError: discard seqOf(intIn(0, 1), 3, 2)
    expect ValueError: discard seqOf(intIn(0, 1), -1, 2)

  # SPEC: GEN-03
  test "Given booleans, a choice among values and strings, When generated, Then each is of its kind, every choice comes up, and the simplest are false, the first value and the first letter":
    check samples(boolean(), 50).toHashSet == [false, true].toHashSet
    check simplest(boolean()) == false
    check samples(pick(["a", "b", "c"]), 100).toHashSet == ["a", "b", "c"].toHashSet
    check simplest(pick(["a", "b", "c"])) == "a"
    let words = samples(stringOf("xyz", 1, 4), 200)
    check words.allIt(it.len >= 1 and it.len <= 4 and it.allCharsInSet({'x', 'y', 'z'}))
    check simplest(stringOf("xyz", 2, 4)) == "xx"

  # SPEC: GEN-03
  test "Given nothing to choose among, or an alphabet of no letters, When the generator is made, Then it is refused":
    expect ValueError: discard pick(newSeq[int]())
    expect ValueError: discard stringOf("", 0, 3)

  # SPEC: GEN-04
  test "Given one seed twice, When generated, Then the values are the same; given another seed, Then they are others":
    let gen = seqOf(intIn(0, 1000), 0, 6)
    check samples(gen, 30, seed = 7) == samples(gen, 30, seed = 7)
    check samples(gen, 30, seed = 7) != samples(gen, 30, seed = 8)
    check samples(gen, 30) == samples(gen, 30, seed = 0)

  # SPEC: GEN-05
  test "Given a generator mapped to doubles, and a pair of two generators, When generated, Then every value is a double, and each pair holds one of each":
    check samples(intIn(0, 50).map(proc(x: int): int {.raises: [].} = x * 2), 100).allIt(it mod 2 == 0)
    let pairs = samples(pair(intIn(1, 3), pick(["p", "q"])), 100)
    check pairs.allIt(it[0] in 1 .. 3 and it[1] in ["p", "q"])
    check simplest(pair(intIn(1, 3), pick(["p", "q"]))) == (1, "p")

suite "running a property":
  # SPEC: RUN-01
  test "Given a property that holds for every input, When checked 250 times, Then it passes and 250 inputs were tried":
    let outcome = check(intIn(0, 9), proc(x: int): bool {.raises: [CatchableError].} = x < 10,
                        CheckConfig(runs: 250, seed: 0, maxShrinks: 100))
    check outcome.passed
    check outcome.runs == 250

  # SPEC: RUN-02
  test "Given a property some input breaks, When checked, Then it fails and the counterexample breaks the property":
    let outcome = check(intIn(0, 1000), proc(x: int): bool {.raises: [CatchableError].} = x mod 7 != 3)
    check not outcome.passed
    check outcome.counterexample.value mod 7 == 3

  # SPEC: RUN-03
  test "Given a property that raises for some input, When checked, Then it fails, and the counterexample carries what was raised":
    let outcome = check(intIn(0, 100), proc(x: int): bool {.raises: [CatchableError].} =
      if x >= 40: raise newException(ValueError, "too large: forty or more")
      true)
    check not outcome.passed
    check outcome.counterexample.value == 40
    check "too large: forty or more" in outcome.counterexample.reason
    check "ValueError" in outcome.counterexample.reason

  # SPEC: RUN-04
  test "Given no run, or a shrink budget below 0, When checked, Then it is refused":
    expect ValueError: discard check(intIn(0, 1), holds[int], CheckConfig(runs: 0, seed: 0, maxShrinks: 10))
    expect ValueError: discard check(intIn(0, 1), holds[int], CheckConfig(runs: 10, seed: 0, maxShrinks: -1))

suite "shrinking":
  # SPEC: SHR-01
  test "Given 'every integer is under 100', When it fails, Then the counterexample is 100":
    let outcome = check(intIn(0, 1_000_000), proc(x: int): bool {.raises: [CatchableError].} = x < 100)
    check not outcome.passed
    check outcome.counterexample.value == 100

  # SPEC: SHR-01
  test "Given 'no integer is under -100', over a range on both sides of 0, When it fails, Then the counterexample is -101":
    let outcome = check(intIn(-1_000_000, 1_000_000), proc(x: int): bool {.raises: [CatchableError].} = x >= -100)
    check outcome.counterexample.value == -101

  # SPEC: SHR-01
  test "Given 'no element is 10 or more', When it fails, Then the counterexample is the one element 10":
    let outcome = check(seqOf(intIn(0, 1000), 0, 20),
                        proc(xs: seq[int]): bool {.raises: [CatchableError].} = xs.allIt(it < 10))
    check not outcome.passed
    check outcome.counterexample.value == @[10]

  # SPEC: SHR-01
  test "Given 'every sequence is shorter than 3', When it fails, Then the counterexample is three simplest elements":
    let outcome = check(seqOf(intIn(-50, 50), 0, 20),
                        proc(xs: seq[int]): bool {.raises: [CatchableError].} = xs.len < 3)
    check outcome.counterexample.value == @[0, 0, 0]

  # SPEC: SHR-05
  test "Given 'the sum stays under 50', When it fails, Then the counterexample sums to exactly 50, and no element of it can be left out":
    let outcome = check(seqOf(intIn(0, 30), 0, 10),
                        proc(xs: seq[int]): bool {.raises: [CatchableError].} = xs.foldl(a + b, 0) < 50)
    let found = outcome.counterexample.value
    check found.foldl(a + b, 0) == 50
    check found.allIt(it > 0)       # leaving any one out brings the sum under 50

  # SPEC: SHR-02
  test "Given a failure, When its draws are replayed through the generator, Then the counterexample comes back, and it breaks the property":
    let gen = seqOf(intIn(0, 1000), 0, 20)
    proc noPairSumsTo(xs: seq[int]): bool {.raises: [CatchableError].} =
      for i in 0 ..< xs.len:
        for j in i + 1 ..< xs.len:
          if xs[i] + xs[j] == 17: return false
      true
    let outcome = check(gen, noPairSumsTo)
    check not outcome.passed
    check replay(gen, outcome.counterexample.draws) == outcome.counterexample.value
    check not noPairSumsTo(outcome.counterexample.value)
    check outcome.counterexample.value.len == 2
    check outcome.counterexample.shrinks > 0

  # SPEC: SHR-03
  test "Given a generator of even numbers and 'under 100', When it fails, Then the counterexample is even: 100, never 99":
    let evens = intIn(0, 1000).map(proc(x: int): int {.raises: [].} = x * 2)
    let outcome = check(evens, proc(x: int): bool {.raises: [CatchableError].} = x < 100)
    check outcome.counterexample.value == 100
    let odd = check(evens, proc(x: int): bool {.raises: [CatchableError].} = x < 101)
    check odd.counterexample.value == 102

  # SPEC: SHR-04
  test "Given a shrink budget of 0, When it fails, Then the first counterexample found is returned as it is; given a budget of 5, Then no more than 5 are tried":
    let property = proc(x: int): bool {.raises: [CatchableError].} = x < 100
    let unshrunk = check(intIn(0, 1_000_000), property, CheckConfig(runs: 100, seed: 0, maxShrinks: 0))
    check not unshrunk.passed
    check unshrunk.counterexample.shrinks == 0
    check unshrunk.counterexample.value >= 100
    var tried = 0
    let counted = check(seqOf(intIn(0, 1_000_000), 0, 20), proc(xs: seq[int]): bool {.raises: [CatchableError].} =
                          inc tried
                          false,                       # the first value is a counterexample
                        CheckConfig(runs: 1, seed: 0, maxShrinks: 5))
    check not counted.passed
    check tried <= 1 + 5

suite "reporting, and telling two implementations apart":
  # SPEC: RPT-01
  test "Given a failed and a passed result, When described, Then the first names the value, the reason, the seed and the shrinks, and the second the runs":
    let failed = check(intIn(0, 1000), proc(x: int): bool {.raises: [CatchableError].} =
                         if x >= 5: raise newException(ValueError, "five")
                         true,
                       CheckConfig(runs: 100, seed: 3, maxShrinks: 500))
    let text = describe(failed)
    check "5" in text
    check "five" in text
    check "seed 3" in text
    check "shrink" in text
    let passed = check(intIn(0, 9), holds[int], CheckConfig(runs: 20, seed: 0, maxShrinks: 0))
    check "20" in describe(passed)

  # SPEC: DIF-01
  test "Given two ways of taking a half that part only for negative odd numbers, When told apart, Then the input is -1; given two that never part, Then it passes":
    proc shifted(x: int): int {.raises: [CatchableError].} = x shr 1      # rounds down
    proc divided(x: int): int {.raises: [CatchableError].} = x div 2      # rounds towards 0
    let outcome = distinguish(intIn(-1000, 1000), shifted, divided)
    check not outcome.passed
    check outcome.counterexample.value == -1
    check "-1" in outcome.counterexample.reason      # what each gave
    check distinguish(intIn(0, 1000), shifted, divided).passed

  # SPEC: DIF-02
  test "Given two functions that raise the same error on the same inputs, When told apart, Then it passes":
    proc checked(x: int): int {.raises: [CatchableError].} =
      if x < 0: raise newException(ValueError, "negative")
      x * 2
    proc extracted(x: int): int {.raises: [CatchableError].} =
      if x < 0: raise newException(ValueError, "negative")
      x + x
    check distinguish(intIn(-1000, 1000), checked, extracted).passed

  # SPEC: DIF-02
  test "Given one function that raises where the other returns, When told apart, Then the smallest such input is the counterexample and the reason names what each did":
    proc checked(x: int): int {.raises: [CatchableError].} =
      if x >= 5: raise newException(ValueError, "five or more")
      x
    proc unchecked(x: int): int {.raises: [CatchableError].} = x
    let outcome = distinguish(intIn(0, 1000), checked, unchecked)
    check not outcome.passed
    check outcome.counterexample.value == 5
    check "ValueError" in outcome.counterexample.reason
    check "five or more" in outcome.counterexample.reason
    check "gave 5" in outcome.counterexample.reason
    let swapped = distinguish(intIn(0, 1000), unchecked, checked)
    check swapped.counterexample.value == 5
    check "five or more" in swapped.counterexample.reason
    check "the first gave 5" in swapped.counterexample.reason

  # SPEC: DIF-02
  test "Given two functions that raise errors of another type or with another message, When told apart, Then they differ":
    proc valueError(x: int): int {.raises: [CatchableError].} =
      raise newException(ValueError, "bad")
    proc keyError(x: int): int {.raises: [CatchableError].} =
      raise newException(KeyError, "bad")
    proc otherMessage(x: int): int {.raises: [CatchableError].} =
      raise newException(ValueError, "worse")
    let byType = distinguish(intIn(0, 9), valueError, keyError)
    check not byType.passed
    check "ValueError" in byType.counterexample.reason
    check "KeyError" in byType.counterexample.reason
    let byMessage = distinguish(intIn(0, 9), valueError, otherMessage)
    check not byMessage.passed
    check "bad" in byMessage.counterexample.reason
    check "worse" in byMessage.counterexample.reason

suite "what the first mutation run left standing (2026-10-12)":
  proc drawn(most: uint64): Gen[int] =
    ## One draw, as it is: the smallest generator there is.
    proc(d: var Draws): int {.raises: [].} = int(d.drawUpTo(most))

  proc untilZero(): Gen[seq[int]] =
    ## Up to five draws of 1..20, ended by a draw of 0: one draw an element.
    proc(d: var Draws): seq[int] {.raises: [].} =
      for i in 0 ..< 5:
        let v = int(d.drawUpTo(20))
        if v == 0: break
        result.add v

  # SPEC: GEN-01
  test "Given ranges that lie below 0, or reach further on one side of it, When values are made, Then every one is in the range":
    for (lo, hi) in [(-20, -5), (-10, 3), (-3, 10), (-1000, -999)]:
      for x in samples(intIn(lo, hi), 400):
        check x >= lo
        check x <= hi

  # SPEC: GEN-01
  test "Given every integer there is, When the simplest is asked for, Then it is 0":
    check simplest(intIn(low(int), high(int))) == 0
    check simplest(intIn(low(int) + 1, high(int))) == 0

  # SPEC: GEN-02
  test "Given the least and the most lengths are the same, When sequences are made, Then each has that length":
    for s in samples(seqOf(intIn(0, 9), 3, 3), 50):
      check s.len == 3

  # SPEC: GEN-03
  test "Given an alphabet of one character, When strings are made, Then they are of that character":
    check simplest(stringOf("a", 2, 2)) == "aa"

  # SPEC: SHR-02
  test "Given a counterexample found after other values and no shrinking, When its draws are replayed, Then they make that value":
    for seed in 0'i64 ..< 20:
      let outcome = check(intIn(0, 1000), proc(x: int): bool {.raises: [CatchableError].} = x < 900,
                          CheckConfig(runs: 200, seed: seed, maxShrinks: 0))
      if not outcome.passed and outcome.runs > 1:
        check replay(intIn(0, 1000), outcome.counterexample.draws) == outcome.counterexample.value

  # SPEC: SHR-05
  test "Given a value of two draws of which only the second matters, When shrunk, Then the first draw is the simplest too":
    var firstWasNotSimplest = 0
    for seed in 0'i64 ..< 20:
      let outcome = check(pair(drawn(1), drawn(1000)),
                          proc(x: (int, int)): bool {.raises: [CatchableError].} = x[1] < 10,
                          CheckConfig(runs: 100, seed: seed, maxShrinks: 2000))
      check not outcome.passed
      check outcome.counterexample.value == (0, 10)
      let unshrunk = check(pair(drawn(1), drawn(1000)),
                           proc(x: (int, int)): bool {.raises: [CatchableError].} = x[1] < 10,
                           CheckConfig(runs: 100, seed: seed, maxShrinks: 0))
      if unshrunk.counterexample.value[0] == 1: inc firstWasNotSimplest
    check firstWasNotSimplest > 0      # or the loop above showed nothing

  # SPEC: SHR-05
  test "Given a list whose offending element is not the first, When shrunk, Then the elements before it are taken away":
    var offenderWasNotFirst = 0
    for seed in 0'i64 ..< 40:
      let property = proc(s: seq[int]): bool {.raises: [CatchableError].} = 7 notin s
      let outcome = check(untilZero(), property, CheckConfig(runs: 300, seed: seed, maxShrinks: 2000))
      if outcome.passed: continue
      check outcome.counterexample.value == @[7]
      let unshrunk = check(untilZero(), property, CheckConfig(runs: 300, seed: seed, maxShrinks: 0))
      if unshrunk.counterexample.value.len > 1 and unshrunk.counterexample.value[0] != 7:
        inc offenderWasNotFirst
    check offenderWasNotFirst > 0

  # SPEC: SHR-05
  test "Given a counterexample from which an element can go only after the values are made small, When shrunk, Then it goes":
    # [a, b] breaks the property while a > b; [0] breaks it too, and nothing
    # else of one element does. So [a, b] must first become [1, 0], and only
    # then can its first element be taken away.
    let property = proc(s: seq[int]): bool {.raises: [CatchableError].} =
      not ((s.len == 2 and s[0] > s[1]) or s == @[0])
    var reached = 0
    for seed in 0'i64 ..< 40:
      let outcome = check(seqOf(intIn(0, 50), 0, 2), property,
                          CheckConfig(runs: 300, seed: seed, maxShrinks: 5000))
      if outcome.passed: continue
      check outcome.counterexample.value == @[0]
      let unshrunk = check(seqOf(intIn(0, 50), 0, 2), property,
                           CheckConfig(runs: 300, seed: seed, maxShrinks: 0))
      if unshrunk.counterexample.value.len == 2: inc reached
    check reached > 0

  # SPEC: SHR-05
  test "Given a list from which the first element can go only once the second is as small as it gets, When shrunk, Then the search goes round again and takes it away":
    # [a, b] breaks the property while a > b, and so does [1]; no other list
    # of one element does. From [a, b] with b above 1 nothing can be cut:
    # first b has to come down to 1, and only then does [1] remain after a cut.
    let property = proc(s: seq[int]): bool {.raises: [CatchableError].} =
      not ((s.len == 2 and s[0] > s[1]) or s == @[1])
    var neededAnotherRound = 0
    for seed in 0'i64 ..< 40:
      let outcome = check(untilZero(), property, CheckConfig(runs: 300, seed: seed, maxShrinks: 5000))
      if outcome.passed: continue
      check outcome.counterexample.value == @[1]
      let unshrunk = check(untilZero(), property, CheckConfig(runs: 300, seed: seed, maxShrinks: 0))
      if unshrunk.counterexample.value.len == 2 and unshrunk.counterexample.value[1] > 1:
        inc neededAnotherRound
    check neededAnotherRound > 0

