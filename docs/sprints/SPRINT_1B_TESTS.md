# Sprint 1b Tests: Fixes from the first device test

Sprint: [SPRINT_1B.md](SPRINT_1B.md) · Rules: [TEST_PLAN.md](../TEST_PLAN.md)

Order: colour rules → subject scoring → box clipping → busy background → label parser → review state → integration → device.

## Unit tests (Mac, package)

### Colour rules

| ID | Given → Then |
|---|---|
| S1B-U01 | `#151B26` → black, ambiguous true |
| S1B-U02 | `#1F2A44` → navy |
| S1B-U03 | `#0A0A0A` → black |
| S1B-U04 | dark brown `#3B2416` → brown, not black |
| S1B-U05 | `#FAFAF8` → white; `#F3EBDD` → cream |
| S1B-U06 | a colour midway between two references → ambiguous true; pure `#B5522B` → ambiguous false |

### Subject scoring and choice (instances given as synthetic masks)

| ID | Given → Then |
|---|---|
| S1B-U07 | big instance touching 3 edges (bed) + smaller centred instance (tee) → tee chosen |
| S1B-U08 | large centred shirt + small corner instance (video thumbnail) → shirt only |
| S1B-U09 | two equal shoes side by side → both chosen (twin) |
| S1B-U10 | two equal instances far apart, neither twin-close → needsChoice true |
| S1B-U11 | one instance → chosen, needsChoice false |
| S1B-U12 | tap point inside instance 2 → only instance 2 |
| S1B-U13 | tap point outside every instance → nearest instance |
| S1B-U14 | explicit chosen indices [0, 2] → mask is their union |
| S1B-U15 | small instance lying fully inside the chosen one's bounds (a print) → merged in |

### Camera box

| ID | Given → Then |
|---|---|
| S1B-U16 | box given; instance centred outside the box → dropped |
| S1B-U17 | box given; instance partly outside → mask clipped to box + 10% |
| S1B-U18 | box given; no instance centred inside → noClearItem with the box hint |
| S1B-U19 | no box (library) → scoring by centre, nothing clipped |
| S1B-U20 | box conversion from screen to photo coordinates for a 3:4 photo in a 19.5:9 preview (aspect fill) → expected normalised rect |

### Busy background

| ID | Given → Then |
|---|---|
| S1B-U21 | plain grey surround → no flag |
| S1B-U22 | checkerboard surround → busyBackground |
| S1B-U23 | busy pattern only inside the mask (printed shirt), plain surround → no flag |

### Label parser (text in, LabelData out)

| ID | Text → Then |
|---|---|
| S1B-U24 | "WES\n100% ORGANIC COTTON\nSLIM FIT\nS" → brand Westside, composition [(100, organic cotton)], fabric cotton, fit slim, size S |
| S1B-U25 | "60% Cotton 40% Polyester" → two parts; main fabric cotton |
| S1B-U26 | "65% Polyester 35% Viscose" → fabric synthetic |
| S1B-U27 | "100% Linen" → linen; "Cotton Linen" → cottonLinen |
| S1B-U28 | "MRP ₹ 1,299.00 incl. of all taxes" → mrp 1299; "Rs.799" → 799 |
| S1B-U29 | "Size: 32" → size 32; "Made in India" alone → no size; lone "S" in a sentence → no size |
| S1B-U30 | "Oversized Fit" → loose; "Regular Fit" → regular |
| S1B-U31 | unknown brand text → brand nil, other fields still parsed |
| S1B-U32 | barcode string kept verbatim; empty text → all fields nil, no crash |

### Merge order

| ID | Given → Then |
|---|---|
| S1B-U33 | aiRaw fabric cotton, label linen → linen |
| S1B-U34 | label linen, user override wool → wool |
| S1B-U35 | removing the override → label value returns |
| S1B-U36 | `LabelData` Codable round trip |

## Integration tests

