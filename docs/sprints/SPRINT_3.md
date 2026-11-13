# Sprint 3: StyleEngine

**Dates:** 30 Nov–6 Dec 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.4, §5.5, P0-9, P0-11, P0-13 (engine side)

## Goal

Given an occasion and a wardrobe, the engine returns outfits you would wear, proven by tests. No UI and no AI this sprint: everything runs as unit tests on the Mac.

## Needs from earlier sprints

- Taxonomy and `ItemTags` in the `StyleEngine` package (Sprints 1–2).
- `wardrobe.json` (the 42-item hand-made file).

## What must exist at the end

| Piece | Behaviour |
|---|---|
| Fixture | `wardrobe.json` converted to the PRD schema, loadable in tests |
| `OccasionIntent` | The engine's input type |
| Occasion table | Each occasion's dress codes, formality range and rules, as data |
| Colour table | Which colours go together, as data |
| Engine | `generate(intent, items, context) → [OutfitCandidate]` with reasons |
| Tests | 10 occasions with expected properties, all passing |

## Design

Everything is plain value types inside the package. The app converts SwiftData objects to `EngineItem` before calling.

```swift
struct EngineItem { let id: UUID; let tags: ItemTags; let colors: [ColorName]
                    let setGroupId: UUID?; let lastWornAt: Date? }

struct EngineContext { let today: Date
                       let excludeOutfits: Set<OutfitKey>   // already shown
                       let pairWeights: [PairKey: Double]    // from saved outfits, empty for now
                       let seed: UInt64 }

struct OutfitCandidate { let slots: [Slot: UUID]; let score: Double
                         let scoreParts: [String: Double] }  // for debugging

struct EngineResult { let outfits: [OutfitCandidate]
                      let rejected: [UUID: RejectReason]
                      let missing: [Slot] }                  // why nothing was built
```

`Slot`: top, baseLayer, bottom, onePiece, outerwear, footwear, accessory1, accessory2, plus set slots (setTop, setBottom, setDrape).

## Build steps

### 1. Fixture (1.5 h)
- `Tests/StyleEngineTests/Fixtures/wardrobe.json`: the 42 items mapped to `ItemTags`. Add the fields the original file lacks: `dressCodes`, `formality`, `seasons`, `warmth`, `statement`. Decide these by hand; they are your ground truth.
- Add three made-up items so set and gap logic can be tested: a kurta, matching pyjama (same `setGroupId`), and juttis.
- A second tiny fixture with no footwear, for the missing-slot test.

### 2. Intent and occasion table (1.5 h)
- `OccasionIntent` as in PRD §5.4.
- `OccasionRules`, one row per occasion, as a Swift dictionary literal (data, not `if` statements):

| Occasion | Dress codes | Formality | Boosts and rules |
|---|---|---|---|
| home | home, casual | 1–2 | |
| casualDay | casual, smartCasual | 1–3 | |
| office | smartCasual, businessCasual | 3–4 | no graphic, no slides |
| interview | businessCasual, formal | 4–5 | plain or subtle pattern only, closed-toe |
| date | smartCasual, party | 3–4 | boost fitted tops, dark bottoms |
| party | party, smartCasual | 2–4 | allow one statement piece |
| festival | festive, smartCasual | 3–4 | boost warm and earth colours, boost Indian and Indo-western |
| puja | festive, smartCasual | 3–4 | boost Indian, light colours; no graphic |
| weddingGuest | festive, formal | 4–5 | boost Indian sets; no denim |
| travel | casual | 1–3 | closed-toe if `lotsOfWalking` |
| gym | athletic | 1 | |

- Flags add rules on top: `fireworks` → closed-toe only, no slides or sandals; `religiousSite` → no shorts, no sleeveless; `lotsOfWalking` → no formal shoes, no slides.
- The intent's explicit `dressCode` and formality range override the table defaults when present.

### 3. Filter stage (1.5 h)
For each item, first failing check wins and is recorded:

| Reason | Fails when |
|---|---|
| `notReady` | status is not ready or tags are empty |
| `avoided` | colour or subcategory is in `intent.avoid` |
| `wrongDressCode` | no overlap between item dress codes and the occasion's |
| `formalityOutOfRange` | item formality outside range by more than 1 |
| `wrongSeason` / `tooWarm` | warmth 3 item in hot weather. Light (warmth 1) tops are kept in cold weather, but the cold formulas then require an overlayer or outerwear |
| `openToeBlocked` | flag requires closed-toe and item is open |
| `ruleBlocked` | an occasion rule (no graphic, no denim, no shorts) |
| `wornRecently` | worn in the last 2 days (soft: used only if enough other items remain) |

Items in `mustIncludeItemIds` skip every check.

### 4. Formulas (2 h)
- Candidate formulas, tried in this order when feasible:
  1. set + footwear (all items of one `setGroupId` fill their set slots together)
  2. top + bottom + footwear
  3. baseLayer + top (overlayer: open shirt, knit, zip polo) + bottom + footwear
  4. top + bottom + footwear + outerwear (cold or rainy only)
  5. onePiece + footwear
- A formula is feasible when every required slot has at least one surviving item.
- Accessories (belt, watch, chain) are added after scoring, at most two, only if formality matches.
- If no formula is feasible, return `missing` with the slots that had no candidates.

### 5. Seed, fill and hard checks (1.5 h)
- Seed: the pinned item if any; otherwise each of the top 5 tops or sets by occasion fit becomes a seed, giving up to 5 starting points.
- Fill each remaining slot with the best-scoring item against what is already chosen; keep the top 2 choices per slot to create variety (so about 5 × 2 × 2 candidates).
- Hard checks, candidate dropped if any fails:
  - more than one statement or non-solid piece (accessories excluded)
  - formality spread across items greater than 2
  - top and bottom the same non-neutral colour
  - warmth 3 item when `weatherFeel` is hot
  - the same outfit key is in `excludeOutfits`

