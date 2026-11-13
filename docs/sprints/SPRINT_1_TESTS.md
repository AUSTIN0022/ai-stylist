# Sprint 1 Tests: Capture and cut-out

Sprint: [SPRINT_1.md](SPRINT_1.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

Order of work: taxonomy tests → colour tests → quality tests → image store tests → pipeline integration → UI. Write each group before the code it covers.

## Unit tests (Mac)

### Taxonomy (build step 1)

| ID | Case | Given → Then |
|---|---|---|
| S1-U01 | Raw values are unique and stable | Every enum's raw strings are unique; a snapshot test fails if a raw value is renamed (renames break stored data) |
| S1-U02 | Display names | Every case has a non-empty `displayName` |
| S1-U03 | Subcategory mapping is complete | Every `Subcategory` belongs to exactly one `Category` through `subcategories(for:)` |
| S1-U04 | Fields per category | `fields(for: .footwear)` has `closedToe`, no collar or sleeve; `.top` has collar and sleeve, no `closedToe`; `.accessory` has neither |
| S1-U05 | Codable round trip | Every enum case encodes and decodes to itself |

### Colour extractor (build step 6)

Images are made in code so the right answer is known exactly.

| ID | Case | Given → Then |
|---|---|---|
| S1-U06 | Solid colour | 100×100 image of `#B5522B` → one colour, hex within a small distance of the input |
| S1-U07 | Transparent pixels ignored | Red square on a fully transparent canvas → red only; nothing from the transparent area |
| S1-U08 | Two colours, ordered by size | 70% navy, 30% cream → `[navy, cream]` in that order |
| S1-U09 | Small cluster dropped | 95% black, 5% white → black only |
| S1-U10 | At most three | Four equal colour bands → 3 colours, or `multicolor` as specified |
| S1-U11 | Name mapping table | Reference hexes map to their names: `#000000` black, `#FFFFFF` white, `#1F2A44` navy, `#F3EBDD` cream, `#B5522B` rust, `#556B2F` olive, `#800020` maroon |
| S1-U12 | Navy is not black | `#1F2A44` → navy; `#0A0A0A` → black |
| S1-U13 | Edge pixels ignored | Red square with a 2 px white fringe → red only |

### Quality check (build step 4)

| ID | Case | Given → Then |
|---|---|---|
| S1-U14 | Too dark | All-black image → `.tooDark` |
| S1-U15 | Blurry | A sharp checkerboard → `.ok`; the same image heavily blurred → `.blurry` |
| S1-U16 | No clear item | Mask area 3% of frame → `.noClearItem`; no mask at all → `.noClearItem` |
| S1-U17 | Item cut off | Mask touching the left and bottom edges → `.cutOff`; touching one edge → `.ok` |
| S1-U18 | Good photo | Bright, sharp, mask 40% and centred → `.ok` |
| S1-U19 | Order of reasons | Dark and blurry together → `.tooDark` (one reason, the first that applies) |

### Image handling and store (build steps 2, 3, 5)

| ID | Case | Given → Then |
|---|---|---|
| S1-U20 | Orientation normalised | An image flagged as rotated right → pixel data upright, width and height swapped |
| S1-U21 | Save and load | Save three files for an item in a temp root → all three load back with the same bytes |
| S1-U22 | Delete | Delete the item → its folder no longer exists |
| S1-U23 | File names only | The item model stores names, and resolving them against a new root still finds the files |
| S1-U24 | Display image | Composite of a cut-out on white → square, corners are white, garment centred |
| S1-U25 | Merge mask instances | Two separate mask regions → one cut-out whose bounds cover both |

## Integration tests

| ID | Where | Case | Then |
|---|---|---|---|
| S1-I01 | iPhone | Cut-out on 5 saved eval photos | Each output has transparency and a bounding box smaller than the frame |
| S1-I02 | iPhone | Tight crop | Transparent margin around the garment is under 10% on each side |
| S1-I03 | Mac | Cut-out fails (fake provider throws) | Item is saved, `cutoutFailed` is true, display image is the centre-cropped original |
| S1-I04 | Mac | Batch of 20 images through the pipeline with a fake cut-out provider | 20 items saved; processed one at a time (peak concurrency 1); order preserved |
| S1-I05 | Mac | Persistence | Insert an item into an on-disk store in a temp folder, reopen the store → item and file names present |
| S1-I06 | Mac | Delete item | Row gone and its image folder gone |
| S1-I07 | Mac | All six models | One of each (`Item`, `Outfit`, `OutfitItem`, `WearLog`, `AIRequestLog`, `FeedbackEvent`) can be inserted and fetched |
| S1-I08 | Mac | Quality flag does not block | A flagged image with "use anyway" still produces an item |

## UI smoke test

| ID | Case | Then |
|---|---|---|
| S1-UI01 | Launch with `-uiTesting` and a seed of 6 items | Wardrobe tab shows 6 cells; tapping the first opens item detail with a colour swatch; delete returns to a grid of 5 |

## Evals to run and record

Write to `docs/EVAL_SPRINT1.md`.

| Eval | Do | Pass mark |
|---|---|---|
| E-COL | Run the colour extractor on all 30 eval cut-outs; compare the first colour name with `expected.json` | ≥ 90% |
| E-CUT | Re-judge all 30 cut-outs made by the real `CutoutService` | ≥ 27 of 30 clean |
| Quality thresholds | Run the quality check on the 30 good photos plus 5 dark and 5 blurry ones you take on purpose | 0 good photos flagged; all 10 bad ones flagged with the right reason |

Record the darkness and blur thresholds you settled on.

## Manual test script (iPhone 17)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S1-M01 | First launch, tap add | Permission prompts for camera and photos show your usage text | ☐ |
| S1-M02 | Pick 20 photos from Photos | 20 placeholders appear at once; each becomes a white-background image; no memory warning or crash | ☐ |
| S1-M03 | Use the in-app camera, take 5 shots in a row, tap Done | Framing guide and hint text visible; thumbnails build up; 5 items added | ☐ |
| S1-M04 | Take a photo in a dim room; take one while moving the phone | "Too dark" and "Blurry" each shown with Retake and Use anyway | ☐ |
| S1-M05 | Look at 10 cut-outs in the grid | Same white background, similar framing, no halo, no hanger or hand | ☐ |
| S1-M06 | Photograph a white tee on a white sheet | Flagged as no clear item; using it anyway keeps the original photo | ☐ |
| S1-M07 | Open the rust shirt and the check shirt | Rust swatch for the first; two or three swatches for the second; hex shown | ☐ |
| S1-M08 | Photograph a pair of shoes | Both shoes in the cut-out | ☐ |
| S1-M09 | Take a portrait and a landscape photo | Both appear upright | ☐ |
| S1-M10 | Force-quit and reopen | All items and images still there | ☐ |
| S1-M11 | Delete an item | It leaves the grid and does not return after restart | ☐ |

## Exit gate

- [ ] S1-U01 to U25 pass
- [ ] S1-I01 to I08 pass (I01, I02 on the phone)
- [ ] S1-UI01 passes
- [ ] Sprint 0 tests still pass
- [ ] E-COL, E-CUT and thresholds recorded in `docs/EVAL_SPRINT1.md` and at pass mark
- [ ] Manual steps M01 to M11 pass
- [ ] No severity 1 or 2 defect open

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
