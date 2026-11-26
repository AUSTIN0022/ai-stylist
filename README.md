# AI Stylist

A privacy-first, zero-running-cost **iOS wardrobe manager and AI outfit stylist** built with SwiftUI, SwiftData, Apple Vision, Image Playground, and on-device Apple Foundation Models, powered by a pure deterministic Swift outfit engine (`StyleEngine`).

---

## Overview & Use Case

People own plenty of clothes yet still struggle to decide what to wear for specific occasions—and existing wardrobe apps typically require cloud accounts, recurring server/API fees, and focus poorly on Indian and Indo-western garments and occasions.

**AI Stylist** solves this completely **on-device with $0 running cost**:

- **Catalog your closet quickly**: Photograph garments or import batches from Photos. Background removal, colour extraction, and structured tagging run automatically on the phone.
- **Dress for real occasions**: Type a request in plain language (e.g., *"Diwali at a friend's place, evening, indoors"* or *"Startup interview on Friday"*) or tap occasion chips to get complete, wearable outfits built from clothes you actually own.
- **Built for both Western and Indian wardrobes**: Supports shirts, tees, polos, sweaters, trousers, jeans, chinos, shorts, footwear, accessories, and multi-piece Indian/Indo-western sets (`kurta` + `kurtaBottom` + `dupatta`, `lehengaSkirt` + `choli` + `dupatta`, `saree` + `blouse`).
- **Offline & private by design**: No backend server, no user accounts, and no garment photos leave your phone.

> **Project status**: Implemented through Sprint 6 (`sprint-6` branch). Core capture, imaging, tagging, styling engine, manual outfit builder, duplicate detection, weather defaults, and MVP metrics screens are built; live on-device evaluation (`docs/EVAL_MVP.md`) is the active measurement phase.

---

## What It Does

### 1. Wardrobe Capture, Cut-Outs & Colour Extraction
- **Multi-source input**: In-app camera (`AVFoundation`) with framing guidance (`CameraView`), or multi-select up to 20 photos from `PhotosPicker`.
- **Automated quality gate**: Checks brightness, blur, and subject area (`QualityCheck`) before processing, letting you retake or keep as needed.
- **Vision cut-outs & catalogue presentation**: Uses Apple Vision foreground instance masking (`VisionCutoutService` / `Cutout`) to lift the garment, crop cleanly, and generate a transparent PNG, a white/catalogue-grey display JPEG, a fabric swatch (`FabricSwatch`), and a white-outlined sticker (`StickerMaker`) for outfit cards and the canvas builder.
- **Deterministic pixel colour extraction**: Clusters cut-out pixels (`ColorExtractor`) to extract 1–3 exact hex codes and map them to named palette colours (`ColorName`) with zero AI calls.
- **Duplicate detection**: Computes a Vision feature print (`FeaturePrint`, `DuplicateCheck`) on each cut-out to flag likely duplicates (*"Is this the same as …?"*) when adding items.

### 2. Label Scanning & On-Device AI Tagging
- **Clothing label scanner**: Live camera OCR + barcode scanning (`LabelScannerView`, `LabelPipeline`) matched against a curated `BrandCatalog` (`brands.json`) to extract brand, size, and fabric composition.
- **3-call structured tagging**: Runs Apple's on-device `SystemLanguageModel` (`FoundationModelsTagger`) with greedy sampling and `@Generable` enum schemas across three focused calls:
  - **Call A (`tagA`)**: Identity — `category`, `subcategory`, `styleOrigin`, `setRole`
  - **Call B (`tagB`)**: Construction — `fabric`, `pattern`, `fit`, `length`, `collar`, `sleeve`
  - **Call C (`tagC`)**: Usage — `dressCodes`, `formality` (1–5), `seasons`, `warmth`, `statement`, `caption`
- **Non-destructive overrides**: Stores raw AI output (`aiRawData`), scanned label data (`labelData`), and user edits (`userOverridesData`) separately, merging them dynamically (`ItemTags.effective`) so re-tagging never wipes manual corrections.
- **Background queue & graceful fallback**: Processes batches in `TaggingQueue` (resuming unfinished items on launch). If Apple Intelligence is unavailable or still downloading, manual tagging remains fully usable.