### 6. Scoring (1.5 h)
Each part is 0–1; the score is the weighted sum. Weights live in one struct so they can be tuned in Sprint 6.

| Part | Weight | Meaning |
|---|---|---|
| occasionFit | 0.30 | average of how well each item's dress codes and formality match, plus occasion boosts |
| colourHarmony | 0.25 | from the colour table, averaged over item pairs |
| formalityMatch | 0.15 | 1 minus normalised formality spread |
| pairWeight | 0.15 | learned pairs from saved outfits; 0.5 when unknown |
| freshness | 0.10 | lower if any item was worn in the last 7 days |
| variety | 0.05 | small seeded random term so days differ |

Colour table (data): neutrals (black, white, cream, beige, grey, charcoal, navy, tan, brown) score 0.8 with anything and 0.9 with each other; listed good pairs score 1.0 (rust + black, rust + brown, olive + cream, navy + beige, lightBlue + navy, maroon + beige, mustard + navy); two different non-neutral accents score 0.3; listed clashes score 0.1.

### 7. Diversity and output (0.5 h)
- Sort by score. Walk down the list and keep a candidate only if it shares at most one non-footwear item with outfits already kept. Return the first N (default 3).
- `OutfitKey` is the sorted set of item ids; the caller passes shown keys back in `excludeOutfits` to get the next batch.

### 8. Tests (2 h)

**Tests first.** This sprint is fully test-driven: write the cases in [SPRINT_3_TESTS.md](SPRINT_3_TESTS.md) for each step before its code. That file has every filter, formula, set, hard-check and scoring case plus the scenarios below and the exit gate.
One test per row; each asserts properties, not exact outfits, so tuning weights does not break them.

| # | Intent | Must hold |
|---|---|---|
| 1 | festival, evening, indoor, mild | rust mandarin shirt with black chinos or brown linen trousers appears in the top 3 |
| 2 | same + `fireworks` | no open-toe footwear in any result |
| 3 | interview | light blue oxford present; bottoms are straight black chinos or similar; no graphic tee, no slides, no Sambas |
| 4 | casualDay, hot | no knitwear, no corduroy, no outerwear |
| 5 | date, evening, cold | a knit or an outerwear piece in every result |
| 6 | any occasion | never two patterned or statement pieces together (check shirt never with rugby polo) |
| 7 | festival, `preferIndian` | kurta and pyjama appear together as one outfit with juttis or sandals |
| 8 | any, no-footwear fixture | `outfits` empty and `missing` contains footwear |
| 9 | any, called twice with the first keys excluded | no outfit repeats |
| 10 | casualDay, `avoid: [jeans]` | no jeans; every rejected jeans item has reason `avoided` |
| 11 | pinned olive corduroy, cold | every result contains it |
| 12 | same intent, same seed, twice | identical results |

Also a speed test: 200 synthetic items, one call under 100 ms.

## Expected behaviour

- `swift test` in `Packages/StyleEngine` passes in under 2 seconds.
- For Diwali the engine reproduces what the chatbot suggested from the same wardrobe, without any AI.
- A debug print of any result shows each outfit's score parts and each rejected item's reason.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Zero outfits for a normal occasion | Filters too strict (dress code and formality both hard) | Allow formality ±1; treat `wornRecently` as soft; print the rejection counts per reason to see which one empties the pool |
| Same three items in every result | No diversity step, or one item dominates occasionFit | Apply the "share at most one item" rule; cap any single part's contribution |
| Black on black on black | Neutrals all score high together | Add a small penalty when every item is the same neutral; require one contrast (the original JSON notes this for the brown shirt + black chinos) |
| Kurta paired with jeans while its pyjama is ignored | Set treated as a normal top | Items with a `setGroupId` are only used through the set formula unless pinned |
| Navy knit with indigo jeans ranks first | Same-colour rule only checks identical names | Treat navy/indigo/blue denim as one family for the same-colour check |
| Results change between runs | Random term not seeded, or dictionary order used | Seed from `context.seed`; sort ids before iterating |
| A test fails after tuning weights | Test asserted an exact outfit | Rewrite it as a property |
| Engine needs SwiftData types | App model leaked into the package | Keep `EngineItem` as the only input; conversion lives in the app |
| Slow on large wardrobes | Trying every combination | Seeds × top-2 per slot keeps it small; never enumerate the full product |

## Checklist

- [ ] Fixture has all 42 items plus the kurta set, with usage tags filled by hand
- [ ] Occasion rules and colour pairs are data tables, not branches
- [ ] Every rejected item has a reason
- [ ] Sets come out as one unit
- [ ] `missing` is filled when nothing can be built
- [ ] Excluded outfits never return
- [ ] All 12 tests and the speed test pass
- [ ] Weights are in one struct
- [ ] Package has no import of SwiftUI, SwiftData or the app

## How it lands

- Branch `sprint-3`, merge to `main`, tag `sprint-3-done`.
- Demo: paste the debug output for the Diwali and interview intents into `docs/EVAL_ENGINE.md`.
- **Gate:** read the top 3 for all 10 occasions yourself. If fewer than 2 of 3 are wearable on more than two occasions, spend Sprint 4's first hours on the tables before any UI.

## Not this sprint

Intent parsing from text, any screen, pair-weight learning (the input exists but stays empty), weather lookup.
