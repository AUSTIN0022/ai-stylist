# Sprint 1: Capture and cut-out

**Dates:** 16–22 Nov 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.2 steps 1–4, §5.3, §6, P0-1 to P0-4, P0-8 (grid only), P0-18

## Goal

A photo becomes a clean, white-background wardrobe entry with exact colours, saved on the phone. No AI tagging yet.

## Needs from earlier sprints

- The Xcode project and the cut-out function from Sprint 0.
- The image size chosen in `docs/EVAL_SPRINT0.md`.

## What must exist at the end

| Piece | Behaviour |
|---|---|
| Data model | Items, outfits and logs persist across app restarts |
| Taxonomy | One file of fixed values used by the model, the UI and the engine |
| Add flow | Pick up to 20 photos, or shoot several in a row with the camera |
| Quality check | Bad photos are flagged with the reason |
| Cut-out | Transparent PNG and white-background JPEG per item |
| Colour | 1–3 hex colours and their names per item, from code |
| Wardrobe tab | Grid of items by category; tap for detail; delete |

## Project layout

```
ai-stylist/
  project.yml               XcodeGen spec (run `xcodegen generate`)
  App/                      SwiftUI app target
    Models/                 SwiftData @Model classes
    Capture/                picker, camera, quality check
    Imaging/                CutoutService, ColorExtractor, ImageStore
    Wardrobe/               grid, item detail
  Packages/StyleEngine/     local Swift package
    Sources/StyleEngine/Taxonomy.swift     enums (this sprint)
    Sources/StyleEngine/...                engine (Sprint 3)
    Tests/StyleEngineTests/
```

The taxonomy lives in the package so the engine can use it without importing the app.

## Build steps

### 1. Taxonomy (1 h)
- `Taxonomy.swift`: one enum per field in PRD §5.3 (`Category`, `Subcategory`, `StyleOrigin`, `SetRole`, `ColorName`, `Pattern`, `Fabric`, `Fit`, `Length`, `Collar`, `Sleeve`, `DressCode`, `Season`, `Statement`).
- Each is `String`-backed, `Codable`, `CaseIterable`, `Sendable` and `@Generable`, with a `displayName`.
- A function `subcategories(for: Category)` and `fields(for: Category)` (footwear has no collar or sleeve; tops have no `closedToe`).
- Replace the inline enums from the Sprint 0 spike with these.

### 2. Data model (2 h)
SwiftData `@Model` classes, fields as in PRD §5.3:
- `Item`: id, createdAt, status (`tagging`, `ready`, `failed`, `archived`), name, caption, `aiRawData: Data?`, `userOverridesData: Data?`, `hexColors: [String]`, `colorNames: [String]`, `setGroupId: UUID?`, `setRole`, three image file names, `taggerVersion`, `lastWornAt`, `cutoutFailed`, `lastError`, `featurePrintData: Data?` (filled in Sprint 6; declared now so the store does not change later).
- `Outfit`, `OutfitItem`, `WearLog`, `AIRequestLog`, `FeedbackEvent` with the fields from the PRD. They are created now and used in later sprints, so the store never needs a migration mid-plan.
- Tags are stored as one JSON blob of a `Codable` struct `ItemTags` (defined in the package), not as separate columns. Colours are separate because code writes them.
- `ImageStore`: saves and deletes files under `Application Support/items/<id>/` (`original.jpg`, `cutout.png`, `display.jpg`). The database stores file names only.

### 3. Capture (2.5 h)
- **Photos:** `PhotosPicker` with `maxSelectionCount: 20`, images only. Load each as data, fix orientation, keep full resolution for the original.
- **Camera:** an in-app camera sheet with a rounded-rectangle framing guide and one line of text: "One item, plain background, good light". A shutter button that stays open for the next shot and a thumbnail strip of what has been taken. "Done" sends all shots to the pipeline.
- Add the camera and photo-library usage descriptions to Info.plist.

### 4. Quality check (1.5 h)
Run on a downscaled copy before the cut-out. Return `.ok` or one reason:

| Check | How | Flag when |
|---|---|---|
| Too dark | Mean luminance of the image (Core Image area average) | Below a threshold you set from the 30 test photos |
| Blurry | Variance of an edge filter (Laplacian) over the image | Below a threshold set the same way |
| No clear item | Area of the foreground mask as a share of the frame | Mask missing, or under about 8% of the frame |
| Item cut off | Mask touches two or more frame edges | True |

