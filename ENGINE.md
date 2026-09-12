# Headless engine branch

This branch prepares Path of Building to run as a **headless calculation engine**
for an external tool — an in-game overlay that answers "is this item an upgrade?"
by asking PoB, rather than reimplementing its damage and defence model.

It is an additive layer on top of upstream. Nothing here changes how the GUI
behaves; the intent is that this branch stays trivially rebasable onto upstream
`dev`.

## Why this branch patches upstream

Upstream `dev` does not currently parse. Fourteen pieces of syntax that are not
Lua had reached the branch:

| Construct | Example | Valid Lua |
| --- | --- | --- |
| Compound assignment | `count += 1` | `count = count + 1` |
| Compound concat | `prefix ..= "x"` | `prefix = prefix .. "x"` |
| Nullish coalescing | `a ?? {}` | `a or {}` |
| Optional chaining | `gem.gemData?.gameId` | `gem.gemData and gem.gemData.gameId` |
| Lambda arrow | `\|_, key\| -> expr` | `function(_, key) return expr end` |
| Bare `continue` | `continue` | `goto continue` + `::continue::` |

They span `Main.lua`, `Item.lua`, `ItemsTab.lua`, `Tooltip.lua`, `CalcOffence.lua`,
`CalcSetup.lua`, `PassiveTreeView.lua`, `BuildExportPoE2.lua` and
`Export/Scripts/uModsToText.lua`. With any of them present the program cannot be
parsed, so it never starts.

The same syntax also reached `spec/System/TestItemMods_spec.lua`, where it does
not stop the program but makes that spec error out instead of running. `spec/`
is therefore swept alongside `src/`.

Note that the codebase already uses the correct `goto continue` / `::continue::`
idiom in roughly sixty other places — the fixes here follow that existing idiom
rather than introducing a new one.

Release tags (`v0.22.0`, `v0.23.0`, `v0.23.1`) are unaffected and parse cleanly.
Only `dev` is broken.

The fixes are also exported as a standalone patch in
[`patches/0001-fix-non-lua-syntax.patch`](patches/0001-fix-non-lua-syntax.patch),
so they can be reapplied to a different checkout without this branch's history.

### Rewriting compound assignment needs care

`x += <expr>` means `x = x + (<expr>)`. Dropping those parentheses silently
changes the meaning whenever the right-hand side contains an operator that binds
more loosely than the arithmetic — `and`, `or`, and comparisons all do:

```lua
-- wrong: parses as (y + cond) and 24 or 0
y = y + self.controls.displayItemVersion:IsShown() and 24 or 0
-- right
y = y + (self.controls.displayItemVersion:IsShown() and 24 or 0)

-- wrong: parses as (life + tonumber(...)) or 0, which throws on a nil match
life = life + tonumber(modLine.line:match("%+(%d+) to maximum Life")) or 0
-- right
life = life + (tonumber(modLine.line:match("%+(%d+) to maximum Life")) or 0)
```

Three of the fourteen sites had a right-hand side like this. A find-and-replace
that does not parenthesise will produce code that compiles and is wrong, which is
worse than the original — so review every rewrite rather than trusting a regex.

## Verifying the tree

```sh
./tools/verify.sh           # parse sweep, headless boot, comparison smoke test
./tools/verify.sh --tests   # the above plus Path of Building's own busted suite
```

`verify.sh` exists because a rebase onto upstream can silently reintroduce the
syntax above. It fails loudly and names the offending file and line.

As of commit `768ae5a` this tree passes the full suite — 52 spec files, 872
assertions, no failures — alongside a clean parse of all 1122 Lua files. The
fixes in this branch are behaviour-preserving as far as Path of Building's own
tests can tell.

Requires `luajit` and the `lua-utf8` module; `--tests` also requires `busted`.
Upstream's test container (`ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`)
has all three.

## Running headless

```sh
cd src && LUA_PATH="../runtime/lua/?.lua;../runtime/lua/?/init.lua;./?.lua" \
	luajit ../poc/compare_poc.lua
```

- [`poc/compare_poc.lua`](poc/compare_poc.lua) — loads a build, parses a pasted
  item, and prints the stat deltas of equipping it.
- [`poc/bench.lua`](poc/bench.lua) — measures startup cost versus per-comparison
  cost, which is what makes a resident process the right shape.

## How the comparison works

PoB already computes this; it is what renders in item tooltips. The engine reuses
that path rather than a parallel one.

```lua
local calcFunc, calcBase = build.calcsTab:GetMiscCalculator()
local output = calcFunc({ repSlotName = slotName, repItem = item })
```

`calcFunc` evaluates a hypothetical item **without mutating the build**. Slot
selection comes from `ItemsTab:GetComparisonSlotNameForItem`, and the set of
stats worth reporting comes from `build.displayStats`, which already carries
per-stat comparison semantics (`compPercent`, `lowerIsBetter`).

Measured on this branch: roughly 3.7 s one-time startup, then ~5 ms per
comparison with the calculator reused.

## Things to know before building on this

- **PoB writes to stdout.** `ConPrintf` emits data-loading chatter and warnings.
  Anything speaking a protocol over stdout must redirect `ConPrintf` to stderr
  first, or the very first run will be corrupted.
- **Networking is stubbed headless.** `LaunchSubScript` is a no-op, so PoB's own
  character import cannot run. Fetch the character externally and hand the JSON
  to `loadBuildFromJSON`, or load a build XML with `loadBuildFromXML`.
- **Sprites are never read.** The image loader is a no-op that reports success
  without opening the file, so `TreeData` artwork and `Assets/` can be excluded
  when packaging an engine.
