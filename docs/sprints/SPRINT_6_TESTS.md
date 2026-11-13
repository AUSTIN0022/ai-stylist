# Sprint 6 Tests: Own use and fixes

Sprint: [SPRINT_6.md](SPRINT_6.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

This sprint has little new code, so most of the testing is: run everything again, run every eval one last time on the real wardrobe, and walk through the whole app by hand.

## Unit tests for the two small additions (Mac)

### Duplicate check (work item 5)

The image feature print needs a device, so the decision logic is tested with made-up distances.

| ID | Case | Given → Then |
|---|---|---|
| S6-U01 | Match | distance under the threshold → "possible duplicate" with the matching item |
| S6-U02 | No match | distance over the threshold → no prompt |
| S6-U03 | Same subcategory only | a very close print on a different subcategory → no prompt |
| S6-U04 | Closest wins | two candidates under the threshold → the nearer one is offered |
| S6-U05 | Items without a print | older items with no stored print are skipped without error |

### Weather (work item 6)

Network is stubbed; no real request in tests.

| ID | Case | Given → Then |
|---|---|---|
| S6-U06 | Mapping | feels-like max 36 °C → hot; 24 °C → mild; 12 °C → cold; rain chance 70% → rainy (rain wins) |
| S6-U07 | Failure is quiet | request fails or times out → `unknown`; no error surfaced |
| S6-U08 | Location denied | → `unknown`; no request made |
| S6-U09 | Cached for the day | two calls on the same date → one request; next day → a new request |
| S6-U10 | User's words win | weather says hot, message says "it's cold in the office" → cold |

## Integration tests

| ID | Where | Case | Then |
|---|---|---|---|
| S6-I01 | Mac | Duplicate flow with fake prints | Adding a near-identical item raises the prompt; "Same" keeps one item; "Different" keeps both |
| S6-I02 | Mac | Weather fills the default | Stubbed hot day, message with no weather → intent has hot; the chip shows it |
| S6-I03 | iPhone | Real feature prints | The same shirt photographed twice matches; two different shirts of the same colour do not |
| S6-I04 | Mac | Metrics script | On a seeded store with known overrides, the accuracy and edits-per-item numbers come out as expected |

## Regression: fixes from daily use

For each of the top five problems you fix (work item 4), where it is in testable logic:

| # | Problem (from `DOGFOOD_NOTES.md`) | Failing test written first (ID) | Fixed |
|---|---|---|---|
| 1 | | S6-R01 | ☐ |
| 2 | | S6-R02 | ☐ |
| 3 | | S6-R03 | ☐ |
| 4 | | S6-R04 | ☐ |
| 5 | | S6-R05 | ☐ |

## Full regression run

- [ ] `swift test` on the package: all Sprint 3, 4 and 5 engine tests pass
- [ ] `xcodebuild test`: all app unit, integration and UI smoke tests from Sprints 0–5 pass
- [ ] After each tuning change in work item 3, the Sprint 3 scenario tests (S3-SC01 to SC12) pass

## Final evals (iPhone, real wardrobe)

Write everything to `docs/EVAL_MVP.md`. This is the last recorded run of each eval.

| Eval | Data this time | Pass mark | Result |
|---|---|---|---|
| E-TAG | The 30 eval photos, for comparison with Sprints 0 and 2 | TEST_PLAN §5 marks; no drop over 5 points | |
| E-TAG (real use) | Whole wardrobe: a field with a user override counts as wrong | Same marks; report strict and lenient (near-synonyms such as cotton vs cottonLinen counted right) | |
| E-CUT | Whole wardrobe: items with `cutoutFailed` or a retake | ≥ 90% clean | |
| E-COL | The 30 eval photos | ≥ 90% | |
| E-SPEED | Whole wardrobe, from stored timestamps and the AI log | median ≤ 20 s | |
| E-INT | Same 15 sentences and 5 follow-ups as Sprint 4 | ≥ 13 of 15; ≥ 4 of 5 | |
| E-NOTE | 10 requests, 30 notes | 0 wrong notes shown; ≥ 24 pass validation | |
| E-ENG | Rating sheet below, before and after tuning | ≥ 2 of 3 wearable on all 10 | |
| Wider garments | 10–15 women's and Indian items | No pass mark; record accuracy per field as the baseline | |

### E-ENG rating sheet

Same 10 occasions used in Sprint 3. Rate the top 3 for each: W = would wear, N = wouldn't, with a one-word reason for each N.

| # | Request | Outfit 1 | Outfit 2 | Outfit 3 | Wearable | Pass (≥ 2) |
|---|---|---|---|---|---|---|
| 1 | Office, normal day | | | | /3 | ☐ |
| 2 | Interview | | | | /3 | ☐ |
| 3 | Date night | | | | /3 | ☐ |
| 4 | House party | | | | /3 | ☐ |
| 5 | Diwali at a friend's, evening, indoors | | | | /3 | ☐ |
| 6 | Wedding guest | | | | /3 | ☐ |
| 7 | Temple visit | | | | /3 | ☐ |
| 8 | Travel day | | | | /3 | ☐ |
| 9 | Casual weekend, hot | | | | /3 | ☐ |
| 10 | Evening out, cold | | | | /3 | ☐ |

Fill it once before tuning and once after. Keep both.

## Full manual acceptance (iPhone 17)

One pass through every P0 requirement on a clean install. Start by exporting your data, deleting the app and reinstalling.

| Step | Requirement | Do | Expected | Pass |
|---|---|---|---|---|
| A01 | P0-17 | Open with Apple Intelligence off | Clear explanation; app usable | ☐ |
| A02 | P0-1 | Add 5 items from the camera and 5 from Photos | 10 items added | ☐ |
| A03 | P0-2 | Include one dark photo | Flagged with the reason | ☐ |
| A04 | P0-3 | Look at the grid | Clean white-background cut-outs | ☐ |
| A05 | P0-4 | Open three items | Colour swatches match the clothes | ☐ |
| A06 | P0-5 | Wait for tagging | All 10 named and categorised | ☐ |
| A07 | P0-6, P0-7 | Correct two tags; re-tag one of those items | Corrections kept | ☐ |
| A08 | P0-8 | Filter by category, colour and dress code; search by name | Correct results | ☐ |
| A09 | P0-9 | Link a set; ask for a festival outfit | Set suggested together | ☐ |
| A10 | P0-10 | Type three different occasions | Chips match what you meant | ☐ |
| A11 | P0-11, P0-12 | Read the cards and notes | Complete, sensible, well laid out | ☐ |
| A12 | P0-13 | Another option twice; swap one piece | No repeats; only that piece changes | ☐ |
| A13 | P0-14 | Save two outfits; restart | Both on the Outfits tab | ☐ |
| A14 | P0-15 | Build one outfit by hand; save; reopen | Same layout | ☐ |
| A15 | P0-16 | Open the AI log | Rows for tagging, intent and notes | ☐ |
| A16 | P1 | Add the same item again | Duplicate prompt | ☐ |
| A17 | P1 | Ask for an outfit with no weather words | Weather chip filled from today's weather | ☐ |
| A18 | P1 | Mark an outfit worn; ask again | It is not in the first three | ☐ |
| A19 | P0-18 | Delete one item; then delete all data | Gone, including after restart | ☐ |
| A20 | — | Use the app for 10 minutes without a plan | No crash, nothing stuck | ☐ |

## Daily-use log

One line per day in `docs/DOGFOOD_NOTES.md`.

| Day | Date | Asked for an outfit? | Wore a suggestion? | Crash or lost data? | Most annoying thing |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| … | | | | | |
| 14 | | | | | |

Targets: an outfit request on 14 consecutive days; no crash or data loss in any 7-day stretch.

## Exit gate (this is the MVP gate)

- [ ] S6-U01 to U10 and S6-I01 to I04 pass
- [ ] A failing test was written before each of the five fixes, where the logic is testable
- [ ] Full regression run is green
- [ ] Every final eval recorded in `docs/EVAL_MVP.md`
- [ ] E-ENG passes on all 10 occasions after tuning
- [ ] Manual acceptance A01 to A20 passes
- [ ] No severity 1 or 2 defect open
- [ ] Daily-use log started and kept
- [ ] Next-step decision written on line 1 of `docs/EVAL_MVP.md`

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
