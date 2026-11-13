# PRD: Wardrobe + AI Stylist MVP (native iOS, on-device AI)

Written 10 Nov 2026. Owner: Austin. Status: draft for review.
Companion: [SPRINT_PLAN.md](SPRINT_PLAN.md), [TEST_PLAN.md](TEST_PLAN.md). Background: [PROJECT_BRIEF.md](../../PROJECT_BRIEF.md), [PRODUCT_COMPARISON.md](../../PRODUCT_COMPARISON.md).

---

## 0. Decisions this PRD makes (read first)

| Decision | Choice | Why |
|---|---|---|
| Platform for the MVP | **Native Swift + SwiftUI, iOS 27, iPhone only** | Free on-device AI, test hardware already owned (iPhone 17, MacBook) |
| AI for tagging and chat | **Apple Foundation Models framework, on-device model** | Accepts image input since iOS 27, structured output via `@Generable`, no key, no rate limit, no cost |
| Cut-outs | **Apple Vision foreground mask**, on-device | Free, no rembg server |
| Fallback AI | **Gemini Flash free tier**, only if the on-device model fails the Sprint 0 accuracy test | Free but rate-limited |
| Backend | **None in the MVP.** Everything is stored on the phone | Nothing to host, nothing to pay for |
| Outfit generation | **Our own Swift rule engine**; the LLM only reads intent and writes the note | Hard rule in CLAUDE.md; cost does not grow per outfit |

**This overrides the stack in CLAUDE.md and PROJECT_BRIEF.md §5** (Expo, NestJS, Postgres, R2) for the prototype phase. Those files are not yet updated.

**Risk you should accept knowingly.** An iPhone-only app that needs Apple Intelligence (iPhone 15 Pro or newer) cannot reach most Indian users, who are on Android. So this MVP is a **$0 prototype that proves the tagging schema and the outfit engine on your own wardrobe**. It is not the India launch product. The parts that carry over to a later cross-platform build are the taxonomy, the item schema, the engine rules and the prompts, so the PRD keeps those as plain data tables, not Swift-only logic.

---

## 1. Problem statement

People own enough clothes but still struggle to decide what to wear for a specific occasion, and they cannot see their wardrobe in one place. Existing apps (Alta, Atricent) are US/EU-focused, need a paid cloud AI per user, and handle Indian occasions and garments poorly. A hand-built `wardrobe.json` plus a chatbot already solved this for one person (a good Diwali outfit from owned clothes), which shows the idea works; it does not show images, does not scale past one file, and re-sends the whole wardrobe on every question.

## 2. Goals

1. **Add an item in under 20 seconds** from photo to a tagged, cut-out wardrobe entry (median, on iPhone 17).
2. **Tags are right without editing most of the time**: category ≥ 95%, colour ≥ 90%, collar/sleeve/pattern ≥ 85%, fabric ≥ 75%, measured against the 42 items in `wardrobe.json`.
3. **Outfits are wearable**: for 10 test occasions, at least 2 of the top 3 suggestions are ones Austin would actually wear.
4. **$0 running cost**: no paid API call anywhere in the MVP.
5. **Daily personal use for 14 days straight** by the end of the plan.

## 3. Non-goals

| Not in the MVP | Why |
|---|---|
| Accounts, login, cloud sync, backend | One user, one phone. Adds weeks and cost |
| Subscriptions, ads, usage caps | Nothing to bill for a free on-device prototype |
| Social features, virtual try-on | Hard rule in CLAUDE.md |
| Android, iPad, web | See risk in §0 |
| Video closet scan, multi-item detection from one outfit photo | Hardest pipeline step; MVP is one garment per photo |
| Wedding planner, trip planner, shopping check | Post-MVP headline features in the brief |
| Generated outfit images | Outfit cards are composed from existing cut-outs |
| Calendar integration | Wear log covers the need for now |

## 4. Users and stories

Single persona for the MVP: **the owner of the wardrobe** (Austin first; later 3–5 friends on TestFlight).

**Building the wardrobe**
- As an owner, I want to photograph or pick several clothes at once so that adding my wardrobe is quick.
- As an owner, I want the camera to tell me when a photo is too dark, blurry or cluttered so that the cut-out and tags come out right.
- As an owner, I want each item shown on a clean white background so that my wardrobe looks consistent.
- As an owner, I want the app to fill in type, colour, fabric, collar, sleeve, fit and dress code so that I don't type anything.
- As an owner, I want to correct a wrong tag with one tap so that suggestions improve.
- As an owner, I want to filter and search my wardrobe so that I can find an item fast.

