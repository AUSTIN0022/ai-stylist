# Sprint 4 Tests: Stylist chat

Sprint: [SPRINT_4.md](SPRINT_4.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

Automated tests use `FakeIntentParser` and `FakeNoteWriter`. The real model's understanding of sentences is measured by E-INT and E-NOTE.

Order of work: intent merge tests → note validator tests → card layout tests → session and swap tests → save tests → flow integration → UI.

## Unit tests (Mac)

### Intent handling (build steps 1, 3)

The model returns a `ParsedIntent` whose fields are all optional (nil means "not mentioned"). App code turns that into a full `OccasionIntent`. That code is what these tests cover.

| ID | Case | Given → Then |
|---|---|---|
| S4-U01 | Follow-up keeps unmentioned fields | previous = festival, evening, indoor; parsed = only `formalityMax: 2` → festival, evening, indoor, formality lowered |
| S4-U02 | Follow-up changes one field | previous indoor; parsed `setting: outdoor` → only setting changes |
| S4-U03 | First message | no previous; parsed `occasion: office` → dress codes and formality come from the occasion table |
| S4-U04 | Avoid backstop | message "no jeans, not black" with parsed `avoid` empty → avoid contains jeans and black |
| S4-U05 | Avoid limited to known values | parsed avoid contains "polyester vibes" → dropped; valid values kept |
| S4-U06 | Occasion chip builds an intent | tap Festival → intent from the table, with no parser call (fake parser call count stays 0) |
| S4-U07 | Pinned items never come from the model | `mustIncludeItemIds` is set only by the app's pin action |
| S4-U08 | Editing a chip | change time of day → new intent; shown-keys list cleared; no parser call |

### Note validator (build step 5)

| ID | Case | Given → Then |
|---|---|---|
| S4-U09 | Absent item type | outfit has no jacket; note says "the jacket adds…" → rejected |
| S4-U10 | Absent colour | outfit is rust, black, cream; note mentions "navy" → rejected |
| S4-U11 | Valid note | mentions only items and colours in the outfit → accepted |

### Outfit card layout (build step 4)

Layout is a pure function: slots and canvas size in, rectangles out.

| ID | Case | Then |
|---|---|---|
| S4-U12 | Slot boxes | top is above bottom; footwear is below both; no box leaves the card |
| S4-U13 | Aspect fit | a tall narrow cut-out and a wide short one both fit inside their box with proportions kept |
| S4-U14 | One-piece | takes the combined top and bottom area |
| S4-U15 | Set and extras | set slots are placed as top and bottom; outerwear left; accessories right; at most 2 accessories |

### Session, another option, swap (build step 6)

| ID | Case | Then |
|---|---|---|
| S4-U16 | Shown keys accumulate | after two rounds, all six keys are in the exclusion set |
| S4-U17 | Wardrobe exhausted | engine returns nothing new → state is "exhausted" with the `missing` slots, not an empty screen |
| S4-U18 | Alternatives are valid | every alternative for a slot passes the hard checks with the rest of the outfit |
| S4-U19 | Alternatives are for that slot only | swap footwear → only footwear offered, and not the current item |
| S4-U20 | Swap replaces one item | after a swap, the other slots are unchanged |

### Save and feedback (build steps 6, 7)

| ID | Case | Then |
|---|---|---|
| S4-U21 | Save creates rows | one `Outfit` (source ai, occasion set) and one `OutfitItem` per slot |
| S4-U22 | Note stored | the saved outfit keeps its note; an outfit with a rejected note saves with none |
| S4-U23 | Item deleted later | deleting a wardrobe item removes it from saved outfits; an outfit left with fewer than 2 items is deleted |
| S4-U24 | Feedback events | another option → 3 `rejected`; swap → 1 `swapped` with the slot; save → 1 `saved` |

## Integration tests (Mac, fakes, seeded store)

| ID | Case | Then |
|---|---|---|
| S4-I01 | Message to cards | Send text with a fake parser returning a festival intent → 3 outfits from the seeded wardrobe |
| S4-I02 | Intent reaches the engine | The engine is called with exactly the merged intent; the chips show the same values |
| S4-I03 | Parser fails or model unavailable | Fake parser throws → intent falls back to casual-day defaults, chips are shown, outfits still appear |
| S4-I04 | Another option three times | No outfit key repeats across the rounds |
| S4-I05 | Cards before notes | Fake note writer waits 5 s → outfits are available immediately; notes attach when ready |
| S4-I06 | Note writer fails | Fake throws → cards stay, without notes; no error shown to the user |
| S4-I07 | Hallucinated note | Fake returns a note naming an absent item → that card has no note; the other two keep theirs |
| S4-I08 | Log rows | One `intent` row per message and one `note` row per result set; chip taps write none |
| S4-I09 | Save and reload | Save an outfit, reopen the store → same items, occasion and note |

## UI smoke test

| ID | Case | Then |
|---|---|---|
| S4-UI01 | Launch with `-uiTesting`, open Stylist, tap the Festival chip, tap Save on the first card, open the Outfits tab | Three cards appear; the Outfits tab shows one outfit |

## Evals to run and record (iPhone)

Write to `docs/EVAL_SPRINT4.md`. Cases live in `AppTests/Evals/intent_cases.json`.

### E-INT: 15 sentences

| # | Sentence | Expected occasion | Expected dress code | Also expect |
|---|---|---|---|---|
| 1 | Office tomorrow, normal day | office | smartCasual or businessCasual | |
| 2 | Interview at a startup on Friday | interview | businessCasual | |
| 3 | Date night at a nice restaurant | date | smartCasual | evening or night |
| 4 | My cousin's sangeet on Saturday | weddingGuest | festive | preferIndian |
| 5 | Diwali at a friend's place, evening, indoors, no crackers | festival | festive or smartCasual | evening, indoor, no fireworks flag |
| 6 | Diwali party, we'll burst crackers on the terrace | festival | festive or smartCasual | fireworks flag |
| 7 | Going to the temple in the morning | puja | festive or smartCasual | day, religiousSite |
| 8 | Flight to Goa, then walking around all day | travel | casual | lotsOfWalking |
| 9 | Gym | gym | athletic | |
| 10 | Staying home today | home | home or casual | |
| 11 | College fest in the evening | party | casual or party | evening |
| 12 | Friend's wedding reception | weddingGuest | festive or formal | |
| 13 | Coffee with a friend, it's really hot out | casualDay | casual | hot |
| 14 | Dinner with my manager | date or office | smartCasual or businessCasual | evening |
| 15 | House party tonight, nothing black | party | party or smartCasual | avoid black |

Pass mark: 13 of 15 with a correct occasion and dress code.

### E-INT follow-ups: 5 cases

| # | After | Follow-up | Expected change, everything else kept |
|---|---|---|---|
| F1 | 5 | Make it more casual | formality range lower |
| F2 | 5 | No chinos | avoid has chinos |
| F3 | 3 | Actually it's outdoors | setting outdoor |
| F4 | 1 | It's going to rain | weatherFeel rainy |
| F5 | 4 | Not Indian wear this time | preferIndian false |

Pass mark: 4 of 5.

### E-NOTE

Run 10 of the sentences above on your real wardrobe and read all 30 notes.

| Check | Pass mark |
|---|---|
| Notes shown that mention an item or colour not in the outfit | 0 |
| Notes that passed validation | ≥ 24 of 30 |
| Notes that are specific to the occasion (your judgment) | ≥ 20 of 30 |

### Speed

| Measure | Pass mark |
|---|---|
| Send to cards visible | ≤ 4 s median |
| Chip tap to cards | under 1 s |
| Cards to notes | note it; no pass mark |

## Manual test script (iPhone 17, real wardrobe)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S4-M01 | Type "Diwali at a friend's place, evening, indoors" | Chips read Festival · Evening · Indoor; 3 cards appear, then notes | ☐ |
| S4-M02 | Read the three outfits | Complete outfits from your own clothes; at least 2 you would wear | ☐ |
| S4-M03 | Look at the cards | Top above bottom, shoes below, sizes sensible, nothing overlapping badly or cut off | ☐ |
| S4-M04 | Type "make it more casual" | Occasion stays; outfits get more casual | ☐ |
| S4-M05 | Type "no chinos" | An avoid chip appears; no chinos in results | ☐ |
| S4-M06 | Tap Another option until it runs out | Never repeats; ends with a clear message, not a blank screen | ☐ |
| S4-M07 | Tap the shoes on a card, tap Swap, pick another | Only shoes offered; only shoes change | ☐ |
| S4-M08 | Change the time-of-day chip | New results at once | ☐ |
| S4-M09 | Tap each occasion chip | Each gives sensible outfits | ☐ |
| S4-M10 | Save an outfit; open the Outfits tab; rename it; restart | Outfit is there with its name, items and note | ☐ |
| S4-M11 | Delete a wardrobe item that is in a saved outfit | Outfit updates or is removed; no blank image | ☐ |
| S4-M12 | Turn Apple Intelligence off; use an occasion chip; type a message | Chips still give outfits; typing falls back gracefully with editable chips | ☐ |
| S4-M13 | Ask for something your wardrobe cannot do (black tie) | Says what is missing | ☐ |

## Exit gate

- [ ] S4-U01 to U24 pass
- [ ] S4-I01 to I09 pass
- [ ] S4-UI01 passes
- [ ] Sprints 0–3 tests still pass (the engine's `alternatives` function has its tests in the package)
- [ ] E-INT, follow-ups, E-NOTE and speed recorded in `docs/EVAL_SPRINT4.md` and at pass mark
- [ ] Manual steps M01 to M13 pass
- [ ] No severity 1 or 2 defect open

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