Flagged photos are not blocked: the user sees the reason and chooses **Retake** or **Use anyway**.

### 5. Cut-out service (2 h)
- Move the Sprint 0 function into `CutoutService`. Input: original image. Output: transparent `cutout.png` cropped to the garment with a small margin, and `display.jpg` (the cut-out centred on white, square, about 1024 px).
- If the mask has several instances, merge them (a shoe pair is two instances).
- On failure: `display.jpg` is the original, centre-cropped; the item gets `cutoutFailed = true` so the UI can offer a retake.

### 6. Colour extractor (1.5 h)
- Input: the cut-out. Ignore transparent pixels and the outer 2 px of the mask edge.
- Downscale to about 64 px, convert pixels to Lab, run k-means with k = 4, keep clusters above 15% of pixels, at most 3, largest first.
- Output each cluster centre as hex. Map each to the nearest `ColorName` using a fixed table of reference Lab values; `multicolor` if more than 3 clusters pass the threshold.
- Unit tests on saved cut-outs from the eval set.

### 7. Wardrobe tab (1.5 h)
- Grid of `display.jpg` thumbnails, sections by category. Until tagging exists, new items sit in an "Unsorted" section.
- Item detail: large image, colour swatches with hex and name, delete button.
- Delete removes the row and the item's folder.

## Expected behaviour

- Picking 20 photos shows 20 placeholders at once; each fills in with its cut-out within about a second or two.
- A photo taken in a dim room shows "Too dark" with Retake and Use anyway.
- Every item in the grid has the same white background and similar framing.
- The rust shirt shows a rust swatch; the check shirt shows two or three swatches.
- After force-quitting and reopening, every item and image is still there.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Photos appear rotated | EXIF orientation ignored when converting to `CGImage` | Normalise orientation once, right after loading |
| App memory spikes or crashes on 20 photos | All full-size images held in memory | Process one at a time; write to disk and release; show thumbnails only |
| Good photos flagged as blurry | Threshold tuned on too few photos; plain fabric has few edges | Measure blur inside the mask only; lower the threshold; when unsure, do not flag |
| White halo or dark fringe around the garment | Mask edge is soft | Erode the mask by 1–2 px before compositing |
| Cut-out includes the hanger or a hand | Vision treats it as part of the subject | Capture guide says "no hanger in frame"; user can retake |
| White tee on white sheet gives an empty cut-out | No contrast | "No clear item" flag fires; guide text asks for a contrasting background |
| Colour reads "grey" for a black item | Glare or shadow dominates the cluster | Use the largest cluster; widen the black range in the reference table |
| Navy reads as black | Reference values too close | Tune the reference table against the eval photos; hex stays exact either way |
| Shoes cut out as one shoe | Only the first mask instance used | Merge all instances |
| Images missing after reinstall | Expected: reinstall wipes app data | Not a bug; export arrives in Sprint 5 |

## Tests

**Tests first.** Write the cases in [SPRINT_1_TESTS.md](SPRINT_1_TESTS.md) before the code for each build step. That file has the full unit, integration, eval and manual cases and the exit gate; the list below is only a summary.

- Colour: rust shirt → `rust` or `orange`; navy shirt → `navy`; cream knit → `cream`; terracotta check → at least 2 colours.
- Quality: one known dark photo and one known blurry photo return the right reason; five good photos return `.ok`.
- `ImageStore`: save then delete leaves no files.

## Checklist

- [ ] Taxonomy file complete and used by the Sprint 0 tagging code
- [ ] All six models created; app restarts keep data
- [ ] 20-photo pick works without a memory warning
- [ ] Camera takes several shots in a row
- [ ] Each quality reason shows for a matching bad photo
- [ ] At least 9 of 10 cut-outs have clean edges
- [ ] Colour tests pass
- [ ] Grid and item detail work; delete removes files
- [ ] Database stores file names only, no image data

## How it lands

- Branch `sprint-1`, merge to `main`, tag `sprint-1-done`.
- Demo: record a 30-second screen capture of adding 5 items from the camera and scrolling the grid. Save it outside the repo; it is also content for later.

## Not this sprint

AI tags, review screen, filters and search, outfits.