**Getting dressed**
- As an owner, I want to type an occasion in plain words ("Diwali at a friend's place, evening, indoors") and get complete outfits from my own clothes.
- As an owner, I want a short reason with each outfit so that I trust it.
- As an owner, I want to ask for a different option or swap one piece so that I am not stuck with the first answer.
- As an owner, I want to pin one item ("style this shirt") and get outfits built around it.

**Keeping outfits**
- As an owner, I want to save an outfit and find it later.
- As an owner, I want to build my own outfit by dragging items onto a canvas.
- As an owner, I want to mark an outfit as worn so that the app stops repeating it.

**Edge cases**
- No Apple Intelligence on the device, or the model is still downloading: the app says so and still allows manual tagging.
- Wardrobe too small for the occasion: the app says which slot is missing ("no closed-toe shoes for this").
- Cut-out fails (white shirt on a white bed): the user can retake or keep the original photo.

## 5. How it works

### 5.1 System picture

```
 Camera / Photo picker
        │  original photo
        ▼
 Quality check ── fail ──▶ "Retake: too dark / blurry / no clear item"
        │ pass
        ▼
 Vision foreground mask ──▶ transparent PNG  +  white-background JPEG
        │
        ├──▶ Colour extractor (code, on cut-out pixels) ──▶ hex + named colours
        ▼
 Tagger (Foundation Models, image + @Generable enums, 3 small calls)
        │  aiRaw (never edited)
        ▼
 Review screen ── user edits ──▶ userOverrides
        ▼
 SwiftData store (items, outfits, wear log, AI request log) + image files on disk

 "Diwali at a friend's place…"
        ▼
 Intent parser (Foundation Models, text only) ──▶ OccasionIntent
        ▼
 StyleEngine (pure Swift): filter ▶ pick formula ▶ seed ▶ fill slots ▶ rule checks ▶ score
        ▼
 Top 3 outfits ──▶ Stylist note (Foundation Models, text only, item rows not images)
        ▼
 Outfit cards composed from cut-outs
```

A vision model runs **once per item, at upload**. Outfit requests use text only.

### 5.2 Add-item pipeline

| Step | What happens | Tool |
|---|---|---|
| 1. Capture | In-app camera with a framing guide, or multi-select from Photos (up to 20) | AVFoundation, `PhotosPicker` |
| 2. Quality check | Reject if too dark, too blurry, or no clear subject; say which | Core Image stats, Vision subject mask area |
| 3. Cut-out | Lift the garment, crop to its bounds, save a transparent PNG and a white-background JPEG | Vision foreground instance mask |
| 4. Colour | Cluster the cut-out's pixels, take the top 1–3 colours as hex, map each to the named palette | Code only, no AI |
| 5. Tag | Three short image prompts, each returning a `@Generable` struct of enums, greedy sampling | Foundation Models |
| 6. Review | Show the cut-out with tag chips; one tap opens a picker for any field | SwiftUI |
| 7. Save | Store `aiRaw`, `userOverrides`, image paths, and one AI log row per call | SwiftData |

Why three tagging calls: the on-device model has a 4K-token context and images use part of it. Small enum-only answers are also more reliable than one large one.
- **Call A, identity:** category, subcategory, style origin (western / Indian / Indo-western), set role.
- **Call B, construction:** fabric, pattern, fit, length, collar or neckline, sleeve. Asked only the fields that apply to the category from call A.
- **Call C, usage:** dress codes, formality 1–5, seasons, warmth, statement level, one-line caption.

Bulk upload runs items one after another in the background; the wardrobe shows a "tagging" placeholder per item.

### 5.3 Item schema

Stored as one row per item. Effective tags = `aiRaw` overlaid with `userOverrides`.

