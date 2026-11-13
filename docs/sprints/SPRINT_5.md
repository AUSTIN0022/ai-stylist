# Sprint 5: Manual builder and memory

**Dates:** 14–20 Dec 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §5.3 (Outfit, WearLog, FeedbackEvent), §6, P0-15, P0-18, and P1 items

## Goal

Build an outfit by hand by dragging items onto a canvas, and have the app learn from what you save, wear and reject.

## Needs from earlier sprints

- Saved outfits and the Outfits tab (Sprint 4).
- `FeedbackEvent` rows already being written (Sprint 4).
- `pairWeights` and `lastWornAt` inputs already in the engine (Sprint 3).

## What must exist at the end

| Pri | Piece | Behaviour |
|---|---|---|
| P0 | Outfit builder | Drag items onto a canvas, move, resize, remove, save |
| P0 | Reopen and edit | A manual outfit reopens with the same layout |
| P1 | Wear log | Mark an outfit or item as worn; recently worn items are suggested less |
| P1 | Pair weights | Saved and worn pairs rank higher, rejected pairs lower |
| P1 | Set linking | Mark several items as one set |
| P1 | Export / import | Wardrobe as a JSON file |
| P1 | Settings | AI status, counts, delete all data |

If the P0 builder is not working by hour 5, switch to the fallback in step 1 and keep the P1 items.

## Build steps

### 1. Outfit builder (4 h)
Layout: canvas on top (about 60% of the screen, plain light background), item drawer below.

- **Drawer:** category tabs (Tops, Bottoms, Footwear, Outerwear, Accessories, Sets), each a horizontal scroll of cut-out thumbnails.
- **Add:** drag a thumbnail up onto the canvas, or tap it to place it at the default position for its category (same positions as the Sprint 4 card).
- **On the canvas:** each placed item is a view with its own offset, scale and z-order.
  - drag to move
  - pinch to resize (clamp between 0.3× and 2.5×)
  - tap to select: shows a remove button and brings it to the front
- **State:** an array of `PlacedItem { itemId, x, y, scale, z }`, with x and y stored as fractions of the canvas size so the layout looks the same on any screen.
- **Save:** name (optional), occasion (optional picker). Creates an `Outfit` with source `manual`, its `OutfitItem` rows with slots inferred from category, and the layout array as JSON.
- **Entry points:** "New outfit" on the Outfits tab; "Edit" on any saved outfit (AI outfits open with the default card layout and become editable).
- Saved manual outfits render from their stored layout on the Outfits tab, not from the fixed card template.

**Fallback if drag and drop is not stable in time:** tap an item to add it to its slot using the fixed card layout, tap a slot to clear it. Same save path. Free-form dragging moves to Sprint 6.

### 2. Wear log (1.5 h)
- **Mark worn** on outfit detail and on result cards: writes a `WearLog` row (outfit id, item ids, date) and sets `lastWornAt` on each item. Default date today; a date picker allows yesterday or earlier.
- Item detail shows "Last worn" and wear count. Outfit detail shows its wear dates.
- Engine: `freshness` already reads `lastWornAt`. The soft `wornRecently` filter uses 2 days for tops and one-pieces and ignores footwear, outerwear and accessories.

### 3. Pair weights (2 h)
- A function in the package: `pairWeights(from events: [FeedbackEvent], outfits: …) → [PairKey: Double]`.
- Start every pair at 0.5. For each pair of items inside an outfit:
  - saved: +0.10
  - worn: +0.15
  - rejected (was shown, user asked for another): −0.03
  - swapped out: −0.10 for pairs involving the removed item, +0.05 for pairs involving its replacement
- Clamp to 0.1–1.0. Recompute from the event history each time the Stylist tab opens; it is cheap and avoids stored state going stale.
- Manual outfits count as saved: a pairing you made by hand is the strongest signal.
- Pass the result in `EngineContext.pairWeights`.

### 4. Set linking (1.5 h)
- In the wardrobe, multi-select items → "Link as a set". Assigns a shared `setGroupId` and a role per item (top, bottom, drape) by category. "Unlink" clears it.
- Linked items show a small set badge and appear under the Sets tab in the builder drawer.
- The engine already treats a `setGroupId` as one unit.

