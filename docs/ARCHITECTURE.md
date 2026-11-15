# Architecture

## Layers
- **StyleEngine package** (`Packages/StyleEngine`, target `StyleEngine`): taxonomy, tag schema, outfit engine, stylist session, review rules (`ReviewRules.swift`) as plain data and pure functions. Portable to the later cross-platform build. Known gap: it still imports `FoundationModels` for the `@Generable` tag structs (`ItemTagger.swift`, `Taxonomy.swift`); splitting those out is a later step.
- **WardrobeImaging** (same package): cut-out, colour, catalogue look, `ImageStore`. Pure over pixels except the Vision wrapper.
- **App** (`App/`): SwiftUI screens, view models, SwiftData models, and the adapters to Apple frameworks.
  - `App/AI/`: the provider seam (below). `App/AI/Apple/` holds everything that imports `FoundationModels`.
  - `App/Capture/`: `ReviewModel` is the façade the review screen uses. It delegates to `CaptureProcessor` (cut-out and file moves), `TaggingCoordinator` (live AI per photo, timeout), `ReviewQuestions` (which questions to ask) and `ReviewSaver` (writes the `Item`, product-photo queue).
  - `App/Tagging/`: `TaggingQueue` (background tagging), `TaggingRun` (calls A, B, C), `AICall` (the per-call log wrapper).
  - `App/Design/`: shared tokens (`Color.catalogueGrey`).

## AI provider seam
Views and view models never name a vendor. They use three protocols: `ItemTagger` (StyleEngine), `IntentParser`, `NoteWriter`. An `AIProvider` (abstract factory) says which adapters to build and whether it can run now (`unavailableReason`). `AppEnvironment` is the composition root: built once in `AIStylistApp`, it holds the provider, the `TaggingQueue` and the `ImageStore`, and is injected with `.environment(env)` (read with `@Environment(AppEnvironment.self)`). Factories take it: `ReviewModel.live(env)`, `StylistViewModel.live(env, context:)`.

Every AI call goes through `AICall.record`, which writes purpose, provider, model, duration and tokens. `provider` comes from the adapter (`ProviderReporting.providerName`), `model` from its `version`, tokens from `TokenReporting`.

### Add a provider (e.g. Gemini or OpenAI)
1. Create `App/AI/<Vendor>/` with three adapters: a class conforming to `ItemTagger` (identity, construction, usage; a fresh request per call), one to `IntentParser`, one to `NoteWriter`. Give each a `version` (bump it when a prompt changes), and conform to `ProviderReporting` (`providerName = "gemini"`), `TokenReporting` and, for the tagger, `AvailabilityReporting`. Throw `AIUnavailable` when the key is missing.
2. Create `<Vendor>Provider: AIProvider`: `name`, `unavailableReason` (nil when a key is present), and the three `make...()` methods. Read the API key from the Keychain or a build setting; never commit it.
3. In `AIStylistApp.init`, change `AppleOnDeviceProvider()` to `<Vendor>Provider()`. Nothing else changes.
4. Before any other person's photos are processed, CLAUDE.md requires a paid provider and per-user caps: add the cap in the adapter (or a wrapping provider) first. Keep sending only the cut-out once per upload, never per outfit request.
5. Tests: use `FakeAIProvider` (AppTests) in an `AppEnvironment`; never call the real model in unit tests. Measure quality with the evals in `docs/TEST_PLAN.md`.