| Field | Values |
|---|---|
| `category` | top, bottom, onePiece, outerwear, footwear, accessory |
| `subcategory` | shirt, tshirt, polo, sweater, hoodie, jacket, blazer, kurta, kurti, blouse, choli, jeans, chinos, trousers, shorts, joggers, pyjama, salwar, skirt, lehengaSkirt, dress, saree, dupatta, sneakers, boots, formalShoes, loafers, sandals, slides, heels, flats, juttis, belt, watch, chain, glasses, bag, cap, other |
| `styleOrigin` | western, indian, indoWestern |
| `setRole` + `setGroupId` | none, or a named part of a set (kurta + bottom + dupatta; lehenga skirt + choli + dupatta; saree + blouse). Items in one set share a `setGroupId` |
| `colors[]` | 1–3 of: black, white, cream, beige, grey, charcoal, navy, blue, lightBlue, teal, green, olive, yellow, mustard, orange, rust, red, maroon, pink, purple, brown, tan, gold, silver, multicolor |
| `hexColors[]` | exact hex from the colour extractor |
| `pattern` | solid, stripe, check, graphic, floral, embroidered, textured, colourBlock, other |
| `fabric` | cotton, linen, cottonLinen, denim, corduroy, twill, jersey, knit, wool, fleece, silk, satin, synthetic, leather, suede, unknown |
| `fit` | slim, regular, relaxed, loose, boxy |
| `length` | cropped, regular, long (tops); short, ankle, full (bottoms) |
| `collar` | spread, buttonDown, mandarin, camp, polo, crew, vNeck, hooded, zipStand, none |
| `sleeve` | sleeveless, short, threeQuarter, long |
| `dressCodes[]` | home, casual, smartCasual, businessCasual, formal, festive, party, athletic |
| `formality` | 1 (home) to 5 (formal) |
| `seasons[]` | summer, monsoon, winter |
| `warmth` | 1 light, 2 medium, 3 warm |
| `statement` | plain, medium, statement |
| `closedToe` | footwear only |
| `caption` | one free-text line, used for search and the stylist note |
| `name` | short label, auto-built ("Rust mandarin-collar linen shirt"), editable |
| Images | `originalPath`, `cutoutPath` (transparent), `displayPath` (white background) |
| Bookkeeping | `id`, `createdAt`, `status` (tagging, ready, failed, archived), `taggerVersion`, `aiRaw` (JSON), `userOverrides` (JSON), `lastWornAt`, `cutoutFailed`, `lastError`, `featurePrint` (for the duplicate check) |

Fabric from a photo is a best guess even for large models (cotton vs linen). The review screen marks fabric as "check this" whenever the model answers `unknown` or the item is new to the category.

Other tables:
- **Outfit**: id, name, source (ai, manual), occasion, note, createdAt, saved, canvas layout (per-item position and scale for manual outfits).
- **OutfitItem**: outfitId, itemId, slot.
- **WearLog**: outfitId or itemIds, date.
- **AIRequestLog**: purpose (tagA, tagB, tagC, intent, note), provider, model, duration, token counts when the API reports them, success. Cost is 0 on-device; the table exists so paid providers can be dropped in later with tracking already in place.
- **FeedbackEvent**: outfitId, action (saved, rejected, swapped), slot, reason text.

### 5.4 Occasion intent

The intent parser turns free text into this, and nothing else:

```
OccasionIntent {
  occasion: casualDay | office | interview | date | party | weddingGuest |
            festival | puja | travel | gym | home
  dressCode: one of dressCodes
  formalityMin, formalityMax: 1–5
  timeOfDay: day | evening | night
  setting: indoor | outdoor | mixed
  weatherFeel: hot | mild | cold | rainy | unknown
  preferIndian: Bool
  flags: [fireworks, lotsOfWalking, religiousSite, photoHeavy]
  mustIncludeItemIds: [id]      // from "style this item"
  avoid: [colour | subcategory] // "no jeans", "not black"
}
```

A static table maps each `occasion` to default dress codes, a formality range and rules (for example festival → festive or smartCasual, warm colours boosted; `fireworks` → closed-toe only, no loose synthetics). The LLM picks from the enums; the table and engine do the rest.

### 5.5 StyleEngine

A pure Swift package with no UI and no AI, fully unit-tested against `wardrobe.json`.

1. **Filter** each item against the intent. Every rejection carries a reason code: `wrongDressCode`, `formalityOutOfRange`, `wrongSeason`, `tooWarm`, `avoided`, `openToeBlocked`, `ruleBlocked`, `wornRecently`, `notReady`.
2. **Pick formulas** that the remaining items can fill:
   - top + bottom + footwear
   - top + bottom + footwear + outerwear (cold only)
   - base tee + overlayer + bottom + footwear
   - onePiece + footwear
   - set (all items sharing a `setGroupId`) + footwear
   - any of the above + up to 2 accessories
3. **Seed**: pinned item if given, else the highest-scoring top or set.
4. **Fill** remaining slots, scoring each candidate against items already chosen.
5. **Hard checks**: at most one statement or patterned piece; formality spread ≤ 2 across the outfit; no top and bottom in the same non-neutral colour; warm overlayer never in hot weather.
6. **Score** = occasion fit + colour harmony + formality match + pair weight (from saved outfits) + freshness (not worn recently) + a small seeded variety term. Outfits already shown this session are excluded outright, not scored down.
7. **Return** the top N distinct outfits, plus the reason list for anything missing ("no festive footwear").

