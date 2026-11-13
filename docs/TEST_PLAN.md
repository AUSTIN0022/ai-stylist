# Test Plan: Wardrobe + AI Stylist MVP

Written 10 Nov 2026. Spec: [PRD_MVP.md](PRD_MVP.md). Sprints: [SPRINT_PLAN.md](SPRINT_PLAN.md).
Per-sprint test cases: [0](sprints/SPRINT_0_TESTS.md) · [1](sprints/SPRINT_1_TESTS.md) · [2](sprints/SPRINT_2_TESTS.md) · [3](sprints/SPRINT_3_TESTS.md) · [4](sprints/SPRINT_4_TESTS.md) · [5](sprints/SPRINT_5_TESTS.md) · [6](sprints/SPRINT_6_TESTS.md)

## 1. Four kinds of checking

| Kind | What it proves | Who runs it | When |
|---|---|---|---|
| **Unit test** | One function or type behaves as specified | Automated, on the Mac | On every change |
| **Integration test** | Several pieces work together (pipeline, database, engine) with fake AI | Automated, on the Mac or simulator | Before every merge |
| **Eval** | The real AI model is accurate enough on real photos and sentences | Automated run on the iPhone, result read by you | When a prompt, image size or model changes, and at each sprint end that lists one |
| **Manual test** | The app feels and looks right in the hand | You, on the iPhone 17 | End of every sprint |

Unit and integration tests must give the same answer every time. The AI model does not, strictly, so it never runs inside them: it is replaced by a fake. The model's quality is measured separately by evals, which have a pass mark instead of pass/fail per case.

## 2. Test-driven development: the working rule

For every build step in a sprint file:

1. **Red.** Write the test cases listed for that step in the sprint's test file. Run them. They must fail (or not compile) for the right reason.
2. **Green.** Write the least code that makes them pass.
3. **Refactor.** Tidy with the tests still passing.
4. **Commit** test and code together, with the test IDs in the message (`S2-U03..U07: tag merge`).

A coding session is given the sprint file and its test file together, and told: tests first.

**What cannot be test-driven, and what covers it instead**

| Thing | Why not | Covered by |
|---|---|---|
| SwiftUI layout and visuals | No stable assertion for "looks right" | Manual test, plus pure layout functions that are unit-tested |
| Camera capture | Needs hardware | Manual test |
| Drag and pinch gestures | Unreliable to automate | Manual test, plus unit tests on the state they change |
| AI model accuracy | Not deterministic, not ours | Evals |
| Vision cut-out quality | Needs a real device and real photos | Cut-out eval and manual test |

## 3. Tooling

| Need | Choice |
|---|---|
| Unit and integration tests | Swift Testing (`import Testing`, `@Test`, `#expect`) |
| Package tests | `swift test --package-path Packages/StyleEngine` |
| App tests | `xcodebuild test -project AIStylist.xcodeproj -scheme AIStylist -destination 'platform=iOS Simulator,name=iPhone 17'` |
| UI smoke tests | XCUITest, one or two per sprint, launched with `-uiTesting` |
| Evals | A separate test plan named `Evals` in the app's test target, run on the iPhone only |
| Continuous integration | None. Solo project: run both commands before each merge. Add CI when a second person joins |

**Test seams the code must have** (build these as you go; they are small):

| Seam | Purpose |
|---|---|
| `ItemTagger`, `IntentParser`, `NoteWriter` protocols | Real implementation in the app, `Fake…` versions in tests that return canned answers, throw, or wait |
| `CutoutProviding` protocol | A fake that returns a prepared cut-out so pipeline tests run on the Mac |
| In-memory SwiftData container | Every database test starts empty and leaves nothing behind |
| `ImageStore(root:)` | Tests pass a temporary folder |
| `today` passed in, never read from the system clock inside logic | Wear and freshness tests can set the date |
| `-uiTesting` launch argument | Uses the in-memory store, fake AI and a seeded fixture wardrobe |

## 4. Test data

| Data | Where | Used by |
|---|---|---|
| `wardrobe.json` fixture, 42 items plus a kurta set, in the PRD schema | `Packages/StyleEngine/Tests/StyleEngineTests/Fixtures/` | Engine tests, UI seed |
| No-footwear fixture | same folder | Missing-slot tests |
| Synthetic images made in code (solid colour, two-colour, black, blurred, sharp) | Built inside tests | Colour and quality unit tests |
| 30 eval photos + `expected.json` | `EvalPhotos/`, git-ignored | Tagging, colour and cut-out evals |
| 5 saved cut-outs from the eval set | App test resources | Colour regression tests |
| Intent sentences and expected intents | `AppTests/Evals/intent_cases.json` | Intent eval |
| 10 rating occasions | [SPRINT_6_TESTS.md](sprints/SPRINT_6_TESTS.md) | Engine rating |

The eval photos are personal and never committed. Everything else is.

## 5. Evals

Each eval writes a dated section to its result file. A result is compared with the pass mark and with the previous recorded run.

