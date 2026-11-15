# Sprint 2: Tagging and editing

**Dates:** 23–29 Nov 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.2 steps 5–7, §5.3, §5.7, P0-5 to P0-8, P0-16, P0-17

## Goal

Every item is tagged with no typing, and any wrong tag is fixed in one tap.

## Needs from earlier sprints

- Provider decision and image size from `docs/EVAL_SPRINT0.md`.
- Taxonomy, data model, cut-outs and colours from Sprint 1.
- The three tagging prompts from Sprint 0.

## What must exist at the end

| Piece | Behaviour |
|---|---|
| Tagger | Fills every tag in PRD §5.3 from the cut-out |
| Tagging queue | Tags new items one by one in the background; survives app restart |
| Raw vs corrections | The AI's answer is stored untouched; edits are stored separately |
| Review screen | New items shown with tag chips; any chip opens a picker |
| Wardrobe filters | Category, colour, dress code, season, and text search |
| AI log | One row per AI call |
| No-AI mode | Items can be added and tagged by hand when the model is unavailable |

## Build steps

### 1. Tag types (in the package, 0.5 h)
- `ItemTags`: a `Codable` struct with every tag field from PRD §5.3 as an optional. Optional because a field may not apply (collar on shoes) or may not be answered.
- `ItemTags.merged(over:)`: returns a copy where each non-nil field of the overrides replaces the raw value. This is the only place the merge rule lives.

### 2. Tagger (2.5 h)
```swift
protocol ItemTagger {
    var version: String { get }                 // e.g. "fm-ondevice-1"
    func tag(cutout: CGImage) async throws -> ItemTags
}
```
- `FoundationModelsTagger` runs calls A → B → C from Sprint 0, each in a fresh session with greedy sampling.
- Call B's struct depends on the category from call A: tops get collar, sleeve, fit, length, fabric, pattern; bottoms get fit, length, fabric, pattern; footwear gets fabric and `closedToe`; accessories get fabric only.
- Call C returns `dressCodes`, `formality`, `seasons`, `warmth`, `statement` and a one-line `caption`.
- Bump `version` whenever a prompt or struct changes. It is saved on each item so stale items can be found and re-tagged.
- Only if Sprint 0 said so: `GeminiTagger` behind the same protocol, key read from a git-ignored local config file, one request per item with a JSON schema, and a delay between items to respect the free-tier rate limit.

### 3. Tagging queue (2 h)
- An actor that takes item ids and processes **one at a time**.
- Per item: set `tagging` → run the tagger → write `aiRawData`, `taggerVersion`, auto-name → set `ready`. On error set `failed` and keep the error text.
- On app launch, re-queue every item still in `tagging`.
- Retry: a "Try again" button on failed items. No automatic retry loop.
- Colours come from Sprint 1's extractor and are not touched here.

### 4. AI request log (0.5 h)
- A small wrapper used by every AI call: records purpose (`tagA`, `tagB`, `tagC`), provider, model/version, start time, duration, success, error text, and token counts when the API reports them.
- A debug list of the last 100 rows in Settings.

### 5. Raw vs corrections (1 h)
- `item.aiRaw` is written only by the queue.
- `item.userOverrides` is written only by the edit UI. Choosing the same value the AI gave removes that override.
- `item.tags` (computed) = `aiRaw.merged(over: userOverrides)`. All screens and the engine read this.
- Re-tagging replaces `aiRaw` and leaves `userOverrides` as they are.

### 6. Auto-name (0.5 h)
- Built from tags: `[first colour] [collar if notable] [fabric if known] [subcategory]` → "Rust mandarin-collar linen shirt", "Black relaxed chinos", "Cream knit sweater".
- If the user edits the name, stop regenerating it.

### 7. Review screen (2.5 h)
- Appears after an add batch, and for any single item from its detail page.
- One card per item: cut-out on the left, tag chips on the right, grouped as What it is / How it's made / When to wear it.
- Tapping a chip opens a picker with that field's allowed values; multi-select for dress codes and seasons.
- Chips with a dot marker need a check: fabric when the answer is `unknown`, and any field the tagger left empty.
- Buttons: Retake (replaces the image and re-runs the pipeline), Re-tag, Save all.
- Items still tagging show a spinner per card; the user can leave and come back.