Colour harmony for the MVP is a small table: neutrals go with everything; one accent colour per outfit; warm-with-warm and earth tones score up; listed clash pairs score down. A daily seed keeps results stable within a day and different across days.

### 5.6 Chat and "show me something else"

- Each message goes to the intent parser with the last few turns of text, so "make it more casual" or "no chinos" adjusts the previous intent.
- **Another option** re-runs the engine with already-shown outfits excluded. No LLM call.
- **Swap one piece** (tap a slot) re-fills just that slot. No LLM call.
- A rejection or swap is saved as a `FeedbackEvent` and lowers that pair's weight.
- The stylist note call receives the top 3 outfits as short text rows (name, colour, fabric, dress code) and returns 1–2 sentences per outfit. It may not add or change items; returned IDs are checked against the engine's output.

### 5.7 Tagger is swappable

`ItemTagger`, `IntentParser` and `NoteWriter` are protocols with one implementation each in the MVP (Foundation Models). The protocols also let tests swap in fakes; see [TEST_PLAN.md](TEST_PLAN.md). A second implementation is written **only** if Sprint 0 shows the on-device model misses the accuracy targets:

| Order | Provider | Cost | Limit |
|---|---|---|---|
| 1 | On-device system model | Free | Needs Apple Intelligence on; 4K context |
| 2 | Apple Private Cloud Compute model (one-line switch, 32K context) | Not verified | Not verified; check before relying on it |
| 3 | Gemini Flash free tier | Free | Rate-limited per minute and per day; own photos only, key in a local config file that is never committed |
| Later | Paid API behind our own backend | Paid | Needed before any other person's photos, per CLAUDE.md |

## 6. Screens

Three tabs and one add flow.

| Screen | What it shows | Main actions |
|---|---|---|
| **Wardrobe** (tab 1) | Grid of white-background cut-outs, grouped by category; filter chips (category, colour, dress code, season); search | Open item, add (+), multi-select to archive |
| **Add items** | Camera with framing guide and live "good / too dark / move closer" hint; or pick from Photos | Shoot several in a row, done |
| **Review** | Cut-out and tag chips per new item; fields needing a check are highlighted | Tap chip to change, retake, save all |
| **Item detail** | Large image, all tags, outfits that use it, last worn | Edit tags, re-run tagging, "style this item", archive |
| **Stylist** (tab 2) | Chat box with occasion shortcut chips (Office, Date, Festival, Wedding, Party, Travel); results as outfit cards with a note | Save, another option, swap a piece, mark worn |
| **Outfits** (tab 3) | Saved outfits as cards, filter by occasion; wear history | Open, edit, mark worn, delete, new manual outfit |
| **Outfit builder** | Canvas plus a drawer of wardrobe items by category | Drag an item onto the canvas, move, resize, remove, save |
| **Settings** | AI status (model available or not), item and outfit counts, export wardrobe as JSON, delete all data | |

Outfit card layout: cut-outs arranged in a fixed template (top above bottom, footwear below, outerwear and accessories to the side) on a plain background.

## 7. Requirements

### P0: the MVP does not work without these

| # | Requirement | Acceptance criteria |
|---|---|---|
| P0-1 | Capture from camera and Photos | Multi-select up to 20 photos; in-app camera takes several in a row; originals saved at full resolution |
| P0-2 | Photo quality check | A dark, blurry or subject-less photo is flagged with the specific reason before tagging; user can retake or continue |
| P0-3 | Cut-out on white | Each item gets a transparent PNG and a white-background image cropped to the garment; on failure the original is kept and the item is marked |
| P0-4 | Exact colour | 1–3 hex colours from cut-out pixels, each mapped to a named colour; no AI call |
| P0-5 | AI tagging | All fields in §5.3 filled from the image on-device; item moves tagging → ready; a failed item can be retried |
| P0-6 | Raw vs corrections | `aiRaw` is never modified after tagging; edits go to `userOverrides`; re-tagging replaces `aiRaw` and keeps overrides |
| P0-7 | Review and edit | Every tag is editable from a picker of allowed values; no free-text tags except name and caption |
| P0-8 | Wardrobe grid | Grid by category with filters for category, colour, dress code and season, plus text search over name and caption |
| P0-9 | Garment sets in the data model | Items can be linked by `setGroupId` with set roles; the engine treats a linked set as one multi-slot unit |
| P0-10 | Intent parsing | Free text returns a valid `OccasionIntent`; if the model is unavailable, occasion chips still work |
| P0-11 | Outfit engine | Returns up to 3 complete outfits or names the missing slot; every rejection has a reason code; unit tests pass on the `wardrobe.json` fixture |
| P0-12 | Outfit cards | Each result is shown as composed cut-outs with item names and a 1–2 sentence note |
| P0-13 | Another option and swap | Both work without an LLM call and never repeat an outfit shown in the same session |
| P0-14 | Save outfits | Saved outfits persist, list on the Outfits tab and reopen with all items |
| P0-15 | Manual outfit builder | Drag items from the drawer onto a canvas, move and resize them, save as an outfit |
| P0-16 | AI request log | One row per AI call with purpose, provider, duration and success |
| P0-17 | Model-unavailable state | If Apple Intelligence is off or still downloading, the app explains it, and manual add and manual tagging still work |
| P0-18 | Delete data | An item, an outfit, or everything can be deleted, including image files |