| ID | Measures | Data | Pass mark | First run | Re-run | Result file |
|---|---|---|---|---|---|---|
| **E-TAG** | Tag accuracy per field, on-device model | 30 photos vs `expected.json` | category ≥ 95%; subcategory ≥ 85%; collar, sleeve, pattern ≥ 85%; fit ≥ 75%; fabric ≥ 75%; dress code (first expected value present) ≥ 80% | Sprint 0 | Sprints 2 and 6, and after any prompt or image-size change | `docs/EVAL_SPRINT0.md`, `EVAL_SPRINT2.md`, `EVAL_MVP.md` |
| **E-CUT** | Cut-out success | 30 photos, judged by eye: garment only, tight crop, no fringe | ≥ 27 of 30 | Sprint 0 | Sprints 1 and 6 | same |
| **E-COL** | Colour from code | 30 cut-outs vs first expected colour | ≥ 90% first colour correct | Sprint 1 | Sprint 6 | `docs/EVAL_SPRINT1.md` |
| **E-SPEED** | Seconds per item, photo to ready | 30 photos | median ≤ 20 s, tagging ≤ 10 s, worst ≤ 40 s | Sprint 0 (tagging only) | Sprints 2 and 6 | with E-TAG |
| **E-DET** | Same input gives same tags | 10 photos, tagged twice | 100% identical | Sprint 0 | Sprint 2 | with E-TAG |
| **E-INT** | Occasion sentences parsed correctly | 15 sentences, 5 follow-ups | ≥ 13 of 15 with correct occasion and dress code; ≥ 4 of 5 follow-ups | Sprint 4 | Sprint 6 | `docs/EVAL_SPRINT4.md` |
| **E-NOTE** | Stylist notes stay truthful | 10 requests × 3 notes | 0 notes shown that mention an item outside the outfit; ≥ 80% of notes pass validation | Sprint 4 | Sprint 6 | same |
| **E-ENG** | Outfits are wearable | 10 occasions, top 3 each, rated by you | ≥ 2 of 3 wearable on every occasion | Sprint 3 (fixture) | Sprint 6 (real wardrobe) | `docs/EVAL_ENGINE.md`, `EVAL_MVP.md` |

**Rules for evals**
- An eval never runs as part of the normal test command; it needs the phone and takes minutes.
- **Regression rule:** a field that drops more than 5 points below its last recorded value blocks the sprint, even if it is still above the pass mark, until the cause is known.
- When a prompt or `@Generable` struct changes, bump the tagger version and re-run E-TAG before merging.
- With 30 photos, one wrong answer moves a field by about 3 points. Treat small differences as noise; that is why the regression rule uses 5.
- E-TAG scoring: single-value fields are right or wrong. List fields count as right when the first expected value is in the answer. Fields missing from `expected.json` are not scored.

## 6. Sprint exit gate

A sprint is done only when all four hold. Record them in the results table at the bottom of that sprint's test file.

1. Every automated test listed for the sprint exists and passes, and all earlier sprints' tests still pass.
2. Every eval listed for the sprint is run, recorded, and at or above its pass mark (or the miss has a written decision).
3. Every step of the manual test script passes on the iPhone 17.
4. No open defect of severity 1 or 2.

| Severity | Meaning | Rule |
|---|---|---|
| 1 | Crash, lost data, or a wrong item deleted | Fix before anything else |
| 2 | A P0 requirement does not work | Fix before the sprint closes |
| 3 | Works but is awkward or looks wrong | Log in `docs/DOGFOOD_NOTES.md`; fix in Sprint 6 if in the top five |

A bug found by hand gets a failing automated test first, then the fix, when it is in testable logic.

## 7. Requirement coverage

Every P0 requirement in the PRD and the tests that prove it. IDs are in the per-sprint files: `U` unit, `I` integration, `UI` smoke, `M` manual step, `E-` eval.

| Requirement | Proven by |
|---|---|
| P0-1 Capture from camera and Photos | S1-I04, S1-M02, S1-M03 |
| P0-2 Photo quality check | S1-U14 to U19, S1-M04 |
| P0-3 Cut-out on white | S1-I01 to I03, E-CUT, S1-M05 |
| P0-4 Exact colour | S1-U06 to U13, E-COL |
| P0-5 AI tagging | S2-U13 to U20, S2-I01, E-TAG, E-SPEED |
| P0-6 Raw vs corrections | S2-U01 to U07, S2-I03 |
| P0-7 Review and edit | S2-U06, S2-UI01, S2-M03 |
| P0-8 Wardrobe grid, filters, search | S2-U24 to U28, S1-UI01, S2-M05 |
| P0-9 Garment sets | S3-U22 to U24, S5-U17 to U19, S5-I04 |
| P0-10 Intent parsing | S4-U01 to U06, S4-I02, E-INT |
| P0-11 Outfit engine | All S3-U, E-ENG |
| P0-12 Outfit cards | S4-U12 to U15, S4-M03 |
| P0-13 Another option and swap | S3-U30, S4-U16 to U20, S4-I04 |
| P0-14 Save outfits | S4-U21 to U23, S4-UI01 |
| P0-15 Manual outfit builder | S5-U01 to U07, S5-I01, S5-M01 to M04 |
| P0-16 AI request log | S2-U21 to U23, S2-I01 |
| P0-17 Model-unavailable state | S2-U29, S2-I04, S2-M06, S4-I03 |
| P0-18 Delete data | S1-I06, S4-U23, S5-U24, S5-I05 |

## 8. How to run

```bash
swift test --package-path Packages/StyleEngine
```

```bash
xcodebuild test -project AIStylist.xcodeproj -scheme AIStylist -destination 'platform=iOS Simulator,name=iPhone 17'
```

Evals: in Xcode, choose the `Evals` test plan, select the iPhone 17 as the destination, and run. Copy the printed summary into the result file for that sprint.
