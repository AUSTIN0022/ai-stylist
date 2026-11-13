# Sprint 0: Proof

**Dates:** 10–13 Nov 2026 · **Planned:** 8 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.2, §5.3, §5.7

## Goal

Know, with numbers, whether Apple's on-device model can tag clothes well enough to build on. The spike screens are throwaway. The tagging prompts, the expected-tags file, the eval scorer and the result are kept and reused in Sprints 2 and 6.

**Tests first:** the eval scorer is test-driven. Cases, evals and the manual script are in [SPRINT_0_TESTS.md](SPRINT_0_TESTS.md).

## What must exist at the end

1. An Xcode project that runs on the iPhone 17.
2. 30 single-item photos of clothes that are in `wardrobe.json`.
3. A file of the correct tags for those 30 items.
4. A debug screen that tags all 30 and prints accuracy per field.
5. `docs/EVAL_SPRINT0.md` with the accuracy table and a written decision on the AI provider.

## Before you start

- iPhone 17 and MacBook both on OS 27, with **Apple Intelligence turned on** in Settings and the model fully downloaded (it downloads in the background after you turn it on; leave the phone on Wi-Fi and power).
- Xcode (the version that ships the iOS 27 SDK) installed, signed in with your Apple ID. A free personal team is enough for running on your own phone.
- API names below were checked against Apple's docs on 10 Nov 2026. Confirm each against the current docs as you write the code.

## Build steps

### 1. Project (1 h)
- **Done (13 Nov):** the project lives in `ai-stylist/`. `project.yml` is the source of truth; run `xcodegen generate` to create `AIStylist.xcodeproj` (git-ignored). App code goes in `App/` and app tests in `AppTests/`; both are synced folders, so new files need no project edits.
- Logic that can run without a phone goes in `Packages/StyleEngine` and is tested on the Mac with `swift test --package-path Packages/StyleEngine`.
- Austin: open the project in Xcode, set your team under Signing, and run the empty app on the phone once.

### 2. Test photos (1 h, you)
How to shoot, because the same rules go into the camera guide in Sprint 1:
- One garment per photo. Lay it flat on a bed or hang it on a door.
- Plain background that contrasts with the garment (dark shirt on a light sheet, white tee on a dark sheet).
- Daylight near a window, no flash, whole garment in frame, shot from straight above or straight on.
- Cover every category: about 8 shirts and polos, 4 tees, 7 pants, 5 shoes, 4 knits, 2 outerwear.
- Name each file with its id from `wardrobe.json`, for example `shirt_rust_mandarin.jpg`. Put them in `EvalPhotos/` and add that folder to the app target as a folder reference so the debug screen can read them.

### 3. Expected tags (1.5 h)
- Create `EvalPhotos/expected.json`: one object per photo with the fields from PRD §5.3 that you can state for certain: `category`, `subcategory`, `colors`, `pattern`, `fabric`, `fit`, `collar`, `sleeve`, `dressCodes`.
- Map the free text in `wardrobe.json` to the PRD's fixed values by hand. Example: "rust-orange / terracotta" → `["rust"]`; "Mandarin collar with open V placket" → `mandarin`; "Lightweight cotton-linen look" → `cottonLinen`.
- Where you are not sure of the true value (fabric of a shoe), leave the field out so it is not scored.

### 4. Cut-out spike (1.5 h)
- One function: `UIImage` in → cut-out `CGImage` out, using Vision's foreground instance mask request (`GenerateForegroundInstanceMaskRequest`, or the older `VNGenerateForegroundInstanceMaskRequest` with `generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`), all instances, cropped to the subject.
- A screen that shows the original next to the cut-out on white for each test photo.

### 5. Tagging spike (1.5 h)
Three calls per item, each a fresh `LanguageModelSession` so the context starts empty:

```swift
@Generable
struct IdentityTags {
    @Guide(description: "The main kind of clothing item shown")
    var category: Category
    var subcategory: Subcategory
    var styleOrigin: StyleOrigin
}

func tagIdentity(_ image: CGImage) async throws -> IdentityTags {
    let session = LanguageModelSession(
        instructions: "You label one clothing item in a photo. Choose only from the allowed values."
    )
    let response = try await session.respond(
        generating: IdentityTags.self,
        options: GenerationOptions(samplingMode: .greedy)
    ) {
        "Label the clothing item in this image."
        Attachment(image)
    }
    return response.content
}
```

