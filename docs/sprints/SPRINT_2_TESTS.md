# Sprint 2 Tests: Tagging and editing

Sprint: [SPRINT_2.md](SPRINT_2.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

No test in this file calls the real model. Use `FakeTagger`, which can return canned tags, throw, or wait. The real model is measured by the evals at the bottom.

Order of work: merge and override tests → tagger and queue tests → log tests → filter tests → pipeline integration → UI.

## Unit tests (Mac)

### Raw vs corrections (build steps 1, 5)

| ID | Case | Given → Then |
|---|---|---|
| S2-U01 | Override wins | raw fabric `cotton`, override `linen` → merged `linen` |
| S2-U02 | No override | raw fabric `cotton`, no override → merged `cotton` |
| S2-U03 | Override removed | remove the fabric override → merged back to `cotton` |
| S2-U04 | Same as raw clears override | set override to the raw value → override key is removed, not stored |
| S2-U05 | Raw is untouched by edits | `aiRawData` bytes before and after `setOverride` are identical |
| S2-U06 | Only allowed values | `setOverride` accepts enum cases only; dress codes and seasons accept a set; an empty set for dress codes is rejected |
| S2-U07 | Re-tag keeps overrides | replace raw with new tags → overrides unchanged; merged still shows the override |

### Tag type and naming (build steps 1, 6)

| ID | Case | Given → Then |
|---|---|---|
| S2-U08 | `ItemTags` round trip | encode and decode → equal |
| S2-U09 | Missing fields allowed | JSON without collar or sleeve decodes (footwear) |
| S2-U10 | Auto-name | rust + mandarin + linen + shirt → "Rust mandarin-collar linen shirt"; black + relaxed chinos → "Black relaxed chinos"; cream + knit sweater → "Cream knit sweater" |
| S2-U11 | Name without unknowns | fabric `unknown`, collar `none` → those words left out |
| S2-U12 | Edited name is kept | after a user rename, re-tagging does not change the name |

### Tagger and queue (build steps 2, 3)

| ID | Case | Given → Then |
|---|---|---|
| S2-U13 | Call B fields follow category | top → collar, sleeve, fit, length, fabric, pattern; bottom → no collar or sleeve; footwear → fabric and `closedToe` only; accessory → fabric only |
| S2-U14 | Version saved | after tagging, `taggerVersion` equals the tagger's `version` |
| S2-U15 | One at a time | enqueue 5 with a slow fake → never more than one running |
| S2-U16 | Success path | status goes `tagging` → `ready`; raw tags and name are set |
| S2-U17 | Failure path | fake throws → status `failed`, error text stored, raw stays nil |
| S2-U18 | Manual retry | retry on a failed item with a now-working fake → `ready` |
| S2-U19 | Resume on launch | items left in `tagging` are re-queued when the queue starts |
| S2-U20 | Timeout | fake never returns → item becomes `failed` after the timeout; the queue moves on |

### AI request log (build step 4)

| ID | Case | Given → Then |
|---|---|---|
| S2-U21 | Row on success | one wrapped call → one row with purpose, provider, duration > 0, success true |
| S2-U22 | Row on failure | wrapped call throws → one row with success false and the error text; the error is re-thrown |
| S2-U23 | Three rows per item | tagging one item writes `tagA`, `tagB`, `tagC` in that order |

### Filters and search (build step 8)

| ID | Case | Given → Then |
|---|---|---|
| S2-U24 | One filter | category top → only tops |
| S2-U25 | OR within a field | colours navy or black → items with either |
| S2-U26 | AND across fields | category top and dress code festive → only festive tops |
| S2-U27 | Filters use merged tags | raw `casual`, override `festive` → appears under festive, not under casual |
| S2-U28 | Search | "MANDARIN" matches the name; "crinkled" matches the caption; empty text returns everything |

### No-AI mode (build step 9)

| ID | Case | Given → Then |
|---|---|---|
| S2-U29 | Availability mapping | available → normal; each unavailable reason → banner text and manual mode on |

## Integration tests (Mac, fake cut-out and fake tagger)

| ID | Case | Then |
|---|---|---|
| S2-I01 | One image through the whole pipeline | Item ends `ready` with cut-out files, colours, raw tags, a name, and 3 log rows |
| S2-I02 | Batch of 10 where the 4th fails | 9 `ready`, 1 `failed`; the queue did not stop |
| S2-I03 | Edit, then re-tag | Raw replaced by the new answer; override kept; merged shows the override; stored in the on-disk store after reopening |
| S2-I04 | Model unavailable | Added item is `ready` with empty tags and opens for manual tagging; when the fake becomes available, "tag untagged" queues exactly those items |
| S2-I05 | Restart mid-queue | 5 queued, stop after 2, start a new queue on the same store → the other 3 finish; nothing is tagged twice |
| S2-I06 | Colours untouched by tagging | Colours from Sprint 1 are the same before and after tagging |

## UI smoke test

| ID | Case | Then |
|---|---|---|
| S2-UI01 | Launch with `-uiTesting`, open the review screen for a seeded item, tap the fabric chip, choose linen, save, relaunch | The chip reads linen after relaunch |

## Evals to run and record (iPhone)

Write to `docs/EVAL_SPRINT2.md`. Run through the real pipeline, not the Sprint 0 spike.

| Eval | Pass mark | Also check |
|---|---|---|
| E-TAG | Marks in TEST_PLAN §5 | No field more than 5 points below `EVAL_SPRINT0.md` |
| E-SPEED | Median photo-to-ready ≤ 20 s; tagging ≤ 10 s | Time for a batch of 20; note phone temperature |
| E-DET | 10 items tagged twice are identical | |
| Edits needed | Add 15 new items of your own and review them | Median edits per item ≤ 1; list which fields you corrected most |

If the Sprint 0 decision was Gemini: run E-TAG with `GeminiTagger`, record the rate-limit behaviour, and confirm the key file is git-ignored (`git status` shows nothing).

## Manual test script (iPhone 17)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S2-M01 | Add 10 photos, leave the screen | Each item shows a tagging state, then a name and category, without you staying on the screen | ☐ |
| S2-M02 | Open the rust shirt | Tags read roughly: top, shirt, western, solid, linen or cotton-linen, relaxed, mandarin, long sleeve, smart casual | ☐ |
| S2-M03 | On the review screen, change fabric, then dress codes (two values) | Each takes two taps; only allowed values offered; saved after restart | ☐ |
| S2-M04 | Look for the "check this" marker | Shown on fabric when unknown and on empty fields; not on confident fields | ☐ |
| S2-M05 | Filter by Festive; add Colour = navy; type "polo" in search | Results narrow each time and match what you expect | ☐ |
| S2-M06 | Turn Apple Intelligence off, reopen, add one photo | Banner explains; item can be tagged by hand; turning it back on offers to tag it | ☐ |
| S2-M07 | Force-quit while 5 items are tagging, reopen | Remaining items finish; none stuck | ☐ |
| S2-M08 | Tap Re-tag on an item you corrected | Your correction is still shown | ☐ |
| S2-M09 | Open a pair of shoes on the review screen | No collar or sleeve chips | ☐ |
| S2-M10 | Open the AI log in Settings | Three rows per tagged item with durations | ☐ |
| S2-M11 | Add 20 items in one batch | Progress "N of M" visible; app stays responsive; phone not uncomfortably hot | ☐ |

## Exit gate

- [ ] S2-U01 to U29 pass
- [ ] S2-I01 to I06 pass
- [ ] S2-UI01 passes
- [ ] Sprint 0 and 1 tests still pass
- [ ] Evals recorded in `docs/EVAL_SPRINT2.md`, at pass mark, no regression over 5 points
- [ ] Manual steps M01 to M11 pass
- [ ] No severity 1 or 2 defect open

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
