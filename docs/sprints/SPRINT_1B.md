# Sprint 1b: Fixes from the first device test

**Dates:** 13–16 Nov 2026 · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.2, §5.3 · **Tests:** [SPRINT_1B_TESTS.md](SPRINT_1B_TESTS.md)

Added after Austin's first run on the iPhone 17 (13 Nov). Sprint 2 starts after this.

## What the device test showed

| Problem | Cause |
|---|---|
| Bed sheet, video thumbnail and sheet strips kept in the cut-out | `VisionCutoutService` merged **every** subject Vision returned (meant to keep shoe pairs) |
| "Silver" listed for a black tee | The bed sheet was in the cut-out, so its pixels were counted |
| Black tee named "navy" (`#151B26`) | Nearest-colour naming; very dark pixels with a blue cast from room light land nearer navy |
| Dashed box on the camera did nothing | Decoration only; nothing used it |
| No chance to fix a bad cut-out or colour before saving | The pipeline saved straight to the wardrobe |
| Barcode `2050032266712` cannot be looked up | Codes starting 20–29 are a store's internal numbers (GS1 restricted circulation); only Westside's billing system knows them |

## What to build

### 1. Choose the right subject (package, `WardrobeImaging`)
- Score each Vision instance instead of merging all:
  - overlap with the camera box (camera photos), else closeness to the image centre
  - area (larger is better); penalty for touching two or more frame edges (usually the bed or table)
- Keep the best instance. Add another only if it is a **twin**: area within 50% of the best and bounding boxes within one box-width of each other (shoe pairs).
- If the second-best scores within 15% of the best and is not a twin, mark the result **needs choice**.
- `CutoutResult` gains `candidates` (index, normalised bounds, area share, score), `chosen` (indices), `needsChoice`.
- New call: cut out with explicit chosen instance indices, or with a tap point (the instance whose mask contains it; nearest if none).

### 2. Make the camera box real
- The camera passes the box rectangle (normalised to the photo, top-left origin) with each shot.
- Subjects whose centre is outside the box are dropped before scoring. The final mask is clipped to the box grown by 10% per side.
- No subject centred in the box → `noClearItem` with the hint "Put the item inside the box".
- Box enlarged to about 85% of screen width, 3:4. Hint: "Fit one item inside the box · plain background · good light".
- Library photos have no box; scoring uses the centre.

### 3. Colour naming
- **Black rule:** Lab lightness < 22 and chroma < 12 → black, before nearest lookup. `#151B26` → black; real navy `#1F2A44` (chroma ≈ 20) stays navy.
- **White rule:** lightness > 92 and chroma < 6 → white.
- Each extracted colour records **ambiguous** = nearest and second-nearest references within 6 Lab units, or a black/white rule fired. The review step asks about ambiguous colours.

### 4. Busy-background flag
- New quality reason `busyBackground`: edge density outside the chosen mask (within its bounds grown 20%) above a threshold. Message: "Busy background. A plain sheet or the floor works better." Not blocking.

### 5. Review step after Done (app)
After the camera's **Done**, or after picking from the library, photos are processed one by one and shown in a full-screen **Review** pager. Nothing reaches the wardrobe until Save.

Per photo:
- Cut-out on white, large; toggle to see the original.
- **Tap to choose the item.** When the result needs a choice, the original is shown with candidates outlined and "Tap the item". **Adjust cut-out** opens the same view on any photo and allows tapping several candidates (pairs).
- **Questions only when unsure**, one tap each, skippable:
  - Colour, if the first colour is ambiguous: "Is this black?" → Yes, the two nearest named colours, Other (full list).
  - Fit, always for now (no AI fit until Sprint 2): Slim · Regular · Relaxed · Loose · Boxy · Skip. From Sprint 2 only when the AI's answer is missing or flagged.
  - Busy background / cut off: a note with Retake.
- **Scan label** (see 6).
- **Retake** · **Discard** · **Save**, and "3 of 5".
- Answers are **user corrections**: saved to `userOverrides`, never `aiRaw`. A colour answer replaces the first colour name; the hex stays.
- Discarded photos leave no files.

