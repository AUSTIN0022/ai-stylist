# E-S4: Stylist chat evals (Sprint 4)

Run date: ___ · Device: iPhone 17, iOS ___ · parser version: fm-intent-1 · note version: fm-note-1
Cases: `AppTests/Evals/intent_cases.json`. Run on the iPhone with Apple Intelligence on, real wardrobe loaded.
Exit gate (SPRINT_4_TESTS.md): every section below at its pass mark.

## E-INT: 15 sentences (pass: 13 of 15 with correct occasion and dress code)

For each sentence, type it in the Stylist tab and read the chips. Write the occasion and dress code the chips showed, then Y or N.

| # | Sentence | Expected occasion | Expected dress code | Also expect | Got occasion | Got dress code | Also met? | Correct (Y/N) |
|---|---|---|---|---|---|---|---|---|
| 1 | Office tomorrow, normal day | office | smartCasual or businessCasual | | | | | |
| 2 | Interview at a startup on Friday | interview | businessCasual | | | | | |
| 3 | Date night at a nice restaurant | date | smartCasual | evening or night | | | | |
| 4 | My cousin's sangeet on Saturday | weddingGuest | festive | preferIndian | | | | |
| 5 | Diwali at a friend's place, evening, indoors, no crackers | festival | festive or smartCasual | evening, indoor, no fireworks flag | | | | |
| 6 | Diwali party, we'll burst crackers on the terrace | festival | festive or smartCasual | fireworks flag | | | | |
| 7 | Going to the temple in the morning | puja | festive or smartCasual | day, religiousSite | | | | |
| 8 | Flight to Goa, then walking around all day | travel | casual | lotsOfWalking | | | | |
| 9 | Gym | gym | athletic | | | | | |
| 10 | Staying home today | home | home or casual | | | | | |
| 11 | College fest in the evening | party | casual or party | evening | | | | |
| 12 | Friend's wedding reception | weddingGuest | festive or formal | | | | | |
| 13 | Coffee with a friend, it's really hot out | casualDay | casual | hot | | | | |
| 14 | Dinner with my manager | date or office | smartCasual or businessCasual | evening | | | | |
| 15 | House party tonight, nothing black | party | party or smartCasual | avoid black | | | | |

Correct: ___ / 15 · Pass: ☐

## E-INT follow-ups (pass: 4 of 5)

Type the "after" sentence, then the follow-up. Everything the follow-up does not mention must stay as it was.

| # | After | Follow-up | Expected change | Changed as expected | Rest kept | Correct (Y/N) |
|---|---|---|---|---|---|---|
| F1 | 5 | Make it more casual | formality range lower | | | |
| F2 | 5 | No chinos | avoid has chinos | | | |
| F3 | 3 | Actually it's outdoors | setting outdoor | | | |
| F4 | 1 | It's going to rain | weatherFeel rainy | | | |
| F5 | 4 | Not Indian wear this time | preferIndian false | | | |

Correct: ___ / 5 · Pass: ☐

## E-NOTE (10 sentences from above on your real wardrobe, 30 notes)

| Check | Count | Pass mark | Pass |
|---|---|---|---|
| Notes shown that mention an item or colour not in the outfit | | 0 | ☐ |
| Notes that passed validation | | ≥ 24 of 30 | ☐ |
| Notes specific to the occasion (your judgment) | | ≥ 20 of 30 | ☐ |

Sentences used: ___

## Speed

| Measure | Result | Pass mark | Pass |
|---|---|---|---|
| Send to cards visible (median of ≥ 5) | | ≤ 4 s | ☐ |
| Chip tap to cards | | under 1 s | ☐ |
| Cards to notes (note it) | | no pass mark | n/a |

Take the numbers from Settings, AI log (`intent` and `note` rows show duration) or a stopwatch.

## Decision

Intent glossary or instructions changed? ___ · Parser version bumped to: ___

## Notes

(Wrong occasions, follow-ups that reset fields, notes that read generic.)
