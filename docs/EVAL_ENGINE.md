# E-ENG: engine output on the 45-item fixture

Run date: 2026-11-14. Engine: Sprint 3 `OutfitEngine`, fixed seed 20261114, fixture `wardrobe.json` (42 items from your file plus the made-up mustard kurta, cream pyjama and tan juttis).
Pass mark (SPRINT_3_TESTS.md): at least 2 of 3 wearable on at least 8 of 10 occasions now; all 10 by Sprint 6.

How to fill this in: in each row's last column write W (would wear) or N plus one word of reason. Then count wearable per occasion in the summary table.
Regenerate with `WRITE_EVAL=/tmp/body.md swift test --package-path Packages/StyleEngine --filter E-ENG` (prints the same text to the test log).

Notes on reading it: the last two or three names in a row are accessories added after scoring. `variety` is the seeded random term and changes with the seed. Intents used are listed under each heading (weather "mild" where the occasion did not say).

## Rating sheet, before tuning (2026-11-14, engine v1)

### 1. Office, normal day

Intent: `office, day, mixed, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.853 | occasionFit 0.80, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.92 | |
| 2 | Rust mandarin-collar shirt + Olive corduroy trousers + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.839 | occasionFit 0.80, colourHarmony 1.00, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.48 | |
| 3 | Charcoal grey collared half-zip knit + Navy corduroy trousers + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.826 | occasionFit 0.80, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.71 | |

### 2. Interview

Intent: `interview, day, mixed, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Light blue oxford shirt + Black chinos, straight fit + Black Chelsea boots + Black leather belt + Clear rectangular glasses | 0.786 | occasionFit 0.80, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.26 | |
| 2 | Navy linen-blend shirt + Black chinos, straight fit + Black Chelsea boots + Black leather belt + Clear rectangular glasses | 0.772 | occasionFit 0.75, colourHarmony 0.90, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.72 | |
| 3 | Navy linen-blend shirt + Black chinos, relaxed fit + Black Chelsea boots + Clear rectangular glasses + Watch | 0.734 | occasionFit 0.69, colourHarmony 0.90, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.28 | |

### 3. Date night

Intent: `date, evening, mixed, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.861 | occasionFit 0.83, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.92 | |
| 2 | Rust mandarin-collar shirt + Olive corduroy trousers + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.847 | occasionFit 0.83, colourHarmony 1.00, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.48 | |
| 3 | Navy knit open-collar polo + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.846 | occasionFit 0.85, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.79 | |

### 4. House party

Intent: `party, evening, indoor, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.847 | occasionFit 0.78, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.92 | |
| 2 | Black Chelsea boots + Clear rectangular glasses + Watch + Mustard embroidered kurta + Cream pyjama | 0.810 | occasionFit 0.80, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.74 | |
| 3 | Cream half-zip knit + Olive corduroy trousers + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.803 | occasionFit 0.78, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.04 | |

### 5. Diwali at a friend's, evening, indoors