### 5. Export and import (1 h)
- Export: one JSON file with every item's merged tags, `aiRaw`, `userOverrides`, colours, set links, plus outfits and wear log. Shared through the system share sheet. Images are not included.
- Import (debug builds only): loads a file in the same format and creates items without images, shown with a placeholder. This is how the `wardrobe.json` fixture gets into a test build.

### 6. Settings (1 h)
- AI status: available or the reason it is not.
- Counts: items, outfits, AI calls this week, median tagging time.
- Export wardrobe.
- **Delete all data:** confirmation that names what will be removed (N items, M outfits, all photos), then deletes the store and the image folder.

## Expected behaviour

- Drag a shirt, trousers and shoes onto the canvas, nudge and resize them, save, close the app, reopen: the outfit looks exactly the same.
- Removing an item from the canvas does not delete it from the wardrobe.
- An outfit marked worn today is not in tomorrow's top 3 for the same occasion, but its shoes can be.
- After you save rust shirt + brown linen trousers three times in different outfits, that pair appears above rust shirt + black chinos for a festival.
- Rejecting an outfit once barely changes anything; swapping out the same shoes several times pushes them down.
- A linked kurta set is always suggested together.
- After Delete all data the app looks like a fresh install and the image folder is empty.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Dragging on the canvas scrolls the drawer or the page | Gesture conflict | Give the canvas its own gesture space; disable page scrolling while a canvas drag is active |
| Pinch moves the item instead of resizing | Drag and magnify gestures competing | Combine them as simultaneous gestures on the selected item only |
| Item jumps when a drag starts | Offset applied from the view origin, not from the touch point | Store the start offset on drag begin and add the translation |
| Layout looks different after reopening or on another device | Positions stored in points | Store fractions of canvas width and height |
| Items can be dragged off-screen and lost | No bounds | Clamp so at least a third of the item stays on the canvas |
| Can't select an item hidden under another | No z-order control | Tap brings to front; add "send to back" on the selected item |
| Dropping from the drawer does nothing | Drop target not registered or wrong payload type | Use the item id as the dragged payload; fall back to tap-to-add |
| Everything is "worn recently" and results dry up | Filter applied to all categories or too long a window | Tops and one-pieces only, 2 days, and soft (ignored if fewer than 3 outfits remain) |
| One early save dominates every suggestion | Increments too large or unclamped | Keep the small increments and the clamp; pair weight is only 15% of the score |
| Weights drift oddly over time | Stored weights updated incrementally with bugs | Always recompute from events |
| Half a set suggested with jeans | Role missing on one item, or set bypass in swap | Set items only through the set formula; swap on a set slot offers other sets, not single items |
| Delete all leaves files behind | Only the database was cleared | Remove the image root folder, then the store; test below |

## Tests

**Tests first.** Write the cases in [SPRINT_5_TESTS.md](SPRINT_5_TESTS.md) before the code for each build step. That file has the full unit, integration, eval and manual cases and the exit gate; the list below is only a summary.

- Layout round trip: save positions, reload, positions equal.
- Pair weights: three saves raise a pair above 0.5; one rejection lowers by 0.03; values stay within 0.1–1.0.
- Engine with weights: with a boosted pair, that pair ranks above an otherwise equal one.
- Freshness: an outfit whose top was worn yesterday is not in the top 3 when alternatives exist, and is when they do not.
- Set link then generate: both items always appear together.
- Export then import: item count and tags match.
- Delete all: zero rows in every table and an empty image folder.

## Checklist

- [ ] Builder: add by drag or tap, move, resize, remove, save
- [ ] Manual outfit reopens with identical layout
- [ ] AI outfits can be opened in the builder and edited
- [ ] Mark worn updates the log and `lastWornAt`
- [ ] Worn outfit is down-ranked next day
- [ ] Pair weights computed from events and passed to the engine
- [ ] Link and unlink a set from the wardrobe
- [ ] Export produces a readable JSON file
- [ ] Settings shows AI status and counts
- [ ] Delete all leaves no rows and no files
- [ ] All tests above pass

## How it lands

- Branch `sprint-5`, merge to `main`, tag `sprint-5-done`.
- Demo: build one outfit by hand, mark it worn, then show the stylist skipping it.
- By the end of this sprint the app is feature-complete for the MVP; Sprint 6 adds no new screens.

## Not this sprint

Personal rules in natural language, calendar view, sharing outfits, weather lookup, duplicate detection.
