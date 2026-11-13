# Sprint 4: Stylist chat

**Dates:** 7–13 Dec 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.4, §5.6, §6, P0-10, P0-12, P0-13, P0-14

## Goal

Type an occasion, get three outfit cards built from your own clothes, ask for another option or swap a piece, and save one.

## Needs from earlier sprints

- Tagged items in the app (Sprint 2), ideally 25 or more of your real clothes.
- A passing engine (Sprint 3). If the Sprint 3 gate failed, fix the tables first.

## What must exist at the end

| Piece | Behaviour |
|---|---|
| Intent parser | Free text and recent turns → `OccasionIntent` |
| Stylist tab | Text box, occasion chips, results as outfit cards |
| Intent chips | The parsed intent shown above results and editable |
| Outfit card | Cut-outs in a fixed layout with names and a note |
| Stylist note | 1–2 sentences per outfit, written by the on-device model |
| Another option / swap | Work with no AI call and never repeat |
| Saved outfits | Outfits tab with list and detail |

## Flow

```
text ─▶ IntentParser (AI, text only) ─▶ OccasionIntent ─▶ shown as chips
                                              │
 SwiftData items ─▶ EngineItem ─▶ StyleEngine.generate ─▶ top 3
                                              │
                         cards appear at once (no note yet)
                                              │
                         NoteWriter (AI, text only) ─▶ notes fill in
```

Cards are shown as soon as the engine returns; notes arrive a moment later. The engine result is never blocked on the note.

## Build steps

### 1. Intent parser (2 h)
```swift
protocol IntentParser {
    func parse(message: String, previous: OccasionIntent?, recent: [String]) async throws -> OccasionIntent
}
```
- `FoundationModelsIntentParser`: one fresh session per message, greedy sampling. The model generates a `@Generable` `ParsedIntent` whose fields are all optional enums (nil = not mentioned). Plain code then merges it with the previous intent and the occasion table into a full `OccasionIntent`; that merge is unit-tested.
- Notes go through a `NoteWriter` protocol in the same way, so tests can use a fake.
- Instructions (short): "Turn the user's message into an outfit request. Choose only from the allowed values. If the message changes an earlier request, keep everything it does not mention."
- Prompt contents: the previous intent as one line of text if there is one, the last two user messages, the new message. Nothing about the wardrobe goes into this call.
- `mustIncludeItemIds` is never set by the model; the app sets it when the user pins an item.
- `avoid` is limited to colour names and subcategories from the taxonomy.
- If the parser throws or the model is unavailable, fall back to `casualDay` defaults and show the chips so the user can set them.

### 2. Stylist tab (2.5 h)
- Top: a row of occasion chips (Office, Date, Festival, Wedding, Party, Travel, Casual). Tapping one builds an intent from the occasion table with no AI call.
- Middle: the conversation as a simple list: the user's message, the intent chips, three outfit cards, action buttons.
- Bottom: a text field with a send button.
- Under the results: **Another option** and **Start over**.
- A view model holds: current intent, shown outfit keys (for exclusion), recent messages (last three).

### 3. Intent chips (1 h)
- A row such as `Festival · Evening · Indoor · Mild · Smart casual`. Each chip opens a picker for that field.
- Changing a chip re-runs the engine immediately, with no AI call, and clears the shown-keys list.
- Flags (fireworks, lots of walking) and avoid items show as removable chips.

### 4. Outfit card (2.5 h)
- A fixed-size card that places transparent cut-outs by slot:
  - top (or set top) upper centre, largest
  - bottom below it, slightly overlapping
  - footwear bottom centre, smaller
  - outerwear to the left of the top
  - accessories in a column on the right
  - one-piece items take the top and bottom area
- Each cut-out is scaled to fit its slot box, keeping aspect ratio.
- Below the image: item names in one or two lines, then the note.
- Tapping a cut-out selects that slot and shows **Swap**. Tapping the card opens outfit detail.

### 5. Stylist note (1.5 h)
- One call for all three outfits. Input is text only: the intent in one line, then per outfit a numbered list of rows like `top: Rust mandarin-collar linen shirt (rust, relaxed)`.
- Output: a `@Generable` struct with exactly three strings. Instructions: "For each outfit write one or two sentences on why it suits the occasion. Mention only the listed items. Do not suggest other items."
- Validation: if a note names a subcategory or colour that is not in its outfit, drop that note and show the card without one.
- Notes are stored on the outfit when it is saved.