Intent: `festival, evening, indoor, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Rust mandarin-collar shirt + Olive corduroy trousers + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.857 | occasionFit 0.86, colourHarmony 1.00, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.48 | |
| 2 | Rust mandarin-collar shirt + Brown mocha linen trousers + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.845 | occasionFit 0.88, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.29 | |
| 3 | Tan juttis + Clear rectangular glasses + Watch + Mustard embroidered kurta + Cream pyjama | 0.845 | occasionFit 0.95, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.55 | |

### 6. Wedding guest

Intent: `weddingGuest, evening, mixed, mild`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Tan juttis + Clear rectangular glasses + Watch + Mustard embroidered kurta + Cream pyjama | 0.841 | occasionFit 0.93, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.55 | |
| 2 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.805 | occasionFit 0.64, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.92 | |
| 3 | Rust mandarin-collar shirt + Black chinos, straight fit + Tan juttis + Black leather belt + Clear rectangular glasses | 0.770 | occasionFit 0.77, colourHarmony 0.90, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.51 | |

### 7. Temple visit

Intent: `puja, day, mixed, mild, religiousSite`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Black leather belt + Clear rectangular glasses | 0.861 | occasionFit 0.83, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.92 | |
| 2 | Cream half-zip knit + Black chinos, relaxed fit + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.847 | occasionFit 0.83, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.94 | |
| 3 | Tan juttis + Clear rectangular glasses + Watch + Mustard embroidered kurta + Cream pyjama | 0.833 | occasionFit 0.91, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.55 | |

### 8. Travel day

Intent: `travel, day, mixed, mild, lotsOfWalking`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Brown linen shirt + Black slim-fit tee + Dark indigo regular-fit jeans + Black Adidas Sambas + Gold crucifix chain + Clear rectangular glasses | 0.831 | occasionFit 0.80, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.81 | |
| 2 | Navy and green striped rugby polo + Beige / cream relaxed jeans + Black Adidas Sambas + Gold crucifix chain + Clear rectangular glasses | 0.829 | occasionFit 0.80, colourHarmony 0.93, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.62 | |
| 3 | Brown linen shirt + Navy textured t-shirt + Beige / cream relaxed jeans + White Nike Air Force 1-style sneakers + Gold crucifix chain + Clear rectangular glasses | 0.822 | occasionFit 0.80, colourHarmony 0.92, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.55 | |

### 9. Casual weekend, hot

Intent: `casualDay, day, mixed, hot`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Burgundy collared t-shirt + Dark indigo regular-fit jeans + Birkenstock two-strap sandals + Gold crucifix chain + Clear rectangular glasses | 0.823 | occasionFit 0.80, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.99 | |
| 2 | Brown linen shirt + Dark indigo regular-fit jeans + Birkenstock two-strap sandals + Gold crucifix chain + Clear rectangular glasses | 0.813 | occasionFit 0.80, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.46 | |
| 3 | Burgundy collared t-shirt + Beige / cream relaxed jeans + Black Adidas Sambas + Gold crucifix chain + Clear rectangular glasses | 0.802 | occasionFit 0.80, colourHarmony 0.90, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.24 | |

### 10. Evening out, cold

Intent: `party, evening, mixed, cold`

| # | Outfit | Score | Parts | Wear / Wouldn't |
|---|---|---|---|---|
| 1 | Cream half-zip knit + Olive corduroy trousers + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.803 | occasionFit 0.78, colourHarmony 0.97, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.04 | |
| 2 | Rust mandarin-collar shirt + Black chinos, relaxed fit + Black windcheater + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.801 | occasionFit 0.78, colourHarmony 0.95, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.81 | |
| 3 | Rust mandarin-collar shirt + Black jeans + Dark charcoal zip jacket + Cream leather gum-sole sneakers + Clear rectangular glasses + Watch | 0.782 | occasionFit 0.77, colourHarmony 0.92, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.70 | |


## Summary

| # | Occasion | Wearable (of 3) | Pass (>= 2) |
|---|---|---|---|
| 1 | Office, normal day | /3 | |
| 2 | Interview | /3 | |
| 3 | Date night | /3 | |
| 4 | House party | /3 | |
| 5 | Diwali at a friend's, evening, indoors | /3 | |
| 6 | Wedding guest | /3 | |
| 7 | Temple visit | /3 | |
| 8 | Travel day | /3 | |
| 9 | Casual weekend, hot | /3 | |
| 10 | Evening out, cold | /3 | |

Gate decision (fill in after rating): _below 8 of 10 passing means Sprint 4 starts with table fixes before any UI._

## Interview: rejection list (S3-M03)

```
== Interview [interview, day, mixed, mild]
#1 0.786  Light blue oxford shirt + Black chinos, straight fit + Black Chelsea boots + Black leather belt + Clear rectangular glasses
     occasionFit 0.80, colourHarmony 0.83, formalityMatch 1.00, pairWeight 0.50, freshness 1.00, variety 0.26
#2 0.772  Navy linen-blend shirt + Black chinos, straight fit + Black Chelsea boots + Black leather belt + Clear rectangular glasses
     occasionFit 0.75, colourHarmony 0.90, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.72
#3 0.734  Navy linen-blend shirt + Black chinos, relaxed fit + Black Chelsea boots + Clear rectangular glasses + Watch
     occasionFit 0.69, colourHarmony 0.90, formalityMatch 0.75, pairWeight 0.50, freshness 1.00, variety 0.28
rejected 36, kept 9
  wrongDressCode (36): Beige / cream relaxed jeans; Birkenstock two-strap sandals; Black Adidas Sambas; Black beach sliders; Black graffiti-print t-shirt; Black jeans; Black slim-fit tee; Black windcheater; Bottle green graffiti-print t-shirt; Brown cable-knit polo sweater; Brown linen shirt; Brown mocha linen trousers; Brown polo t-shirt; Burgundy collared t-shirt; Charcoal grey collared half-zip knit; Cream half-zip knit; Cream leather gum-sole sneakers; Cream pyjama; Dark charcoal zip jacket; Dark indigo regular-fit jeans; Forest green cotton-linen shirt; Gold crucifix chain; Grey loose jeans; Mustard embroidered kurta; Navy and green striped rugby polo; Navy corduroy trousers; Navy hoodie; Navy knit open-collar polo; Navy textured t-shirt; Olive corduroy trousers; Rust mandarin-collar shirt; Tan juttis; Teal full-zip hoodie jacket; Terracotta check shirt; White Nike Air Force 1-style sneakers; White slim-fit tee
```

## Sprint 5 learning check (2026-11-22)

Automated on the fixture wardrobe (`S5LearningCheckTests`), not yet on your real wardrobe. Five top outfits from casual, date, party, travel and festival were "saved" and the second outfit of each "rejected"; pair weights were computed from those events and the Diwali and office requests re-run.

| Request | Saved pairs in top 3 (before → after) | Mean pairWeight part (before → after) | Clothing pair shared by all 3 |
|---|---|---|---|
| Diwali | 4 → 4 | 0.500 → 0.569 | none |
| Office | 6 → 6 | 0.500 → 0.627 | none |

Reading: learning is gentle. The learned signal reaches the top results (pair part rises) but does not reorder them on this wardrobe, because the saved outfits came from the same engine and were already the best pairs. No pair dominates. Still to do by hand: the same check on your real wardrobe after a week of saves and rejects.
