# Sprint 3 Tests: StyleEngine

Sprint: [SPRINT_3.md](SPRINT_3.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

This sprint is the purest test-driven work in the plan: the engine has no UI and no AI, so every behaviour is a unit test written first. All tests run with `swift test --package-path Packages/StyleEngine` in under 2 seconds.

Tests assert **properties** ("no open-toe footwear"), not exact outfits, so tuning weights later does not break them.

Order of work: fixture and table tests → filter tests → formula tests → set tests → hard-check tests → scoring and output tests → scenario tests.

## Unit tests

### Fixture and tables (build steps 1, 2)

| ID | Case | Then |
|---|---|---|
| S3-U01 | Fixture loads | 45 items (42 + kurta, pyjama, juttis); ids unique |
| S3-U02 | Fixture is complete | Every item has category, subcategory, at least one colour, at least one dress code, formality 1–5, at least one season |
| S3-U03 | Occasion table complete | Every `occasion` case has a rules row with dress codes and a formality range where min ≤ max |
| S3-U04 | Colour table symmetric | score(a, b) equals score(b, a) for every pair; every score is 0–1 |
| S3-U05 | Weights | The six weights sum to 1.0 |

### Filter stage (build step 3)

One test per reason. Each builds a tiny wardrobe where exactly one item should be rejected, and checks the reason.

| ID | Reason | Given → Then |
|---|---|---|
| S3-U06 | `notReady` | item with empty tags → rejected `notReady` |
| S3-U07 | `avoided` (colour) | avoid black → black items rejected `avoided` |
| S3-U08 | `avoided` (subcategory) | avoid jeans → jeans rejected, chinos kept |
| S3-U09 | `wrongDressCode` | interview → graphic tee (casual only) rejected |
| S3-U10 | `formalityOutOfRange` | range 4–5 → formality 3 kept (±1), formality 2 rejected |
| S3-U11 | `tooWarm` | hot → warmth 3 knit rejected |
| S3-U12 | `openToeBlocked` | `fireworks` flag → sandals and slides rejected, sneakers kept |
| S3-U13 | `ruleBlocked` | office → graphic tee and slides rejected by the occasion rule |
| S3-U14 | `wornRecently` is soft | top worn yesterday is rejected when other tops exist, kept when it is the only top |
| S3-U15 | Pinned skips filters | pinned item that fails dress code is still kept |

### Formulas (build step 4)

| ID | Case | Then |
|---|---|---|
| S3-U16 | Basic formula | top + bottom + footwear is feasible with one of each |
| S3-U17 | Outerwear only when cold | mild → no outerwear slot; cold → outerwear formula offered |
| S3-U18 | Layered formula | base tee + overlayer + bottom + footwear appears when an overlayer survives |
| S3-U19 | One-piece | onePiece + footwear, with no top or bottom |
| S3-U20 | Nothing feasible | no footwear → `outfits` empty, `missing` contains footwear |
| S3-U21 | Accessories | at most 2; none whose formality is more than 1 from the outfit's |

### Sets (build step 4)

| ID | Case | Then |
|---|---|---|
| S3-U22 | Set is one unit | kurta and pyjama share a `setGroupId` → they always appear together |
| S3-U23 | Set item not used alone | the kurta never appears with jeans or chinos |
| S3-U24 | Pinned set item brings its set | pin the kurta → pyjama is in the same outfit |

### Hard checks (build step 5)

| ID | Case | Then |
|---|---|---|
| S3-U25 | One pattern only | check shirt never with the striped rugby polo or a graphic tee as a layer |
| S3-U26 | Formality spread | no outfit with items more than 2 formality levels apart |
| S3-U27 | Same colour, top and bottom | no rust top with rust bottom; navy knit with indigo jeans is rejected (same family) |
| S3-U28 | Heat | hot → no warmth 3 item in any outfit |
| S3-U29 | All one neutral | black top + black bottom + black shoes scores lower than the same outfit with white sneakers |

### Scoring and output (build steps 6, 7)

| ID | Case | Then |
|---|---|---|
| S3-U30 | Exclusion | call twice, passing the first result's keys → no outfit repeats |
| S3-U31 | Diversity | within one result, no two outfits share more than one non-footwear item |
| S3-U32 | Deterministic | same intent, items, seed → identical results, twice |
| S3-U33 | Score parts in range | every part is 0–1; total equals the weighted sum |
| S3-U34 | Pair weight has effect | two otherwise equal outfits; the one whose pair has weight 0.9 ranks above the one at 0.5 |
| S3-U35 | Freshness has effect | an outfit whose top was worn 3 days ago ranks below an equal one never worn |
| S3-U36 | Outfit key | key is the same whatever the order of items |
| S3-U37 | Speed | 200 synthetic items, one call under 100 ms |
| S3-U38 | Every rejected item has a reason | count of kept + rejected equals input count |

## Scenario tests (whole engine on the fixture)

| ID | Intent | Must hold |
|---|---|---|
| S3-SC01 | festival, evening, indoor, mild | rust mandarin shirt with black chinos or brown linen trousers is in the top 3 |
| S3-SC02 | SC01 + `fireworks` | no open-toe footwear in any result |
| S3-SC03 | interview | light blue oxford present; no graphic tee, slides or Sambas in any result |
| S3-SC04 | casualDay, hot | no knitwear, corduroy or outerwear |
| S3-SC05 | date, evening, cold | every result has a knit or an outerwear piece |
| S3-SC06 | office | every result is smart casual or above; no graphic, no slides |
| S3-SC07 | festival, `preferIndian` | kurta + pyjama with juttis or sandals is in the top 3 |
| S3-SC08 | any, no-footwear fixture | empty result, `missing` has footwear |
| S3-SC09 | casualDay, avoid jeans | no jeans; each jeans item's reason is `avoided` |
| S3-SC10 | cold, pinned olive corduroy | every result contains it |
| S3-SC11 | home | formality 1–2 only; slides allowed |
| S3-SC12 | party | at most one statement piece; none of the outfits is all one neutral |

## Integration tests (app target)

| ID | Case | Then |
|---|---|---|
| S3-I01 | Store item → `EngineItem` | Conversion uses merged tags: an override changes what the engine sees |
| S3-I02 | Archived and failed items | Not passed to the engine |
| S3-I03 | Engine has no app dependency | The package builds and tests on its own, importing no SwiftUI, SwiftData or app code |

## Eval to run and record

| Eval | Do | Pass mark |
|---|---|---|
| E-ENG (fixture) | Print the top 3 for the 10 rating occasions listed in [SPRINT_6_TESTS.md](SPRINT_6_TESTS.md), with score parts. Paste into `docs/EVAL_ENGINE.md`. Mark each outfit wear / wouldn't wear with a one-word reason | ≥ 2 of 3 wearable on at least 8 of 10 occasions now; all 10 by Sprint 6 |

This is the Sprint 3 gate: below the mark, Sprint 4 starts with table fixes.

## Manual check

There is no app screen this sprint. The manual work is reading output.

| Step | Do | Expected | Pass |
|---|---|---|---|
| S3-M01 | Run `swift test` | All pass, under 2 seconds | ☐ |
| S3-M02 | Read the Diwali output | Matches what you would pick; the rust shirt outfit is there | ☐ |
| S3-M03 | Read the rejection list for the interview intent | Each rejected item's reason makes sense to you | ☐ |
| S3-M04 | Read all 10 occasions and rate them | Rating sheet filled in `docs/EVAL_ENGINE.md` | ☐ |
| S3-M05 | Change one colour-pair score in the table, re-run | Tests still pass; ranking changes as expected. Revert | ☐ |

## Exit gate

- [ ] S3-U01 to U38 pass
- [ ] S3-SC01 to SC12 pass
- [ ] S3-I01 to I03 pass
- [ ] Sprints 0–2 tests still pass
- [ ] E-ENG recorded; gate decision written in `docs/EVAL_ENGINE.md`
- [ ] Manual steps M01 to M05 done

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