### 8. Filters and search (1.5 h)
- Filter chips above the grid: category, colour, dress code, season. Filters combine with AND across fields and OR within a field.
- Search matches name and caption, case-insensitive.
- Grid sections now use the real category; "Unsorted" is only for `tagging` and `failed` items.

### 9. No-AI mode (1 h)
- On launch and when the app returns to the foreground, check model availability.
- If unavailable: a banner on the Wardrobe tab with the reason and what to do. Added items go straight to `ready` with empty tags and open on the review screen for manual tagging.
- When the model becomes available, offer "Tag N untagged items".

## Expected behaviour

- Add 10 photos, put the phone down, come back in a couple of minutes: all 10 are named, tagged and in the right categories.
- The rust shirt reads: top · shirt · western · rust · solid · cottonLinen or linen · relaxed · mandarin · long · casual, smartCasual, festive.
- Changing fabric from cotton to linen takes two taps and survives a restart.
- Filtering by "festive" shows only items with that dress code.
- With Apple Intelligence off, the banner explains why and manual tagging works.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Items stuck on "tagging" forever | App killed mid-item and not re-queued | Re-queue `tagging` items on launch; add a timeout that marks the item `failed` |
| User's corrections vanish after re-tag | Re-tag overwrote overrides | Queue writes `aiRaw` only; add the test below |
| `aiRaw` changes when the user edits | Edit UI writes to the wrong blob | All edits go through one `setOverride(field, value)` function |
| Collar shown for shoes | Call B not branched by category | Use `fields(for:)` from the taxonomy to build the call and the review card |
| Tagging slows down or the phone gets hot on big batches | Back-to-back model calls | Keep it sequential; pause the queue when the system reports thermal state serious; show "N of M" |
| Same wrong tag on many items (every shirt "regular fit") | Prompt bias | Add a one-line definition of each value to the `@Guide`; re-run the Sprint 0 eval before and after |
| Caption describes the background or is very long | Prompt too open | "One sentence, under 20 words, describe only the garment"; send the cut-out |
| Accuracy dropped compared with Sprint 0 | Different image size or prompt drift | Re-run the eval inside the real pipeline; diff against `EVAL_SPRINT0.md` |
| Filters show nothing | Filtering on `aiRaw` not merged tags, or AND within a field | Filter on `item.tags`; OR within a field |
| Gemini returns rate-limit errors (only if used) | Free-tier limit | Space requests; on a limit error wait and resume, do not mark failed |

## Tests

**Tests first.** Write the cases in [SPRINT_2_TESTS.md](SPRINT_2_TESTS.md) before the code for each build step. That file has the full unit, integration, eval and manual cases and the exit gate; the list below is only a summary.

- Merge: raw fabric `cotton`, override `linen` → `linen`; override removed → `cotton`.
- Edit safety: after an edit, `aiRawData` bytes are identical to before.
- Re-tag: overrides are unchanged after `aiRaw` is replaced.
- `fields(for: .footwear)` excludes collar and sleeve.
- Auto-name for five fixture items matches expected strings.
- Eval from Sprint 0 runs through `FoundationModelsTagger` and writes results to `docs/EVAL_SPRINT2.md`.

## Checklist

- [ ] Tagger behind the protocol; version string saved per item
- [ ] Queue is sequential, resumes after restart, has manual retry
- [ ] One AI log row per call, visible in the debug list
- [ ] `aiRaw` byte-identical before and after an edit
- [ ] Re-tag keeps overrides
- [ ] Review screen edits every field from fixed values only
- [ ] Fields needing a check are marked
- [ ] Filters and search work on merged tags
- [ ] No-AI banner and manual tagging work with Apple Intelligence off
- [ ] Accuracy not below Sprint 0; median photo-to-ready ≤ 20 s
- [ ] No key committed (if Gemini was needed)

