> **Decision (write this line last, after the 14-day run):** _not decided yet._ Options (SPRINT_6.md step 9): plan the cross-platform build (wedding planner first) / one more sprint on tags and rules / stop and write down why.

# EVAL_MVP: measured numbers for the Wardrobe + AI Stylist prototype

Started 2026-11-22. Fill each section from the app, then paste. Nothing here is an estimate: leave a cell empty until it is measured.

## How to get each number

| Metric | Where |
|---|---|
| Edits per item, time to add, cut-out success, intent-to-results, running cost, personal use, outfit feedback | Settings → **MVP metrics** (copy or share the table, paste under "Measured" below) |
| Tag accuracy per field (strict) | The same screen, second table; also Settings → Accuracy |
| Outfit acceptance (E-ENG) | Settings → **Rate the engine**, round "Before tuning", then tune, then round "After tuning"; copy the table |
| E-TAG / E-COL on the 30 eval photos | Settings → Developer → Photo eval (bundled photos) |
| E-INT, E-NOTE | The Sprint 4 sentence list in `docs/EVAL_SPRINT4.md`, re-run on the phone |
| Wider garments | Add the 10–15 items, review each, then Settings → Accuracy; record per field below |

Limits to remember when reading the numbers:
- "Intent to results" is the logged intent call only; the engine's own time is not logged (it runs in milliseconds, S3-U37).
- Personal use counts days with an `intent` or `note` AI call. A day of chip-only use with the model off leaves no log row.
- Cut-out success counts `cutoutFailed` only; retakes are not recorded.
- Items added before 2026-11-22 have no ready time, so they are left out of "time to add".

## Measured (paste from Settings → MVP metrics)

_Not yet measured. Add the wardrobe first._

## Final evals (iPhone, real wardrobe)

| Eval | Pass mark | Result |
|---|---|---|
| E-TAG, 30 eval photos | TEST_PLAN §5; no drop over 5 points vs Sprint 0 | |
| E-TAG, real use (strict) | Same marks | |
| E-TAG, real use (lenient: near-synonyms right) | Same marks | |
| E-CUT | ≥ 90% clean | |
| E-COL | ≥ 90% | |
| E-SPEED | median ≤ 20 s | |
| E-INT | ≥ 13 of 15; ≥ 4 of 5 | |
| E-NOTE | 0 wrong notes shown; ≥ 24 pass validation | |
| E-ENG | ≥ 2 of 3 wearable on all 10 | |

## E-ENG rating sheet

### Before tuning
_Paste from Settings → Rate the engine (round: Before tuning)._

### Tuning log
One line per change: what was changed (table or weight), why (which reasons), and the Sprint 3 tests still passing.

| Change | Reason | Sprint 3 tests |
|---|---|---|
| | | |

### After tuning
_Paste from Settings → Rate the engine (round: After tuning)._

## Wider garment test (women's and Indian wear)

No pass mark: this is the baseline. Per field, did the AI's tag survive review (strict)?

| Item | category | subcategory | styleOrigin | pattern | fabric | fit | collar/neckline | dressCodes | Notes |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

## Duplicate check threshold

The match distance shown on the "Is this the same as…?" card is Vision's feature-print distance (lower is closer). Threshold today: `DuplicateCheck.threshold` = 0.45.

| Pair | Distance | Should match? | Result |
|---|---|---|---|
| Same shirt photographed twice | | yes | |
| Two pairs of black chinos | | no (or at least ask) | |
| Two different shirts, same colour | | no | |

Adjust the constant in `Packages/StyleEngine/Sources/StyleEngine/DuplicateCheck.swift` if the first row is above it or the others fall below.

## Weather

Today's weather uses Open-Meteo with a coarse (0.1°) location, once a day. Thresholds are in `WeatherFeelMapper` (rain ≥ 60%, feels-like max ≥ 32 °C hot, < 18 °C cold). Note any day it was wrong: date, weather, what the app picked.

| Date | Feels-like max | Rain | App picked | Right? |
|---|---|---|---|---|
| | | | | |