### 6. Another option and swap (1.5 h)
- **Another option:** add the three shown keys to `excludeOutfits`, call the engine again. When the engine returns nothing new, show "That's everything your wardrobe has for this" with the `missing` slots if any.
- **Swap:** call an engine function `alternatives(for slot, in outfit, intent)` that returns the next best items for that slot which pass the hard checks with the rest of the outfit. Show them as a horizontal strip; tapping one replaces the item in the card.
- Both record a `FeedbackEvent` (`rejected` for the three replaced outfits, `swapped` with the slot). They are stored now and used in Sprint 5.

### 7. Save and Outfits tab (2 h)
- **Save** on a card creates an `Outfit` (source `ai`, occasion, note) and its `OutfitItem` rows, and records a `saved` event.
- Outfits tab: grid of saved outfit cards, newest first, filter by occasion.
- Outfit detail: large card, item list (tap to open the item), rename, delete.
- Deleting a wardrobe item removes it from saved outfits; an outfit left with fewer than two items is deleted.

## Expected behaviour

- "Diwali at a friend's place, evening, indoors, no crackers" → chips read `Festival · Evening · Indoor`; three cards appear within about a second of the intent, notes a few seconds later.
- "Make it more casual" → formality drops, occasion stays Festival, new cards appear.
- "No chinos" → an avoid chip appears; no chinos in results.
- Another option shows three different outfits each time until the wardrobe is exhausted.
- Swapping footwear keeps the rest of the outfit and offers only footwear that fits the occasion.
- A saved outfit is on the Outfits tab after restarting the app.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Wrong occasion for clear text ("sangeet" → party) | Small model does not know the term | Add a short glossary line to the instructions (sangeet, haldi, mehendi, puja → their occasions); the chips let the user correct it in one tap |
| Follow-up resets everything | Previous intent not passed, or model ignores it | Pass the previous intent as text; after parsing, copy over any field the new message did not mention |
| "No jeans" ignored | `avoid` not parsed, or free text returned | Constrain `avoid` to taxonomy values; add a keyword check in code for "no <subcategory or colour>" as a backstop |
| Long wait before anything shows | UI waits for the note | Show cards right after the engine; fill notes in later |
| Note mentions an item that is not in the outfit | Model invents | Validation drops the note; tighten instructions; never let the note change items |
| Note is generic ("great for any occasion") | Too little context | Include the occasion, time and two tags per item in the rows |
| Context error on the note call | Three outfits with long rows | Shorten rows to name and colour; or one call per outfit |
| Cards look messy: shoes huge, shirt tiny | Scaling by image size instead of slot box | Fit each cut-out inside its slot box; crop cut-outs tight in Sprint 1's service |
| Another option repeats an outfit | Shown keys not accumulated, or key order differs | Key is the sorted id set; append every shown key to the session set |
| Empty results with no explanation | `missing` not surfaced | Show "Nothing for this yet: no <slot>" and a button to relax the dress code |
| Chips do nothing when AI is off | Chip path goes through the parser | Chips build the intent from the occasion table directly |
| Saved outfit shows blank images later | Item deleted | Cascade on delete as described in step 7 |

## Tests

**Tests first.** Write the cases in [SPRINT_4_TESTS.md](SPRINT_4_TESTS.md) before the code for each build step. That file has the full unit, integration, eval and manual cases and the exit gate; the list below is only a summary.

- Intent table (runs on device or Mac with the model): 15 sentences with expected occasion and dress code; at least 13 must match. Include: office tomorrow, interview at a startup, date night, cousin's sangeet, Diwali at a friend's, temple visit, flight to Goa, gym, staying home, college fest.
- Follow-ups: "more casual" lowers `formalityMax`; "no black" adds black to `avoid`; "actually it's outdoors" changes only `setting`.
- Note validation: a note naming an absent subcategory is rejected.
- `alternatives(for:)`: returned items all pass the hard checks with the remaining outfit.
- Save then reload: outfit has the same items and note.

## Checklist

- [ ] 13 of 15 intent sentences correct
- [ ] Follow-ups keep unmentioned fields
- [ ] Intent chips shown and editable; editing re-runs the engine with no AI call
- [ ] Cards appear before notes
- [ ] No note mentions an item outside its outfit
- [ ] Another option never repeats within a session
- [ ] Swap offers only valid items for that slot
- [ ] Save, list, detail, rename and delete work and survive restart
- [ ] Occasion chips work with the model unavailable
- [ ] Text to cards ≤ 4 s on the phone
- [ ] AI log has `intent` and `note` rows

## How it lands

- Branch `sprint-4`, merge to `main`, tag `sprint-4-done`.
- Demo: screen-record the Diwali request end to end, including one follow-up, a swap and a save. This is the first clip worth posting.

## Not this sprint

Manual builder, wear log, learning from feedback, weather lookup, tool calling.