### 3. Stylist Chat & Deterministic Outfit Engine (`StyleEngine`)
- **Natural-language intent parsing**: Converts free-text requests and follow-ups (*"Make it more casual"*, *"No chinos"*, *"Not black"*) into a structured `OccasionIntent` via `FoundationModelsIntentParser` and `IntentMerge`.
- **Daily weather defaults**: Uses coarse location (`0.1°` rounding via `CoarseLocation` / `OpenMeteoSource`) once per day to fetch feels-like temperature and rain chance from Open-Meteo (free, no API key) and set the default `weatherFeel` (`hot`, `mild`, `cold`, `rainy`).
- **Rule-based outfit generation (`OutfitEngine`)**:
  1. Filters items against the intent (`wrongDressCode`, `formalityOutOfRange`, `wrongSeason`, `tooWarm`, `avoided`, `openToeBlocked`, `ruleBlocked`, `wornRecently`, `notReady`).
  2. Builds outfits from weather-appropriate formulas (`top + bottom + footwear`, `layered`, `withOuterwear`, `onePiece`, and linked garment `sets`) plus up to 2 accessories.
  3. Enforces hard styling constraints (e.g., at most one statement/patterned piece, formality spread ≤ 2, clash checks, closed-toe footwear for `fireworks` / `rainy` / `interview` rules).
  4. Scores candidates by **occasion fit**, **colour harmony**, **formality match**, **pair weights** (learned from `FeedbackEvent` and `WearLog`), **freshness**, and a daily seeded variety term.
- **Zero-LLM variations & swaps**: *"Another option"* and single-slot piece swapping run purely in `StyleEngine` with session deduplication.
- **Validated stylist notes**: `FoundationModelsNoteWriter` generates 1–2 sentence explanations from text-only item summaries, checked by `NoteValidator` so notes never hallucinate items or colours outside the outfit.

### 4. Outfits, Manual Builder & Product Shots
- **Saved Outfits & Wear Log**: Save generated or custom outfits, filter by occasion, and mark outfits worn to track `lastWornAt` and inform engine freshness.
- **Drag-and-Drop Outfit Builder**: Arrange garment stickers on an interactive canvas (`OutfitBuilderView`, `OutfitCanvas`) with move, scale, and layer ordering.
- **Set Linking**: Group multi-piece garments (e.g., kurta + pyjama + dupatta) with a shared `setGroupId`.
- **Optional Product Photos**: Generate clean studio-style garment flat-lays on device using Apple `ImagePlayground` (`ProductShotSession`, `ProductShotPrompt`, shape templates, and fabric swatches).

### 5. Observability, Backup & Evals
- **AI Request Log**: Records purpose, provider, model version, duration, token count, and success/error for every AI call (`AIRequestLog`).
- **Backup & Portability**: Export and (in debug builds) import wardrobes as JSON (`WardrobeExport`), plus full local data reset (`DataReset`).
- **Built-in Metrics & Eval Tools**: In-app views for field accuracy (`AccuracyView`), MVP metrics (`MVPMetricsView`), 10-occasion engine rating (`RatingSheetView`), and bundled photo evals (`DebugEvalView`).

---

## How It Works (Architecture)

The codebase is split into a portable pure-Swift core (`Packages/StyleEngine`) and a thin Apple-framework iOS app (`App/`):

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           App/ (SwiftUI + SwiftData)                    │
│  WardrobeView · AddItemsFlow · ReviewView · StylistView · OutfitsView   │
│  AppEnvironment (Composition Root) · TaggingQueue · OpenMeteoSource     │
├─────────────────────────┬───────────────────────┬───────────────────────┤
│     AIProvider Seam     │    StyleEngine        │    WardrobeImaging    │
│  (App/AI/Apple/)        │  (Packages/StyleEngine│  (Packages/StyleEngine│
│                         │   /Sources/StyleEngine│   /Sources/Wardrobe-  │
│  • FoundationModels-    │  • Taxonomy & Schema  │    Imaging/)          │
│    Tagger / Intent /    │  • OutfitEngine       │  • Vision Cut-out     │
│    NoteWriter           │  • IntentMerge        │  • QualityCheck       │
│  • ImagePlayground      │  • PairWeights        │  • ColorExtractor     │
│    (ProductShotSession) │  • DuplicateCheck     │  • StickerMaker       │
│                         │  • Weather / Eval     │  • FeaturePrint       │
│                         │                       │  • ImageStore         │
└─────────────────────────┴───────────────────────┴───────────────────────┘
```

### Key Architectural Decisions
- **Vision AI runs once per garment at upload**; stylist requests send text-only summaries (never images) to the LLM, and outfit scoring itself runs deterministically in Swift (`OutfitEngine`).
- **Swappable AI Provider Seam**: Views and view models depend only on `AIProvider`, `ItemTagger`, `IntentParser`, and `NoteWriter` protocols—never vendor SDKs directly. Switching to Gemini, OpenAI, or another backend only requires implementing those adapters under `App/AI/<Vendor>/` and swapping `AppleOnDeviceProvider()` in `App/AIStylistApp.swift`.
- **Data-driven engine & tables**: Rules, formulas, occasion mappings, and colour harmony live as plain data tables in `EngineTables.swift` so they can be tuned or ported to cross-platform builds later.

---

## Repository Structure

```text
ai-stylist/
├── project.yml                         # XcodeGen spec (source of truth for AIStylist.xcodeproj)
├── App/                                # iOS SwiftUI application target
│   ├── AI/                             # AIProvider seam & Apple FoundationModels adapters
│   ├── Capture/                        # Camera, label scanner, duplicate guard, review flow
│   ├── Debug/                          # Bundled eval UI & `-uiTesting` seeded mode
│   ├── Design/                         # Shared UI color tokens
│   ├── Memory/                         # Pair-weight learning & wardrobe JSON export/import
│   ├── Models/                         # SwiftData @Model entities (Item, Outfit, WearLog, etc.)
│   ├── Outfits/                        # Saved outfits & drag-and-drop OutfitBuilderView
│   ├── Settings/                       # Settings, AI log, accuracy, MVP metrics, rating sheet
│   ├── Stylist/                        # Stylist chat, intent chips, outfit cards, Open-Meteo
│   ├── Tagging/                        # Background tagging queue & call logging
│   ├── Templates/                      # Garment shape template image(s)
│   └── Wardrobe/                       # Wardrobe grid, detail view, stickers, product shots
├── Packages/StyleEngine/               # Local Swift Package (StyleEngine + WardrobeImaging)
│   ├── Package.swift
│   ├── Sources/StyleEngine/            # Taxonomy, OutfitEngine, Stylist logic, Weather, Evals
│   ├── Sources/WardrobeImaging/        # Cut-outs, colour extraction, stickers, ImageStore
│   └── Tests/                          # Unit tests & JSON wardrobe fixtures
├── AppTests/                           # App integration tests, fakes & intent eval cases
├── UITests/                            # XCUITest UI smoke tests (runs with `-uiTesting`)
├── EvalPhotos/                         # Local git-ignored eval photos + tracked expected.template.json
└── docs/                               # PRD, architecture, test plan, eval logs, sprint plans
```

---

## Requirements

- **macOS** with **Xcode 27.2+** / **iOS 27.0 SDK** (Swift 6.0+)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`) — `AIStylist.xcodeproj` is generated from `project.yml` and intentionally git-ignored
- **Physical iPhone with Apple Intelligence** (enabled in Settings with the on-device model downloaded) for live on-device Foundation Models tagging, intent parsing, note generation, and Image Playground product shots
  - *Note*: The iOS Simulator runs the UI, `-uiTesting` mode, and all automated unit/integration/UI tests (using `FakeAIProvider`), though on-device Apple Intelligence availability depends on host/simulator support.

