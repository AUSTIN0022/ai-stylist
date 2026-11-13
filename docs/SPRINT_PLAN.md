# Sprint Plan: Wardrobe + AI Stylist MVP

Written 10 Nov 2026. Spec: [PRD_MVP.md](PRD_MVP.md).

This file is the summary. The full build detail for each sprint (steps, expected behaviour, what can go wrong and the fix, tests, checklist) is in [sprints/](sprints/): [0](sprints/SPRINT_0.md) · [1](sprints/SPRINT_1.md) · [2](sprints/SPRINT_2.md) · [3](sprints/SPRINT_3.md) · [4](sprints/SPRINT_4.md) · [5](sprints/SPRINT_5.md) · [6](sprints/SPRINT_6.md). Where the two differ, the sprint file wins.

Testing: [TEST_PLAN.md](TEST_PLAN.md) sets the rules (tests first, evals, exit gate). Each sprint has a matching `sprints/SPRINT_N_TESTS.md` with its test cases, evals and manual script.

## Assumptions (change these first if wrong)

- **Team:** Austin, solo, alongside the job search.
- **Capacity:** about 15 hours a week, planned to 12 (80%). If your real number is different, scale the dates, not the scope.
- **Sprint length:** 1 week, Monday to Sunday. Sprint 0 is a 4-day spike.
- **Hardware:** iPhone 17 and MacBook, both on OS 27 with Apple Intelligence turned on.
- **Estimates** are hours of your time when pairing with a coding model, not model time.

## Overview

| Sprint | Dates | Goal | Planned |
|---|---|---|---|
| 0 | 10–13 Nov | Prove on-device tagging on real photos and choose the AI provider | 8 h |
| 1 | 16–22 Nov | A photo becomes a clean cut-out with exact colours, saved in a wardrobe | 12 h |
| 1b | 13–16 Nov | Fixes from the first device test: subject choice, working camera box, black rule, review step, label scan ([SPRINT_1B.md](sprints/SPRINT_1B.md)) | 10 h |
| 2 | 23–29 Nov | Every item is tagged automatically and can be corrected | 12 h |
| 3 | 30 Nov–6 Dec | The engine builds correct outfits from `wardrobe.json`, with tests | 12 h |
| 4 | 7–13 Dec | Type an occasion, get outfit cards, save them | 12 h |
| 5 | 14–20 Dec | Build outfits by hand; wear log and feedback improve results | 12 h |
| 6 | 21–27 Dec | Whole wardrobe loaded, used daily, rough edges fixed | 12 h |

**Go/no-go gates**
- **End of Sprint 0:** on-device accuracy meets the PRD targets → continue on-device. Misses on fabric only → continue, mark fabric "check this". Misses on category or collar → switch tagging to Gemini Flash free tier before Sprint 2.
- **End of Sprint 3:** fewer than 2 of 3 wearable outfits on the 10 test occasions → spend Sprint 4 on engine rules and push everything else a week.

## Which model to use for which work

| Work | Model | Why |
|---|---|---|
| Engine design, scoring rules, tagging prompts, schema changes, debugging wrong outfits | Opus 5.5 | Judgment-heavy; mistakes are expensive |
| SwiftUI screens, pipeline wiring, SwiftData, drag and drop | Sonnet 5.5 | Bulk of the code, well-specified |
| Enum and fixture boilerplate, converting `wardrobe.json`, test tables, copy text | Haiku 5.5 | Mechanical |
| Re-planning, PRD changes | Fable 5.2 | Only when scope changes |

Start each coding session by pointing the model at PRD_MVP.md and the one sprint section below, not the whole repo.

---

## Sprint 0: Proof (10–13 Nov)

