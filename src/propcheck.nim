## Property-based testing (ADR-PCK-0001).
##
## A generator makes a value from a sequence of draws. A property is
## checked against values made from a seed; when one breaks it, the draws
## behind that value are made shorter and smaller, the value is made
## again from them, and the smallest value that still breaks the property
## is reported. Because it is the draws that are shrunk, a generator needs
## no shrinker of its own, and whatever it guarantees of its values
## (evenness, an order, a length) holds for the shrunk value too.
##
## Every generator is written so that smaller draws make simpler values:
## an integer nearer 0, a shorter sequence, `false`.

import std/random

type
  Draws* = object
    ## The choices behind one value: drawn from a seed, or replayed.
    replaying: bool
    replayed: seq[uint64]
    rng: Rand
    used: seq[uint64]       ## what was drawn, as it was used

  Gen*[T] = proc(d: var Draws): T {.raises: [].}
    ## Makes a value from draws.

  Property*[T] = proc(x: T): bool {.raises: [CatchableError].}
    ## Holds (true) or not. Raising is not holding.

  CheckConfig* = object
    runs*: int          ## how many values the property is tried on
    seed*: int64        ## the same seed makes the same values
    maxShrinks*: int    ## how many times, at most, the property is tried again to shrink a counterexample

  Counterexample*[T] = object
    value*: T
    reason*: string         ## why it does not hold
    shrinks*: int           ## how many shrinking steps were taken
    draws*: seq[uint64]     ## `replay` makes `value` from these

  CheckResult*[T] = object
    passed*: bool
    runs*: int              ## values tried before stopping
    seed*: int64
    counterexample*: Counterexample[T]   ## meaningful when not `passed`

const DefaultConfig* = CheckConfig(runs: 100, seed: 0, maxShrinks: 2000)

# ─── draws ──────────────────────────────────────────────────────────────────

proc drawUpTo*(d: var Draws; most: uint64): uint64 {.raises: [].} =
  ## A draw from 0 to `most`, both included. For generators written by
  ## hand: make the smaller draw the simpler value.
  if d.replaying:
    let at = d.used.len
    # A replayed sequence that ran out, or that was cut where a larger
    # draw stood, gives the simplest draw that is allowed here.
    result = if at < d.replayed.len: min(d.replayed[at], most) else: 0
  elif most == high(uint64):
    result = d.rng.next()
  else:
    result = d.rng.next() mod (most + 1)
  d.used.add result

proc replay*[T](gen: Gen[T]; draws: seq[uint64]): T {.raises: [].} =
  ## The value `gen` makes from `draws`. From no draws: its simplest value.
  var d = Draws(replaying: true, replayed: draws)
  gen(d)

# ─── generators ─────────────────────────────────────────────────────────────

const smallOffsets = 15'u64   # a quarter of the integers are drawn this near the simplest one