| ID | Where | Case | Then |
|---|---|---|---|
| S1B-I01 | Mac | Review batch of 3 with fake cut-out provider: save 1, discard 1, retake 1 | 1 item saved; discarded photo leaves no files; retake slot reopens |
| S1B-I02 | Mac | Colour answer "black" on an ambiguous item | `userOverrides` has the colour; `aiRaw` untouched; hex unchanged |
| S1B-I03 | Mac | Fit answer, then Skip on the next item | First item override fit; second has none |
| S1B-I04 | Mac | Scan label with fake OCR text from U24, confirm | `labelData` stored, `label.jpg` saved, effective fabric cotton and fit slim |
| S1B-I05 | Mac | Nothing saved before Save | Wardrobe count unchanged while the review is open |
| S1B-I06 | Simulator | Existing Sprint 1 tests | All still pass |

## Evals (iPhone)

| Eval | Do | Pass mark |
|---|---|---|
| E-CUT-1B | Re-run the 5 photos from 13 Nov (blue jacket, both black-tee shots, website screenshot) plus 10 new ones on the same sheet | No background or overlay kept in at least 13 of 15, counting a "Tap the item" answer as success |
| E-COL-1B | Black, navy, dark brown, white and cream items | All named correctly, or flagged ambiguous and fixed in one tap |
| E-LABEL | 10 labels or price tags from your clothes | Brand ≥ 8/10 (known brands), fabric ≥ 9/10, size ≥ 9/10, fit where printed ≥ 8/10 |

Record in `docs/EVAL_SPRINT1.md` under a "1b" heading.

## Manual test script (iPhone 17)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S1B-M01 | Open camera | Bigger box; hint "Fit one item inside the box…" | ☐ |
| S1B-M02 | Shoot the black tee on the floral sheet, inside the box, then Done | Review opens; only the tee; colour black or a colour question; busy-background note; fit question | ☐ |
| S1B-M03 | Shoot with the tee mostly outside the box | "Put the item inside the box" | ☐ |
| S1B-M04 | Pick the website screenshot from Photos | Only the shirt, or "Tap the item" and tapping the shirt fixes it | ☐ |
| S1B-M05 | Shoot a pair of shoes | Both shoes | ☐ |
| S1B-M06 | On any photo tap Adjust cut-out, tap another candidate | Cut-out changes to it | ☐ |
| S1B-M07 | Shoot 3 items; save one, discard one, retake one | Only the saved and the retaken ones reach the wardrobe | ☐ |
| S1B-M08 | Scan the tee's neck label | Brand, cotton, slim, S shown as chips; edit one; save | ☐ |
| S1B-M09 | Open the saved tee | Colour black; label values shown | ☐ |
| S1B-M10 | Force-quit during review, reopen | Nothing half-saved in the wardrobe | ☐ |

## Exit gate
- [ ] S1B-U01 to U36 pass
- [ ] S1B-I01 to I06 pass
- [ ] Sprint 0 and 1 tests still pass
- [ ] E-CUT-1B, E-COL-1B, E-LABEL recorded and at pass mark
- [ ] Manual M01 to M10 pass

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |

---

## Round 2 tests (14 Nov)

### Unit (package)
| ID | Given → Then |
|---|---|
| S1B-U37 | "WES\n100% ORGANIC COTTON\nSLIM FIT\nS" → size S (lone line) |
| S1B-U38 | "Size: M", "SIZE M", "M (38)", "S/36" → M, M, M, S |
| S1B-U39 | "2XL" → XXL; "3XL" → XXXL |
| S1B-U40 | A sentence containing " a " or " S " mid-line → no size |
| S1B-U41 | "WE5" and "WFS" → Westside; "Zaro" → Zara; "Max" inside "Maximum comfort" → nil |
| S1B-U42 | past brands ["Snitch"] passed in; text "SNITCH" → Snitch; "SN1TCH" → Snitch |
| S1B-U43 | Price tag text "MRP ₹1,999\nSale Price ₹1,299\nColour: Olive\nStyle No: 300012345\nSize: L" → mrp 1999, salePrice 1299, colour "Olive", styleCode "300012345", size L |
| S1B-U44 | "MRP ₹ 12" → mrp nil; "MRP ₹ 4,99,999" → nil |
| S1B-U45 | Live lines + still-photo lines with duplicates → each line once, order kept |
| S1B-U46 | `LabelData` with new fields round-trips; old JSON without them still decodes |
| S1B-U47 | Size picker list: letters first, then "Free size", then waist 26–44 |
| S1B-U48 | Brand suggestions for "we": past brands first ("Westside" if used before), then list matches; empty input → past brands only |