---

## Getting Started (Local Setup)

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd ai-stylist
   ```

2. **Install XcodeGen** (if not already installed)
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project**
   ```bash
   xcodegen generate
   ```
   This creates `AIStylist.xcodeproj` locally from `project.yml` (kept out of git via `.gitignore`).

4. **Configure code signing (for running on a physical iPhone)**
   - Open `AIStylist.xcodeproj` in Xcode, or update `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` before running `xcodegen generate`.
   - Select your iPhone target and run the `AIStylist` scheme.

---

## Running Tests & Evaluations

### 1. Pure Swift Package Tests (`StyleEngine` + `WardrobeImaging`)
Runs fast on macOS with no simulator or AI model required:
```bash
swift test --package-path Packages/StyleEngine
```

### 2. App Unit, Integration & UI Tests
Uses fake AI providers (`FakeAIProvider`) and `-uiTesting` in-memory seeded data:
```bash
xcodebuild test \
  -project AIStylist.xcodeproj \
  -scheme AIStylist \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 3. On-Device Model Evaluations
- Copy `EvalPhotos/expected.template.json` to `EvalPhotos/expected.json` and place your personal test garment photos in `EvalPhotos/` (both photos and `expected.json` are git-ignored).
- Run the **Photo eval** screen under **Settings → Developer → Photo eval (bundled photos)** or run the `Evals` test plan on a physical iPhone.
- See [docs/TEST_PLAN.md](docs/TEST_PLAN.md) and [docs/EVAL_MVP.md](docs/EVAL_MVP.md) for pass marks and measurement instructions.

---

## Privacy & Permissions

- **Camera & Photo Library**: Used strictly to photograph or select clothing items and scan care/brand labels. All images are stored locally on the device (`ImageStore`).
- **Location (`NSLocationWhenInUseUsageDescription`)**: Optional; when granted, coordinates are rounded to `0.1°` (~10 km) and sent once per day to the free Open-Meteo forecast API to pre-fill today's weather feel. No personal or wardrobe data is ever sent.

---

## Documentation

- [PRD_MVP.md](docs/PRD_MVP.md) — Product requirements, item schema, outfit rules, and MVP goals
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Layering, `AIProvider` seam, and how to add new AI vendors
- [TEST_PLAN.md](docs/TEST_PLAN.md) — Automated test strategy, eval definitions, and sprint exit gates
- [SPRINT_PLAN.md](docs/SPRINT_PLAN.md) — Sprint roadmap (Sprints 0–6) and detailed specs in [docs/sprints/](docs/sprints/)
- [EVAL_MVP.md](docs/EVAL_MVP.md) — Final prototype measurement log and tuning record