## How it lands

- Branch `sprint-2`, merge to `main`, tag `sprint-2-done`.
- Demo: add 10 items, show the review screen, fix one tag, filter by dress code.
- Start adding your real wardrobe now, a few items a day; Sprint 4 needs real data in the app.

## Not this sprint

Outfits, chat, duplicate detection, set-linking UI.

---

## Addendum (14 Nov): what changed before Sprint 2 started

Already built during Sprint 1b, so Sprint 2 builds on it instead of redoing it:
- `ItemTagger` protocol with the **identity call (A)** on-device, run inside the review; `aiRaw` vs `labelData` vs `userOverrides` merge; AI log rows for call A.
- Review screen (not a separate tag-chip screen) is where tags are confirmed. Sprint 2's "review screen" work extends it.
- No background queue: tagging runs while the review is open. The queue in step 3 is still needed for **Sort these** and **Review again** on many items, and for items saved before the model finished.

Added scope:
1. **Calls B and C** in `FoundationModelsTagger`, same pattern as A, run after A (B's fields depend on A's category).
2. **Review shows every tag** as compact chips grouped What it is / How it's made / When to wear it; only uncertain fields are asked as questions (existing behaviour), everything else is one tap to change.
3. **Adjust cut-out fix**: reported not working on the phone (14 Nov). Reproduce on the simulator with a real photo, fix, and add a test that a tap on a second candidate changes the saved cut-out files.
4. **Eval from my wardrobe** (Settings → Accuracy): for every item Austin has reviewed and saved, compare `aiRaw` with the effective tags (a field the user changed counts as an AI miss) and show per-field accuracy against the TEST_PLAN pass marks, plus label-read accuracy (items with a label vs fields the user edited after scanning). Writes the same table format as `EVAL_SPRINT0.md` and can be shared. This turns everyday use into the Sprint 0 / E-TAG eval without a separate photo session. The bundled-photo `DebugEvalView` stays reachable from Settings → Developer.
5. **Settings screen** (gear on the Wardrobe tab): AI status, counts, Accuracy, AI log (last 100 calls), Developer (DebugEvalView), Delete all data.

## Catalogue look (image clean-up), 14 Nov

Goal: every wardrobe tile looks like a product shot (reference: H&M product images, the Polo shirt screenshot): garment upright and centred, same scale and margins, neutral colour, clean edge, soft shadow, light grey-white background.

Deterministic, on-device, free. It does **not** iron wrinkles or rebuild missing parts; that needs generative AI (separate decision).