### Integration (app, fakes)
| ID | Case | Then |
|---|---|---|
| S1B-I07 | Review: answer category Top → subcategory Tshirt, save | Item's effective tags have category top; it appears in the Tops section, not Unsorted |
| S1B-I08 | Item detail: edit label size from "A" to S | `labelData.size` = S; effective tags unchanged otherwise |
| S1B-I09 | Rescan label with fake text | `labelData` replaced; old `label.jpg` replaced |
| S1B-I10 | Blurry still (fake blur verdict) | Not accepted; scanner stays open with the message |

### Manual (iPhone)
| Step | Do | Expected | Pass |
|---|---|---|---|
| S1B-M11 | Scan label on the WES tee | Live highlights on the text; capture enabled only with text in the box; shutter at the bottom | ☐ |
| S1B-M12 | Capture while moving | "Hold steady" and stays in the scanner | ☐ |
| S1B-M13 | Capture steady | Westside, cotton (organic), slim, S filled; no MRP invented | ☐ |
| S1B-M14 | Scan a price tag on a new item | MRP, sale price, size, colour, style code filled where printed | ☐ |
| S1B-M15 | Open an item → Label → Edit; change size via the picker | Saved; shows the new size | ☐ |
| S1B-M16 | Type "W" in brand | Suggestions with Westside first | ☐ |
| S1B-M17 | Review a new item, answer "What is it?" | Item lands in its category section, not Unsorted | ☐ |

### Eval
E-LABEL re-run with the live scanner: 10 labels or tags. Pass marks unchanged (brand ≥ 8/10, fabric ≥ 9/10, size ≥ 9/10).

---

## Round 3 tests (14 Nov)

| ID | Kind | Given → Then |
|---|---|---|
| S1B-U50 | unit | `mergeLines` with "100% ORGANIC COTTON" and "100% organic  cotton" → one line |
| S1B-U51 | unit | composition parts de-duplicated: two identical "100% organic cotton" → one part |
| S1B-U52 | unit | neck label "WES\n100% ORGANIC COTTON\nSLIM FIT\n$" → size S; same with "5" → S |
| S1B-U53 | unit | price tag with a lone "5" line and no fit/composition line → no size |
| S1B-U54 | unit | `LabelData.rawText` round-trips; old JSON decodes |
| S1B-I11 | integration | Fake tagger returns tshirt/top → review preselects "T-shirt · Top"; save without tapping → `aiRaw` has category top, `userOverrides` has none, item in Tops |
| S1B-I12 | integration | Fake tagger returns tshirt; user picks Polo → `userOverrides.subcategory` polo; `aiRaw` unchanged |
| S1B-I13 | integration | Fake tagger throws → full category list shown; one AIRequestLog row with success false |
| S1B-I14 | integration | Alternatives for tshirt are two other `top` subcategories, never from another category |
| S1B-M18 | manual | Scanner: Cancel and shutter at the bottom of the screen |
| S1B-M19 | manual | Scan the WES label → open "Text read" → screenshot it for us; slim and S filled |
| S1B-M20 | manual | New item: "What is it?" already shows a correct suggestion for a tee, a shirt, jeans and shoes |