proc intIn*(lo, hi: int): Gen[int] {.raises: [ValueError].} =
  ## An integer from `lo` to `hi`. The simplest is 0 when the range holds
  ## it, and otherwise the end nearest 0.
  if lo > hi: raise newException(ValueError, "the range " & $lo & " .. " & $hi & " is empty")
  let span = cast[uint64](hi) - cast[uint64](lo)    # the largest offset
  # Offsets count away from the simplest value: 0, +1, -1, +2, -2, ... while
  # both sides last, then on along the longer side.
  let above = if hi >= 0 and lo <= 0: cast[uint64](hi) else: 0'u64
  let below = if hi >= 0 and lo <= 0: 0'u64 - cast[uint64](lo) else: 0'u64
  let both = min(above, below)
  result = proc(d: var Draws): int {.raises: [].} =
    let offset =
      if d.drawUpTo(3) == 0: d.drawUpTo(min(span, smallOffsets))
      else: d.drawUpTo(span)
    if lo > 0: return cast[int](cast[uint64](lo) + offset)
    if hi < 0: return cast[int](cast[uint64](hi) - offset)
    if offset <= 2 * both and both <= high(uint64) div 2:
      let size = (offset + 1) div 2
      return if offset mod 2 == 1: cast[int](size) else: cast[int](0'u64 - size)
    let size = both + (offset - 2 * both)
    if above > below: cast[int](size) else: cast[int](0'u64 - size)

proc boolean*(): Gen[bool] {.raises: [].} =
  ## `false` is the simpler.
  proc(d: var Draws): bool {.raises: [].} = d.drawUpTo(1) == 1

proc pick*[T](values: openArray[T]): Gen[T] {.raises: [ValueError].} =
  ## One of `values`. The first is the simplest.
  if values.len == 0: raise newException(ValueError, "there is nothing to pick from")
  let choices = @values
  result = proc(d: var Draws): T {.raises: [].} = choices[d.drawUpTo(uint64(choices.len - 1)).int]

proc seqOf*[T](element: Gen[T]; minLen, maxLen: int): Gen[seq[T]] {.raises: [ValueError].} =
  ## A sequence of `minLen` to `maxLen` values of `element`. The shortest
  ## is the simplest.
  if minLen < 0 or minLen > maxLen:
    raise newException(ValueError, "lengths " & $minLen & " to " & $maxLen & " are not a range of lengths")
  result = proc(d: var Draws): seq[T] {.raises: [].} =
    # Before each element past the least, a draw says whether there is one
    # more: 0 ends the sequence, so cutting draws away shortens it.
    for i in 0 ..< maxLen:
      if i >= minLen and d.drawUpTo(7) == 0: break
      result.add element(d)

proc stringOf*(alphabet: string; minLen, maxLen: int): Gen[string] {.raises: [ValueError].} =
  ## A string of `minLen` to `maxLen` characters of `alphabet`. The
  ## shortest, of the first character, is the simplest.
  if alphabet.len == 0: raise newException(ValueError, "the alphabet has no character")
  var letters: seq[char]
  for c in alphabet: letters.add c
  let chars = seqOf(pick(letters), minLen, maxLen)
  result = proc(d: var Draws): string {.raises: [].} =
    for c in chars(d): result.add c

proc map*[A, B](gen: Gen[A]; change: proc(a: A): B {.raises: [].}): Gen[B] {.raises: [].} =
  ## The values of `gen`, each changed by `change`.
  proc(d: var Draws): B {.raises: [].} = change(gen(d))

proc pair*[A, B](first: Gen[A]; second: Gen[B]): Gen[(A, B)] {.raises: [].} =
  ## A value of each.
  proc(d: var Draws): (A, B) {.raises: [].} =
    let a = first(d)
    (a, second(d))

# ─── checking ───────────────────────────────────────────────────────────────

type Verdict[T] = proc(x: T): string {.raises: [].}   # "" when it holds, else why not

proc simpler(a, b: seq[uint64]): bool =
  ## Shorter, or as long and earlier in order.
  if a.len != b.len: return a.len < b.len
  for i in 0 ..< a.len:
    if a[i] != b[i]: return a[i] < b[i]
  false

proc checkBy[T](gen: Gen[T]; verdict: Verdict[T]; config: CheckConfig): CheckResult[T]
               {.raises: [ValueError].} =
  if config.runs < 1: raise newException(ValueError, "a check tries at least one value")
  if config.maxShrinks < 0: raise newException(ValueError, "the shrink budget cannot be below 0")
  result = CheckResult[T](passed: true, seed: config.seed)
  var d = Draws(rng: initRand(config.seed))
  for run in 1 .. config.runs:
    d.used.setLen(0)
    let value = gen(d)
    result.runs = run
    let reason = verdict(value)
    if reason.len == 0: continue

    # A counterexample. Make its draws simpler while it stays one.
    var best = Counterexample[T](value: value, reason: reason, draws: d.used)
    var tries = 0
    var improved = true
    proc attempt(candidate: seq[uint64]): bool =
      ## Whether `candidate` makes a simpler counterexample; then it is the
      ## best, and the search goes round once more.
      if tries >= config.maxShrinks: return false
      var replayed = Draws(replaying: true, replayed: candidate)
      let made = gen(replayed)
      if not simpler(replayed.used, best.draws): return false
      inc tries
      let why = verdict(made)
      if why.len == 0: return false
      best.value = made
      best.reason = why
      best.draws = replayed.used
      inc best.shrinks
      improved = true
      true

    while improved and tries < config.maxShrinks:
      improved = false
      # Cut runs of draws away: elements of a sequence, mostly.
      for size in [8, 6, 4, 3, 2, 1]:
        var at = best.draws.len - size
        while at >= 0:
          # `at + size` never passes the end: `at` starts `size` short of it,
          # only goes down, and is pulled back after a cut.
          if attempt(best.draws[0 ..< at] & best.draws[at + size .. ^1]):
            at = min(at, best.draws.len - size)
          else:
            dec at
      # Make single draws the simplest, then as small as they can be:
      # take the largest power of two away that leaves a counterexample.
      var at = 0
      while at < best.draws.len:
        if best.draws[at] != 0:
          var candidate = best.draws
          candidate[at] = 0
          if not attempt(candidate):
            for power in countdown(63, 0):
              let step = 1'u64 shl power
              if at < best.draws.len and best.draws[at] >= step:
                candidate = best.draws
                candidate[at] -= step
                # Whether it took is in `improved`; the next power is tried either way.
                discard attempt(candidate)
        inc at
    result.passed = false
    result.counterexample = best
    return

proc check*[T](gen: Gen[T]; property: Property[T]; config = DefaultConfig): CheckResult[T]
              {.raises: [ValueError].} =
  ## Tries `property` on `config.runs` values of `gen`. On the first that
  ## breaks it, shrinks that value and stops.
  let verdict: Verdict[T] = proc(x: T): string {.raises: [].} =
    try:
      if property(x): "" else: "the property is false"
    except CatchableError as e:
      # A property that raises does not hold; what it raised is the reason.
      "the property raised " & $e.name & ": " & e.msg
  checkBy(gen, verdict, config)

proc distinguish*[T, R](gen: Gen[T]; first, second: proc(x: T): R {.raises: [CatchableError].};
                        config = DefaultConfig): CheckResult[T] {.raises: [ValueError].} =
  ## Looks for a value on which `first` and `second` do different things.
  ## Raising is one of the things a function can do: two that raise the same
  ## error, with the same message, on a value do not differ on it. Passing
  ## means no such value was found.
  mixin `$`, `==`
  let verdict: Verdict[T] = proc(x: T): string {.raises: [].} =
    # What each raised, as "Type: message"; empty when it returned.
    var a, b: R
    var raisedA, raisedB = ""
    try:
      a = first(x)
    except CatchableError as e:
      raisedA = $e.name & ": " & e.msg
    try:
      b = second(x)
    except CatchableError as e:
      raisedB = $e.name & ": " & e.msg
    if raisedA.len == 0 and raisedB.len == 0:
      return if a == b: "" else: "the first gave " & $a & ", the second " & $b
    if raisedA == raisedB: return ""
    "the first " & (if raisedA.len > 0: "raised " & raisedA else: "gave " & $a) &
      ", the second " & (if raisedB.len > 0: "raised " & raisedB else: "gave " & $b)
  checkBy(gen, verdict, config)

proc describe*[T](outcome: CheckResult[T]): string {.raises: [].} =
  ## The result in words: for a failure, the counterexample, why, and how
  ## to make it again.
  mixin `$`
  if outcome.passed:
    return "held for " & $outcome.runs & " values (seed " & $outcome.seed & ")"
  "counterexample: " & $outcome.counterexample.value & "\n  " & outcome.counterexample.reason &
    "\n  found on value " & $outcome.runs & " of seed " & $outcome.seed & ", after " &
    $outcome.counterexample.shrinks & " shrinking steps"