Steps, in the package, applied when building `display.jpg` (the cut-out PNG and original are untouched):
1. **Upright:** rotate by the angle of the mask's principal axis (moments) when it is within ±25° of vertical/horizontal, so a crooked flat-lay is squared up. Tops and bottoms stand upright (long axis vertical for bottoms and dresses; shoulders horizontal for tops).
2. **Neutral colour:** white-balance the garment using the photo's surround (grey-world on the area outside the mask, clamped), then a mild auto-levels on the garment only.
3. **Clean edge:** feather the mask edge by 1–2 px (after round 4's clean-up), remove remaining edge fringe by pulling edge pixels toward the interior colour.
4. **Framing:** scale so the garment's bounding box fills 82% of the long side of a 1200×1500 (4:5) canvas, centred; same rule for every item so tiles line up.
5. **Background and shadow:** `#F4F4F2` background, soft contact shadow (blurred, 12% opacity, offset down 1.5%).
6. **Regenerate existing items:** a one-time "Refresh catalogue images" action in Settings rebuilds `display.jpg` for all items from their stored cut-outs.

Tests (S2-CL01..CL07): rotation of a synthetic 15°-tilted rectangle mask to < 1°; grey-world on a blue-tinted surround removes the cast within 3 Lab units; framing puts the bounds at 82% ± 1% of the long side and centred ± 1%; background corner pixel equals `#F4F4F2`; shadow only below the garment; regenerate leaves the cut-out and original byte-identical; a 2048 px input processes in under 300 ms on the Mac.

## Adjust cut-out: zoom, pan and a draggable box (14 Nov)

Requested after the Sprint 2 device test. In the Adjust cut-out sheet:
1. **Zoom and pan** the photo: pinch to zoom (1×–5×), drag with one finger to pan when zoomed, double-tap to toggle 1× / 2.5×. Outlines and the box move with the photo.
2. **Draggable, resizable box**: a "Draw box" toggle shows a selection rectangle (starts at the current cut-out's bounds) with four corner handles and a draggable centre. Minimum size 8% of the photo side; it stays inside the photo.
3. **Apply** with the box re-runs subject choice inside it (instances centred outside are dropped, the mask is clipped to the box plus 10%), using the stored instance masks, no new Vision call. Tapping candidates still works when the box is off; with the box on, tapping toggles candidates inside it.
4. **Reset** returns to the automatic choice.

Tests: S2-U50 `recut(box:)` keeps only instances centred inside and clips the mask; S2-U51 a box containing no instance centre throws `noItemInBox` and leaves the cut-out unchanged; S2-U52 pure box-editing geometry (drag a corner, drag the centre, clamp to the photo, minimum size); S2-U53 view-to-photo coordinate mapping under zoom 2.5× and pan returns the same normalised point as at 1×; S2-I20 applying a box in the review updates the saved cut-out files and posts the refresh notification.

## Product photos with Apple Image Playground (14 Nov)

Decision (Austin, 14 Nov): store-style product images come from **Apple Image Playground** first (free, Private Cloud Compute, nothing stored by Apple, result lives only on the phone). Gemini's paid image model is the fallback only if this does not look right. The prototype stays free.

Goal: every garment type always looks the same — front view, straight, laid flat or "ghost" shape, plain light grey background, soft shadow, no person, no hanger — like the H&M sweater listings. Natural folds are fine; colour, print and details must match the real item.

Facts from the iOS 27.2 SDK (checked 14 Nov): the programmatic `ImageCreator` is deprecated; generation is only through `imagePlaygroundSheet(isPresented:concepts:sourceImage:onCompletion:onCancellation:)` (or `ImagePlaygroundViewController`), so **each product photo needs one tap from the user to generate and accept**. Concepts: `.text`, `.extracted(from:title:)`, `.image(CGImage)`. Style is set with `.imagePlaygroundGenerationStyle(_:in:)`; styles are `any`, `animation`, `illustration`, `sketch`, `emoji`, `externalProvider`. Availability: `@Environment(\.supportsImageGeneration)`.

Build:
1. **Template prompts (package, pure, tested):** `ProductShotPrompt.make(for tags: ItemTags, colours: [ColorName], label: LabelData?) -> String`. One fixed template per garment shape so results are uniform:
   - T-shirt / polo, short sleeve: "Front view e-commerce product photo of a {colour} {fabric} short-sleeve {crew-neck/polo} t-shirt, laid perfectly flat and symmetrical, sleeves straight out, centred, plain light grey background, soft natural shadow, no person, no mannequin, no hanger, no text."
   - Long-sleeve top / sweater / shirt: same, with "long sleeves straight down beside the body", collar type ("button-down collar", "mandarin collar"…) and placket for shirts.
   - Hoodie / jacket / outerwear: "…hood laid flat behind the collar, zip or front closed…".
   - Trousers / jeans / chinos / shorts: "…laid flat, legs straight and parallel, waistband at the top, front view…".
   - Dress / one-piece, saree, kurta, lehenga: shape-specific variants.
   - Footwear: "side view of a pair of {colour} {subcategory}, …".
   - Pattern and print words come from tags (`solid`, `stripe`, `check`, `graphic`); brand names are never put in the prompt.
   Max length 300 characters; deterministic for the same tags.
2. **Sheet flow (app):** "Make product photo" on item detail and in the review (after save). Presents `imagePlaygroundSheet` with concepts `[.text(prompt), .image(cutout)]` and `sourceImage` = the cut-out on white, style locked to `.any` (`.imagePlaygroundGenerationStyle(.any, in: [.any])`). On completion: copy the file from the temporary URL immediately, run it through `Catalogue.render` framing so every product photo has the same canvas and margins, save as `product.jpg` in the item folder, post `.itemImagesChanged`. Cancel leaves everything unchanged. Hidden when `supportsImageGeneration` is false, with a one-line reason.
3. **Display preference:** the grid and detail show `product.jpg` when present, otherwise the catalogue `display.jpg`. Item detail has a 3-way toggle Product / Cut-out / Photo. "Remove product photo" deletes only `product.jpg`. Colours, tags, label and the outfit engine always use the real cut-out, never the generated image.
4. **Batch helper:** Settings → "Make product photos (N)" steps through items without one, one sheet per item (the user taps Use or Cancel each time; Apple does not allow a silent batch).
5. **Log:** one `AIRequestLog` row per sheet (purpose `productShot`, provider `imagePlayground`, duration, success / cancelled). No token counts are available.

Tests (S2-PS01..PS08):
- PS01 the template for a black cotton short-sleeve crew-neck t-shirt contains "short-sleeve", "black", "cotton", "light grey background", "no person" and no brand.
- PS02 a white button-down long-sleeve shirt mentions "button-down collar" and "long sleeves".
- PS03 jeans use the trousers template ("legs straight and parallel"); footwear uses the side-view template.
- PS04 same tags give the identical string; length ≤ 300.
- PS05 label brand "Westside" never appears in any prompt.
- PS06 saving a completion URL writes `product.jpg` at 1200×1500 and leaves `cutout.png`, `display.jpg`, `original.jpg` byte-identical.
- PS07 display preference picks product > display; removing the product photo falls back to display.
- PS08 cancelling writes nothing and logs a cancelled row.

Manual (iPhone): make product photos for a black tee, a white tee, the navy hoodie, the Polo shirt and a pair of jeans; compare side by side with the H&M sweater references for shape uniformity and colour fidelity; note any changed logos or prints.

## Product photos round 2 (14 Nov, after Austin's device test)

What the test showed (screenshots 28–33): the default prompt now works; but (a) nothing visible happens for 3–4 s after "Make product photo"; (b) the generated photo keeps Image Playground's grey backdrop inside our light card (two backgrounds); (c) the hoodie came out crooked because Image Playground copies the layout of the source image, and our source is Austin's crooked cut-out; (d) Austin's favourite result is the maroon tee he made in the Playground app from his black-tee photo with his own sentence — the shape stayed, the colour changed.

Build:
1. **Loading feedback:** tapping "Make product photo" immediately dims the image and shows an animated sparkle/shimmer overlay ("Preparing…") until Apple's sheet appears, and again ("Saving…") after Use until `product.jpg` is written. The button shows a spinner and is disabled. Apple requires its own sheet for generation (ImageCreator is deprecated in iOS 27), so the sheet stays; the overlay makes the wait visible.
2. **One background:** run Vision's foreground mask on the generated image, cut the garment out, and render it with `Catalogue.render` onto the same `#F4F4F2` 1200×1500 canvas as every other tile. Product photos, catalogue tiles and the item card then share one background, scale and margins. If the mask fails, fall back to centre-cropping the generated image to 4:5 (no second inset card).
3. **Uniform shape per garment type — canonical templates:** pass a fixed **template image per garment shape** as `sourceImage` instead of the user's crooked cut-out, and put the item's colour phrase (+ hex) and fabric in the sentence. Shapes: `tshirtShort`, `tshirtLong` (also sweaters/polos long), `shirt`, `hoodie`, `jacket`, `trousers` (jeans/chinos/trousers), `shorts`, `shoes`. The first template is bundled: `App/Templates/tshirt-short.jpg` (Austin's maroon tee). For the other shapes: Settings → Developer → "Make template for <shape>" runs Image Playground with a neutral template prompt (mid-grey plain garment of that shape, same sentence style), and saves the result to `Application Support/templates/<shape>.jpg`; a saved template wins over a bundled one. Selection rule (pure, tested): template if one exists for the shape **and** the pattern is solid/textured (or missing); otherwise (stripe, check, graphic, embroidered, colourBlock, floral) the user's own cut-out, because a template would lose the print. The fabric swatch stays an optional extra concept (style "proven + swatch").
4. **Prompt = Austin's exact wording:** "Create a Front view e-commerce product photo of a {colour phrase} {fabric} {garment}, laid flat and symmetrical, plain light grey background, soft shadow, no person, no text." with garment words matching his ("tshirt" for t-shirts). Footwear and trousers keep their layout variants.
5. **Old tiles:** after this lands, run Settings → Refresh catalogue images so all non-product tiles use the 4:5 catalogue canvas (the grid currently mixes square and 4:5).

Tests:
- PS15 `ProductTemplate.shape(for:)` maps tshirt+short → tshirtShort, tshirt+long and sweater → tshirtLong, shirt → shirt, hoodie → hoodie, jacket/blazer → jacket, jeans/chinos/trousers → trousers, shorts → shorts, footwear → shoes, kurta/saree/dress → nil (no template yet).
- PS16 source selection: solid tee with a template → template; striped tee → cut-out; shape with no template → cut-out; saved template beats bundled.
- PS17 the default sentence for a black cotton tee equals Austin's wording with "black (#171D24) cotton tshirt".
- PS18 post-processing a synthetic generated image (garment on a grey backdrop) yields a 1200×1500 image whose corner pixel is #F4F4F2 (the backdrop is gone).
- PS19 the overlay state machine: idle → preparing → sheet → saving → idle; cancel from sheet returns to idle; failure shows an error and returns to idle.

## Capture and product photo fixes (15 Nov)

From Austin's iPhone test. Tests S2-FX01..FX07.
1. **White read as silver:** `ColorExtractor.classify` also calls light, cool or neutral tones white (L > 75, chroma < 14, b* < 5, so cream and beige still win; flagged ambiguous). Silver is never picked automatically (it stays in the colour menu). Light-to-mid neutrals are grey. The product prompt uses the colour name, so "silver sneakers" goes away.
2. **Fix a colour:** a Colour row (swatches, name menu of every `ColorName`) in the review and on item detail. The choice replaces `colorNames[0]` (`Item.setColour`; the hex stays, so the extracted name is still `classify(hex)`); an auto-built item name follows it. Not yet shown on the accuracy screen.
3. **Fit question** only for tops, bottoms, one-pieces and outerwear (`asksFit`), never footwear or accessories.
4. **When to wear it:** the chips were already editable (picker per field, user override wins). New plain-code rule after tagging (`ItemTags.refined`): leather or suede sneakers, loafers, flats and boots lose `athletic` (empty becomes casual). There is no sports-shoe subcategory, so no exception yet.
5. **Product photo after saving:** Save queues the item ids (`ReviewModel.takeProductQueue`); the screen that opened the review (wardrobe, item detail) runs `ProductShotSession.makeQueued` in the cover's `onDismiss`, one Image Playground sheet per item.
6. **Cut-out and AI together:** after Done one progress screen ("Cutting out and reading your clothes…", per-photo stage) runs cut-out and tagging; the review opens when all are done. Each photo waits at most 30 s for the AI (`tagTimeout`), then shows as failed with the manual questions. Unavailable model: same fallback.
7. **Product photo edges:** no second cut-out. `Catalogue.productFrame`: subject bounds from a mask (measurement only), 4:5 crop centred with 9% margin (padded with the backdrop if the photo is too tight), 1200x1500, per-channel gain so the border-median backdrop becomes `#F4F4F2`. No subject: centre-crop 4:5. The sheet now also sets `ImagePlaygroundOptions` (iOS 27): `sizeSpecification = .closest(to: 1200x1500)` and `creationStrategy = .editExisting` when a source image is passed, else `.automatic`.