**Goal:** know, with numbers, whether the on-device model can tag clothes well enough.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | Create the Xcode project (SwiftUI, iOS 27, iPhone), run on the iPhone 17 | 1 h | Sonnet |
| P0 | Take 30 single-item photos of clothes that are in `wardrobe.json` | 1 h | you |
| P0 | Throwaway screen: pick photo → Vision cut-out → show on white | 1.5 h | Sonnet |
| P0 | Draft the three `@Generable` tagging structs and prompts (PRD §5.2) | 1.5 h | Opus |
| P0 | Eval: run all 30, print a table of predicted vs expected per field, with accuracy and seconds per item | 2 h | Sonnet |
| P1 | Try two image sizes and note token use and speed | 0.5 h | you |
| P1 | Check whether the model runs in the simulator on the Mac | 0.5 h | you |

**Checklist**
- [ ] App builds and runs on the phone
- [ ] `SystemLanguageModel` reports available; the unavailable case prints a clear reason
- [ ] 30 test photos in a folder, each named with its `wardrobe.json` id
- [ ] Expected-tags file written for those 30 items (hand-map the JSON's free text to the PRD enums)
- [ ] Accuracy table saved to `docs/EVAL_SPRINT0.md`
- [ ] Provider decision written at the top of that file

**Risk:** the expected-tags file takes longer than the code. Keep it to the 30 photographed items.

---

## Sprint 1: Capture and cut-out (16–22 Nov)

**Goal:** a photo becomes a clean, white-background wardrobe entry with exact colours.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | SwiftData models: Item, Outfit, OutfitItem, WearLog, AIRequestLog, FeedbackEvent (PRD §5.3) | 2 h | Opus for schema, Sonnet to write |
| P0 | Taxonomy enums as one file, each `Codable`, `CaseIterable` and `@Generable` | 1 h | Haiku |
| P0 | Photos multi-select (up to 20) and in-app camera with framing guide | 2.5 h | Sonnet |
| P0 | Quality check: dark, blurry, no subject, with the reason shown | 1.5 h | Sonnet |
| P0 | Cut-out service: mask → crop → transparent PNG + white JPEG; keep original on failure | 2 h | Sonnet |
| P0 | Colour extractor: top 1–3 hex from cut-out pixels → named palette | 1.5 h | Opus |
| P0 | Wardrobe grid by category, item detail with image | 1.5 h | Sonnet |
| P2 | Live camera hint ("move closer", "more light") | stretch | Sonnet |

**Checklist**
- [ ] 20 photos picked at once all end up in the wardrobe
- [ ] A dark photo and a blurry photo are each flagged with the right reason
- [ ] Cut-outs are cropped tight and have no background fringe on at least 9 of 10 test photos
- [ ] Colour test: rust shirt → orange/rust, navy shirt → navy, cream knit → cream (unit test on saved cut-outs)
- [ ] Images are stored as files; the database holds paths only
- [ ] Deleting an item removes its three image files

**Risk:** light clothes on light backgrounds cut out badly. Mitigation: the framing guide says "plain, contrasting background"; the original photo is the fallback.

---

## Sprint 2: Tagging and editing (23–29 Nov)

**Goal:** every item is tagged with no typing, and any wrong tag is fixed in one tap.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | `ItemTagger` protocol and the Foundation Models implementation (calls A, B, C) | 2.5 h | Opus |
| P0 | Background tagging queue: one item at a time, tagging → ready or failed, retry | 2 h | Sonnet |
| P0 | `aiRaw` and `userOverrides` storage and the merged "effective tags" accessor | 1 h | Sonnet |
| P0 | Review screen: tag chips, picker per field, "check this" highlight | 2.5 h | Sonnet |
| P0 | Auto-name ("Rust mandarin-collar linen shirt") | 0.5 h | Haiku |
| P0 | Filters (category, colour, dress code, season) and search | 1.5 h | Sonnet |
| P0 | AIRequestLog row per call | 0.5 h | Sonnet |
| P0 | Model-unavailable state with manual tagging | 1 h | Sonnet |
| P1 | Re-run tagging from item detail | 0.5 h | Sonnet |

**Checklist**
- [ ] Sprint 0 eval re-run inside the real pipeline; accuracy not worse than Sprint 0
- [ ] Editing a tag changes `userOverrides` only; `aiRaw` is byte-identical before and after
- [ ] Re-tagging replaces `aiRaw` and keeps the user's overrides
- [ ] Killing the app mid-queue and reopening resumes the untagged items
- [ ] With Apple Intelligence off, an item can still be added and tagged by hand
- [ ] Median time from photo to ready ≤ 20 s on the phone

**Risk:** tagging 20 items in a row heats the phone or gets slow. Mitigation: sequential queue, show progress, let the user leave the screen.

---

## Sprint 3: StyleEngine (30 Nov–6 Dec)

**Goal:** given an intent and a wardrobe, the engine returns outfits you would wear, proven by tests, with no UI and no AI.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | Engine value types in the `StyleEngine` package (the package itself is created in Sprint 1 for the taxonomy) | 0.5 h | Sonnet |
| P0 | Convert `wardrobe.json` to a test fixture in the PRD schema (42 items) | 1.5 h | Haiku, you review |
| P0 | Occasion table: occasion → dress codes, formality range, flags, colour boosts | 1.5 h | Opus |
| P0 | Filter stage with reason codes | 1.5 h | Sonnet |
| P0 | Formulas, including sets as one multi-slot unit | 2 h | Opus |
| P0 | Hard checks and scoring (colour harmony table, formality, statement limit, repetition) | 3 h | Opus |
| P0 | Tests: 10 occasions with expected properties | 2 h | Sonnet |
| P1 | Daily seed for stable-per-day variety | stretch | Sonnet |

**Checklist**
- [ ] Diwali, evening, indoor → rust mandarin shirt + black chinos (or brown linen) appears in the top 3
- [ ] Same with `fireworks` flag → no open-toe footwear in any result
- [ ] Interview → light blue oxford with straight chinos; no graphic tees, no slides
- [ ] Hot day → no knitwear, no corduroy; cold evening → knit or outerwear present
- [ ] Never two statement or patterned pieces in one outfit
- [ ] A kurta set in the fixture comes out as one unit with footwear
- [ ] Wardrobe with no footwear → result names the missing slot
- [ ] Asking for the next 3 excludes the first 3
- [ ] All tests run in under 2 seconds on the Mac

**Risk:** rules that look right on one wardrobe fail on others. Mitigation: keep the occasion and colour tables as data so they can be tuned without code changes; test on borrowed wardrobes in Sprint 6.

---

## Sprint 4: Stylist chat (7–13 Dec)

**Goal:** type an occasion and get three outfit cards from your own clothes, then save one.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | `IntentParser`: text + recent turns → `OccasionIntent` via `@Generable` | 2 h | Opus |
| P0 | Stylist tab: text box, occasion chips, results list | 2.5 h | Sonnet |
| P0 | Outfit card: cut-outs in a fixed layout with item names | 2.5 h | Sonnet |
| P0 | Stylist note call on the top 3 (text rows in, 1–2 sentences each out, IDs validated) | 1.5 h | Opus |
| P0 | Another option and swap a piece, no LLM call | 1.5 h | Sonnet |
| P0 | Save outfit; Outfits tab list and detail | 2 h | Sonnet |
| P1 | "Style this item" from item detail | stretch | Sonnet |

**Checklist**
- [ ] 15 test sentences parse to the expected occasion and dress code (table in the test target)
- [ ] "Make it more casual" after a result lowers formality and keeps the occasion
- [ ] "No jeans" removes jeans from the next results
- [ ] A note never mentions an item that is not in its outfit
- [ ] Text in, cards out in ≤ 4 s
- [ ] Occasion chips work with the model unavailable
- [ ] A saved outfit survives an app restart with all images

**Risk:** the small model returns a wrong occasion for vague text. Mitigation: show the parsed intent as editable chips above the results ("Festival · evening · indoor"), so one tap corrects it.

---

## Sprint 5: Manual builder and memory (14–20 Dec)

**Goal:** build an outfit by hand, and have the app learn from what you save, wear and reject.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | Outfit builder: canvas, item drawer by category, drag in, move, resize, remove | 4 h | Sonnet |
| P0 | Save and reopen a manual outfit with its layout | 1 h | Sonnet |
| P1 | Mark worn; WearLog; freshness in engine scoring | 1.5 h | Sonnet |
| P1 | FeedbackEvent on save, reject and swap → pair weights | 2 h | Opus |
| P1 | Set-linking UI (select items → "these are one set") | 1.5 h | Sonnet |
| P1 | Export wardrobe as JSON; import for test builds | 1 h | Haiku |
| P1 | Settings: AI status, counts, delete all data | 1 h | Sonnet |

**Checklist**
- [ ] Drag four items onto the canvas, rearrange, save, reopen: same layout
- [ ] A manual outfit appears on the Outfits tab next to AI ones
- [ ] An outfit worn today does not appear in tomorrow's top 3 for the same occasion
- [ ] After saving the same pair three times, that pair ranks higher
- [ ] A linked kurta set is always suggested together
- [ ] Delete all data leaves no image files behind

**Risk:** drag and drop eats the sprint. Mitigation: if it is not working by hour 5, ship "tap to add to slot" with a fixed layout and move free-form dragging to Sprint 6.

---

## Sprint 6: Own use and fixes (21–27 Dec)

**Goal:** your whole wardrobe is in the app and you use it every day.

| Pri | Item | Est | Model |
|---|---|---|---|
| P0 | Photograph and add every item you own | 3 h | you |
| P0 | Run the 10-occasion rating sheet; tune occasion and colour tables | 3 h | Opus |
| P0 | Fix the top 5 annoyances from daily use | 3 h | Sonnet |
| P1 | Duplicate check on add (image feature print) | 1.5 h | Sonnet |
| P1 | Weather from Open-Meteo for today's `weatherFeel` | 1 h | Sonnet |
| P1 | Add 10–15 borrowed photos of women's and Indian garments; record tag accuracy | 1.5 h | you |
| P2 | TestFlight build for 3–5 friends (needs the paid Apple developer account) | stretch | you |

**Checklist**
- [ ] All PRD success metrics measured and written to `docs/EVAL_MVP.md`
- [ ] 2 of top 3 wearable on all 10 occasions
- [ ] No crash in 7 days of use
- [ ] 14-day use streak started
- [ ] Decision written down: what the next build is (cross-platform plan, wedding planner, or stop)

---

## Risks across the plan

| Risk | Impact | Mitigation |
|---|---|---|
| On-device model too weak on collar, fabric or Indian garments | Wrong tags, bad outfits | Sprint 0 gate; Gemini free tier as the second tagger; review screen makes fixes one tap |
| 4K context too small once an image is attached | Tagging calls fail or truncate | Three small calls; downscale the cut-out; measured in Sprint 0 |
| iPhone-only prototype cannot become the India product | Rework later | Taxonomy, schema and engine rules kept as data tables; decision forced at the end of Sprint 6 |
| Job search takes the hours | Dates slip | Scope is fixed per sprint; slip the date, never stack two sprints |
| Engine tuned to one men's wardrobe | Poor results for others | Borrowed-photo test in Sprint 6 before anyone else uses it |

## Definition of done (every sprint)

- [ ] Runs on the iPhone 17, not only the simulator
- [ ] Tests were written before the code for every build step (see [TEST_PLAN.md](TEST_PLAN.md) §2)
- [ ] The sprint's exit gate in `sprints/SPRINT_N_TESTS.md` is met: automated tests green, evals recorded and at pass mark, manual script passed, results row filled in
- [ ] No paid API key anywhere; no key of any kind committed
- [ ] Sprint checklist ticked in this file, with a one-line note for anything carried over
- [ ] Committed on a branch and merged to main
