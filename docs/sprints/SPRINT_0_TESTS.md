# Sprint 0 Tests: Proof

Sprint: [SPRINT_0.md](SPRINT_0.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

Sprint 0 is mostly an eval. The only logic worth test-driving is the **eval scorer**, because every later accuracy number depends on it being right. The scorer and `expected.json` are kept; the spike screens are throwaway.

## Write these tests first

### Unit tests (Mac)

| ID | Case | Given → Then |
|---|---|---|
| S0-U01 | Single-value field, correct | expected `mandarin`, got `mandarin` → scored 1 |
| S0-U02 | Single-value field, wrong | expected `mandarin`, got `spread` → scored 0 |
| S0-U03 | List field, first expected present | expected `[smartCasual, festive]`, got `[casual, smartCasual]` → scored 1 |
| S0-U04 | List field, first expected absent | expected `[smartCasual, festive]`, got `[festive]` → scored 0 |
| S0-U05 | Field missing from expected | expected has no `fabric` → fabric not counted in the total for that item |
| S0-U06 | Field missing from the answer | expected `linen`, got nil → scored 0 |
| S0-U07 | Accuracy maths | 27 right of 30 scored → 90.0% |
| S0-U08 | Zero scored items | no item has the field → reported as "n/a", no divide-by-zero |
| S0-U09 | Timing summary | durations 4, 6, 8, 30 → median 7, worst 30 |
| S0-U10 | `expected.json` decodes | every value is a valid case of its enum; a bad value fails with the item id and field named |
| S0-U11 | Photo and expected match | every photo has an expected entry and every entry has a photo; mismatches are listed |
| S0-U12 | Pass-mark check | given accuracies and the pass marks in TEST_PLAN §5 → returns which fields pass and which fail |

### Integration tests (iPhone only)

| ID | Case | Then |
|---|---|---|
| S0-I01 | Model availability | Returns available, or a specific reason; never crashes |
| S0-I02 | Cut-out on one known photo | Output is non-empty, has transparent pixels, and is smaller than the input frame |
| S0-I03 | One identity call on one cut-out | Returns a valid `category` case within 15 s |
| S0-I04 | Three calls in sequence on one item | A, B, C all return without a context-size error at the chosen image size |

## Evals to run and record

Write results to `docs/EVAL_SPRINT0.md`. Definitions and pass marks are in TEST_PLAN §5.

| Eval | Do | Record |
|---|---|---|
| E-TAG | Run all 30 photos through calls A, B, C | Accuracy per field; the list of wrong answers with photo id, expected, got |
| E-CUT | Look at all 30 cut-outs | Count of clean ones; ids of bad ones and why |
| E-SPEED | Timed inside the E-TAG run | Median and worst seconds per call and per item |
| E-DET | Tag 10 of the photos a second time | Number of items with any differing field |
| Image size | E-TAG at 512 px and at 1024 px long side | Accuracy and speed side by side; the size chosen |

Colour is **not** scored this sprint. It comes from code in Sprint 1 (E-COL).

**Result file layout**

```
Line 1: DECISION: on-device | on-device, fabric flagged | Gemini for tagging
Image size chosen: ___ px
Table: field | accuracy | pass mark | pass?
Table: timing
List: every wrong answer
Notes: simulator result, anything odd
```

## Manual test script (iPhone 17)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S0-M01 | Install and open the app | Opens without a crash; shows whether the model is available | ☐ |
| S0-M02 | Turn Apple Intelligence off in Settings, reopen | App says the model is unavailable and why; no crash | ☐ |
| S0-M03 | Turn it back on, reopen | Reports available | ☐ |
| S0-M04 | Open the cut-out screen, scroll all 30 | Each shows the original and the cut-out on white | ☐ |
| S0-M05 | Tap Run eval | Progress is visible; finishes; prints the summary | ☐ |
| S0-M06 | Tap Run eval again | Same accuracy numbers as the first run | ☐ |
| S0-M07 | Compare five rows of the printed table against the photos by eye | The "got" values are what the table says; the scorer marked them correctly | ☐ |

## Exit gate

- [ ] S0-U01 to U12 pass with `swift test` or the app test target
- [ ] S0-I01 to I04 pass on the phone
- [ ] All evals above recorded in `docs/EVAL_SPRINT0.md`
- [ ] Decision written on line 1, following the decision rule in SPRINT_0.md
- [ ] Manual steps M01 to M07 pass

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