- **Call A, identity:** category, subcategory, styleOrigin.
- **Call B, construction:** fabric, pattern, fit, collar, sleeve.
- **Call C, usage:** dressCodes, formality, seasons, caption.
- Send the **cut-out on white**, not the original photo. Downscale so the long side is about 768 px.
- Write the enums inline for now; they move to the real taxonomy file in Sprint 1.
- Check `SystemLanguageModel.default.availability` first and print the reason if it is not available.

### 6. Eval (2 h)
- A debug button "Run eval": for each photo, cut out, run A, B, C, time each call, compare with `expected.json`.
- Scoring: single-value fields are right or wrong. List fields (`colors`, `dressCodes`) count as right if the first expected value is in the answer.
- Print one row per item and a summary: accuracy per field, median and worst seconds per item.
- Run it twice. With greedy sampling the answers should be identical; note it if they are not.

### 7. Two quick checks (1 h)
- Run the eval once at 512 px and once at 1024 px long side. Note accuracy and speed for each.
- Try the same code in the iOS simulator on the Mac and note whether the model and the cut-out work there.

## Expected behaviour

- The app launches on the phone and reports the model as available.
- Each cut-out shows only the garment, cropped tight.
- Each item takes roughly 5–10 seconds for the three calls.
- The summary prints accuracy per field for 30 items.

## Decision rule

| Result | Decision |
|---|---|
| category ≥ 95%, collar/sleeve/pattern ≥ 85%, fabric ≥ 75% | Stay on-device. Continue as planned |
| Fabric between 65% and 75% | Stay on-device. Fabric is marked "check this", and label scan (Sprint 1b) supplies the real value when the item has a label |
| Only fabric below target | Stay on-device. Fabric is always marked "check this" on the review screen |
| Category or collar below target after two rounds of prompt fixes | Tagging moves to Gemini Flash free tier in Sprint 2; intent and notes stay on-device |
| Colour | Not measured this sprint. The model is never asked for colour; it comes from code in Sprint 1. Keep `colors` in `expected.json` for that |

Write the decision as the first line of `docs/EVAL_SPRINT0.md`, then the table, then the image size you chose.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Model reports unavailable | Apple Intelligence off, model still downloading, or device language/region not supported | Turn it on in Settings, wait on Wi-Fi and power, set device language to English; print the availability reason instead of guessing |
| Error about context or size when an image is attached | Image uses too much of the 4K context | Downscale to 512–768 px; keep prompts to one sentence; one call per session |
| Model refuses or errors on a photo | A person or face is in the frame, or the guardrail misreads the image | Send the cut-out, not the original; reshoot without a person |
| Every item comes back as "shirt" | Too many choices, no guidance | Add `@Guide` descriptions; in call B ask only the fields that apply to the category from call A |
| Mandarin collar tagged as spread | Detail lost at small size | Raise to 1024 px for call B only; add a one-line description of each collar type to the prompt |
| Cut-out is empty or includes the bed sheet | Low contrast between garment and background | Reshoot on a contrasting background; this becomes the capture guide rule |
| Cut-out fails only in the simulator | The mask request may need a real device | Test on the phone; note it in the eval file |
| More than 15 s per item | Image too large or model cold | Smaller image; call the session's prewarm before the loop |
| Two runs give different tags | Sampling not greedy | Pass `GenerationOptions(samplingMode: .greedy)` on every call |

## Checklist

- [ ] App builds and runs on the iPhone 17
- [ ] Model availability is printed, with a reason when unavailable
- [ ] 30 test photos in `EvalPhotos/`, named by `wardrobe.json` id
- [ ] `expected.json` covers all 30
- [ ] Cut-out works on at least 27 of 30
- [ ] Eval prints per-field accuracy and timing
- [ ] 512 px vs 1024 px compared
- [ ] Simulator result noted
- [ ] `docs/EVAL_SPRINT0.md` written with the decision on line 1
- [ ] Nothing in `EvalPhotos/` is committed

## How it lands

- Branch `sprint-0`. Commit the project, the spike code and `docs/EVAL_SPRINT0.md`.
- Merge to `main` and tag `sprint-0-done`.
- The spike screens can stay behind a debug menu; Sprint 1 replaces them.

## Not this sprint

The data model, the wardrobe UI, the review screen, the engine, Gemini code (unless the decision rule requires it).