### 6. Scan label (package parser + app)
- **Scan label** opens the camera on the neck label, care label or price tag. One photo.
- On-device text recognition and barcode detection (Vision). A parser in the package returns `LabelData`:
  - `brand`: from a known list (Westside/Wes/W, Zara, H&M, Uniqlo, Levi's, Allen Solly, Van Heusen, Peter England, Louis Philippe, Jack & Jones, Snitch, Bewakoof, The Souled Store, Roadster, HRX, Marks & Spencer, Pantaloons, Max, FabIndia, Manyavar, Biba, Aurelia, Libas, U.S. Polo Assn, Tommy Hilfiger, Ralph Lauren), else nil
  - `composition`: "100% organic cotton", "60% cotton 40% polyester" → list of (percent, fibre); main fibre mapped to `Fabric` (polyester/viscose/rayon/nylon/elastane → synthetic)
  - `fit`: "slim fit" → slim, "regular fit" → regular, "relaxed" → relaxed, "oversized" → loose, "boxy" → boxy
  - `size`: XS–XXXL, or waist 26–44, only near the word "size" or alone on a line
  - `mrp`: "MRP ₹1,299", "Rs. 1299"
  - `barcode`: stored as-is for duplicate detection; never looked up
- Shown as editable chips. Confirmed values go to `Item.labelData`. Merge order for effective tags: **aiRaw < labelData < userOverrides**.
- Label photo stored as `label.jpg` in the item's folder.

## Schema changes
- `Item.labelData: Data?` (JSON `LabelData`); `ImageStore` name `label.jpg`
- Effective tags merge aiRaw, then labelData, then userOverrides
- `QualityReason.busyBackground`; `CutoutResult.candidates/chosen/needsChoice`; colour `ambiguous`

## Expected behaviour
- Black tee on the floral sheet, top-down inside the box: only the tee; colour black; busy-background note; fit question.
- Website screenshot from the library: only the shirt, no video thumbnail — or "Tap the item" if scores are close.
- Pair of shoes: both kept.
- Neck label "W… 100% organic cotton, slim fit, S" → brand Westside, fabric cotton, fit slim, size S.
- Discard leaves no files; Save puts the item under Unsorted with answers applied.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Shoe pair loses one shoe | Twin rule too strict | Widen the area ratio or distance; test with shoes apart |
| A big print splits the garment and only part is kept | Vision returned the print as its own instance | Merge instances lying fully inside the chosen one's bounds; "Adjust cut-out" lets the user tap several |
| Box clipping cuts off sleeves | Item bigger than the box | 10% margin; hint; review shows it so the user can retake |
| Dark brown becomes black | Chroma limit too high | Keep chroma < 12; test with a dark brown |
| Label read wrong (O vs 0, stray "S") | OCR noise | Size only near "size" or alone on a line; every value is an editable chip before saving |
| Unknown brand | Not in the list | "Brand: add" for manual entry |

## Not in 1b
AI tagging (Sprint 2), barcode lookup, a brush eraser for cut-outs (tap-to-choose first; revisit after use).

---

## Round 2 (14 Nov, after the second device test)

### What the test showed
| Problem | Cause |
|---|---|
| Label scan read only "cotton"; size "S" missed | The label photo was motion-blurred and the logo font is stylised; the scanner took any photo with no sharpness or text check |
| Size became "A" and could not be changed | Size was a free-text field in the review, and item detail shows label values read-only |
| Brand field is blank every time | No suggestions |
| Shutter sits mid-screen in label mode | Label camera reused the item camera layout with a long hint |
| Correct item still under "Unsorted" | Category comes from AI tagging, which is Sprint 2. Until then every item has no category |

### What to build
1. **Live label scanner.** Replace the label photo camera with VisionKit's live text scanner (`DataScannerViewController`, text + barcodes, high accuracy), shown with a small dashed target box (about 80% width, 1:2.5 height ratio) set as the scanner's region of interest. Recognised text is highlighted live, so the user sees what was read. The capture button is at the bottom and enabled only when at least one line of text is recognised inside the box. On capture: take a still photo (`capturePhoto`), run the blur check (Laplacian on the box area); if blurry, show "Hold steady, it's blurry" and stay in the scanner. Combine the live-recognised lines with a `RecognizeTextRequest` pass on the still, deduplicated, then parse. Fall back to the old photo camera if the scanner is unsupported or unavailable.
2. **Parser improvements.**
   - Size: also accept a lone `S/M/L/XL/XXL/XS/XXXL` or `2XL/3XL` line anywhere in neck-label text; normalise `2XL` → `XXL`; accept "Size S", "SIZE: M", "S/36", "M (38)" → letter size; waist 26–44 and shirt chest 36–46 only next to "size" or "waist".
   - Brand: fuzzy match against the brand list and the user's past brands (case-insensitive, edit distance ≤ 1 for names of 4+ letters, so "WES"/"W≡S" OCR noise like "WE5", "WFS" maps to Westside).
   - Price tags: `mrp`, `salePrice` ("Sale price", "Offer price", "Our price"), `colour` text ("Colour:", "Color:", "Shade:"), `styleCode` ("Style", "Art No", "Article", "SKU", "Style Code"), `size` from "Size:" lines. New optional fields on `LabelData`.
   - Ignore MRP values below ₹50 or above ₹200,000 (OCR noise).
3. **Constrained editing.**
   - Size picker: XS, S, M, L, XL, XXL, XXXL, Free size, then waist 26–44, then "Other…" (free text). Used in the review label editor and in item detail.
   - Brand field: suggestions as you type, from brands already in this wardrobe first, then the built-in list. Free text allowed.
   - Item detail: an **Edit** button on the Label section opens the same editor (brand, fabric, fit, size, MRP, sale price, colour text, style code). Saving updates `labelData`. A **Rescan label** button replaces it.
4. **Category question now (until Sprint 2).** In the review, a first question "What is it?" with the six categories (Top, Bottom, One-piece, Outerwear, Footwear, Accessory), then subcategory chips for that category. The answer is a user correction (`userOverrides.category`, `.subcategory`) and the grid sections use it, so the item leaves "Unsorted". From Sprint 2 the AI fills these and the question is asked only when the AI's answer is missing.
5. **Label camera layout.** Shutter at the bottom; hint shortened to "Fit the label in the box"; same bottom bar as the item camera.

### Not in round 2
Web search for brands (no backend in the MVP; brand list and past brands only).

---

## Round 3 (14 Nov, after the third device test)

### What the test showed
| Problem | Likely cause |
|---|---|
| Composition read, but "SLIM FIT" and the lone "S" were not filled in automatically | Unknown. We never see the raw text the scanner read. Lone single letters are often dropped or misread ("$", "5") by text recognition |
| Composition listed twice | Live lines and still-photo lines merged without normalising case/spacing before de-duplicating |
| Shutter and Cancel sit just under the box, mid-screen | Scanner overlay layout |
| "What is it?" shows every category and subcategory | No suggestion; category was planned for Sprint 2 AI |

### What to build
1. **Show the raw text.** The label editor gets a collapsed "Text read" section listing every recognised line, and `LabelData.rawText` stores it. Needed to debug the parser on real labels and for E-LABEL.
2. **Better single-letter capture.** Run the still-photo text pass with the smallest minimum text height and language correction off; also run it on a 2× upscaled crop of the box. In a neck label (≤ 6 lines and a fit or composition line present), map a lone `$`, `5` or `s` line to S, a lone `1` or `l` line to L is NOT allowed (too risky), and keep `M`, `L`, `XL` as read.
3. **De-duplicate properly.** Normalise lines (trim, collapse spaces, case-fold, strip punctuation) before de-duplicating, and de-duplicate composition parts.
4. **Scanner layout.** Controls pinned to the bottom safe area of the full screen (same bar as the item camera); hint at the top; box centred. Verify on the simulator with the fallback camera and by a screenshot.
5. **AI category suggestion (Sprint 2 call A, brought forward).** Add the `ItemTagger` protocol from Sprint 2 with only the identity call for now: on-device Foundation Models, `@Generable` struct of `Category` + `Subcategory` + `StyleOrigin`, greedy sampling, the cut-out on white at the Sprint 0 image size (768 px). Result saved to `aiRaw` (this is AI output, not a user correction) and one `AIRequestLog` row. In the review, "What is it?" shows the AI's answer preselected as one chip ("T-shirt · Top") plus up to two alternatives from the same category and "Something else" (opens the full lists). Accepting needs no tap; changing it writes a user correction. If the model is unavailable or fails, the question falls back to the full lists. Runs while the photo is processing, so it adds no visible wait in most cases.

---

## Round 4 (14 Nov, after the fourth device test)

### What the test showed
| Problem | Likely cause |
|---|---|
| White tees: ragged cut-outs with holes and stray blobs, bits of sheet kept | White garment on a light sheet is low contrast for Vision's subject mask; the mask is used raw (no hole fill, no blob removal) |
| White named silver/beige (`#D2D3CD`, `#D7D8D2`) | Indoor light makes white read at Lab L ≈ 84–86; the white rule needed L > 92 |
| WES label on the white tee read blank | Light-grey print on white fabric is low contrast; only one text pass on the unprocessed photo |
| Max label read correctly as Lifestyle · Max, XS, loose | Works |
| Delete button and label photo hidden under the tab bar on item detail | Scroll content has no bottom inset for the floating tab bar |
| No way to fix old items (Unsorted, bad cut-out, untagged) | Review only runs on new photos |

### What to build
1. **Mask clean-up** (package, pure, tested): keep the largest connected component plus any component ≥ 15% of its area (shoe pairs), fill interior holes, morphological close (radius ~1% of the short side), then the existing 1 px erode. Applied after subject choice, before compositing.
2. **Light-on-light hint**: if the garment's main colour has L > 75 and the surround (bounds grown 20%, outside the mask) also has mean L > 70, add the note "Light item on a light surface. A dark sheet or floor gives a cleaner cut-out." with Retake.
3. **White rule v2**: L > 80 and chroma < 8 → white (ambiguous unless L > 90); a light grey with L ≤ 80 stays grey/silver. Keep `#C0C0C0` as silver, `#F3EBDD` as cream.
4. **Label text passes**: run text recognition on the box crop three ways and merge: original, contrast-stretched grayscale (`CIColorControls` contrast up + `CIExposureAdjust` as needed, or a histogram stretch), and inverted (for white-on-dark labels). Keep the 2× upscale.
5. **Item detail layout**: content padded for the tab bar (`.safeAreaPadding(.bottom)` or `contentMargins`) so Delete and the label photo are reachable; label photo as a tappable thumbnail that opens full screen.
6. **Review existing items**:
   - Item detail gets **Review again**, which opens the same review screen for that one item (Adjust cut-out from the stored original, AI "What is it?", colour, fit, Scan label, **Retake photo**). Saving updates the item in place; no new item.
   - The **Unsorted** section header gets **Sort these (N)**, which opens the review pager over all unsorted items one by one.
   - Old items with no AI tags get the identity call when reviewed again.

### Tests (S1B-U66..U72, S1B-I16..I18)
| ID | Given → Then |
|---|---|
| U66 | mask with a hole in the middle → hole filled |
| U67 | main blob + tiny far blob (2% area) → tiny blob removed; two equal blobs (shoes) → both kept |
| U68 | jagged edge mask → after close, perimeter shorter, area within 5% |
| U69 | `#D2D3CD`, `#D7D8D2` → white; `#C0C0C0` → silver; `#F3EBDD` → cream |
| U70 | light garment + light surround → light-on-light note; light garment + dark surround → no note |
| U71 | contrast stretch of a low-contrast synthetic image raises its luminance range; inversion maps black↔white |
| U72 | text merge of three passes keeps each line once |
| I16 | Review again on a saved item with a fake provider: change category and colour, save → same item id updated, item count unchanged |
| I17 | Sort these with 3 unsorted items → pager of 3; after categorising all, Unsorted is empty |
| I18 | Retake photo in Review again replaces the item's image files, keeps its label and overrides |