### P1: fast follow

- "Style this item" from item detail (pin an item).
- Wear log and freshness: mark worn; worn items are down-weighted for a few days.
- Feedback to pair weights: saved outfits raise a pair's weight, rejections lower it.
- Weather from Open-Meteo (free) to fill `weatherFeel` for today.
- Duplicate check on add: compare a new cut-out to existing ones (Vision image feature print) and ask "same as this item?".
- Set-linking UI: select items and mark them as one set.
- Export and import wardrobe JSON (also the path for loading `wardrobe.json` into a test build).
- Chat tool calling so the model can call `searchItems` for questions like "do I have anything green?".

### P2: design for it, do not build it

- Backend, accounts and sync (NestJS, Postgres, R2 as in the brief); the SwiftData schema mirrors the future Prisma schema field for field.
- Paid AI provider with per-user token and cost caps.
- Wedding planner, trip planner, shopping check.
- Multiple items from one outfit photo; video closet scan.
- Android or cross-platform client reusing the taxonomy and engine rule tables.
- Personal rules from feedback ("never pair X with Y").

## 8. Success metrics

| Metric | Target | How measured |
|---|---|---|
| Tag accuracy vs `wardrobe.json` (42 items) | category ≥ 95%, colour ≥ 90%, collar/sleeve/pattern ≥ 85%, fabric ≥ 75% | Eval script from Sprint 0, re-run after every prompt change |
| Edits per item at review | median ≤ 1 | Count of `userOverrides` keys |
| Time to add one item | median ≤ 20 s, of which tagging ≤ 10 s | AI log durations and timestamps |
| Cut-out success | ≥ 90% need no retake | Retake count |
| Outfit acceptance | ≥ 2 of top 3 wearable on 10 test occasions | Manual rating sheet |
| Intent to results | ≤ 4 s | AI log and engine timing |
| Running cost | Rs 0 | No paid provider configured |
| Personal use | 14 consecutive days with at least one stylist request | FeedbackEvent and AI log dates |

## 9. Open questions

| Question | Who | Blocking? |
|---|---|---|
| Does the on-device model reach the accuracy targets, especially collar type, fabric and Indian garments? | Engineering, Sprint 0 | **Yes**, decides the provider |
| How many of the 4K tokens does one garment image use, and what image size is the best trade-off? | Engineering, Sprint 0 | Yes |
| Is the Private Cloud Compute model free and unmetered for third-party apps? | Engineering, check Apple docs | No |
| Does the on-device model run in the iOS simulator on the MacBook, or is the iPhone required for every AI test? | Engineering, Sprint 0 | No |
| After the prototype, which path reaches Indian Android users: the Expo plan in the brief, or something else? | Austin | No, but decide before any launch work |
| The research note (docs/RESEARCH_INDIE_HACKERS.md) advised against starting the full wardrobe build and found a direct competitor (Drapis). Does a $0 personal prototype change that advice enough to proceed? | Austin | No; this PRD assumes yes because nothing is spent |
| Men's wardrobe is the test set, but the brief says launch women-first. When do women's and Indian garments get tested? | Austin | No; needs 10–15 borrowed photos by Sprint 5 |

## 10. Phasing

| Phase | Outcome | Sprint |
|---|---|---|
| 0. Proof | On-device tagging measured against `wardrobe.json`; provider chosen | 0 |
| 1. Wardrobe | Photo → cut-out → tags → wardrobe grid with editing | 1–2 |
| 2. Engine | Outfits from an occasion, tested on the fixture | 3 |
| 3. Stylist | Chat, outfit cards, another option, swap, save | 4 |
| 4. Builder | Manual drag-and-drop outfits, wear log, feedback | 5 |
| 5. Own use | Full wardrobe loaded, 14 days of use, fixes | 6 |

No hard deadline. Wedding season (Nov–Feb) is the natural window for filming content from the working prototype.
