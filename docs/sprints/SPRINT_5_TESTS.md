# Sprint 5 Tests: Manual builder and memory

Sprint: [SPRINT_5.md](SPRINT_5.md) · Rules and eval definitions: [TEST_PLAN.md](../TEST_PLAN.md)

Gestures themselves (drag, pinch) are tested by hand. The state they change is plain data and is unit-tested: every gesture ends in a call like `move(item, by:)` or `scale(item, to:)`, and those are what the tests drive.

Order of work: canvas state tests → wear tests → pair-weight tests → set tests → export tests → delete tests → integration → UI.

## Unit tests (Mac)

### Canvas state (build step 1)

| ID | Case | Given → Then |
|---|---|---|
| S5-U01 | Positions are fractions | place at the centre of a 300×400 canvas → stored x 0.5, y 0.5; rendered on a 600×800 canvas at its centre |
| S5-U02 | Scale clamp | scale to 0.1 → 0.3; scale to 5 → 2.5 |
| S5-U03 | Bounds clamp | move far off the right edge → at least a third of the item stays on the canvas |
| S5-U04 | Bring to front | select the bottom item → its z is the highest |
| S5-U05 | Remove from canvas | removing a placed item leaves the wardrobe item untouched |
| S5-U06 | Slot inference | shirt → top, chinos → bottom, sneakers → footwear, hoodie → outerwear, second top → base layer or overlayer by category rules |
| S5-U07 | Default position on tap-to-add | each category lands at its default card position; adding the same item twice does not duplicate it |

### Wear log (build step 2)

| ID | Case | Given → Then |
|---|---|---|
| S5-U08 | Mark worn | one `WearLog` row with outfit id, item ids and date; each item's `lastWornAt` updated |
| S5-U09 | Backdated wear | marking worn for last week does not overwrite a more recent `lastWornAt` |
| S5-U10 | Recently-worn window | top worn yesterday → soft-rejected; footwear, outerwear and accessories worn yesterday → not rejected; top worn 3 days ago → not rejected |

### Pair weights (build step 3)

| ID | Case | Given → Then |
|---|---|---|
| S5-U11 | Starting value | no events → every pair 0.5 |
| S5-U12 | Saved | one saved outfit of A, B, C → pairs AB, AC, BC each 0.60 |
| S5-U13 | Worn | outfit worn once → its pairs +0.15 |
| S5-U14 | Rejected | outfit rejected once → its pairs −0.03 |
| S5-U15 | Swapped | shoes X swapped for Y → pairs with X −0.10, pairs with Y +0.05 |
| S5-U16 | Clamp and recompute | 20 saves → 1.0, never above; 40 rejections → 0.1, never below; computing twice from the same events gives the same result; a manual outfit counts as saved |

### Sets (build step 4)

| ID | Case | Given → Then |
|---|---|---|
| S5-U17 | Link | linking a kurta and pyjama gives both the same `setGroupId` and roles by category |
| S5-U18 | Unlink | both lose the id and role; other sets untouched |
| S5-U19 | Invalid link | linking two tops, or a single item, is refused with a reason |

### Export, import, settings, delete (build steps 5, 6)

| ID | Case | Given → Then |
|---|---|---|
| S5-U20 | Export content | file has every item with merged tags, raw tags, overrides, colours, set links, plus outfits and wear log; no image data |
| S5-U21 | Round trip | export then import into an empty store → same item count, tags, sets and outfits |
| S5-U22 | Import without images | imported items show a placeholder and are usable by the engine |
| S5-U23 | Settings counts | item, outfit and AI-call counts match the store |
| S5-U24 | Delete all | every table has zero rows afterwards |

## Integration tests (Mac, seeded store)

| ID | Case | Then |
|---|---|---|
| S5-I01 | Manual outfit end to end | Place three items, save, reopen the store → outfit has source manual, three items, and the same layout to within rounding |
| S5-I02 | Worn today, skipped tomorrow | Mark an outfit worn with date D; run the engine with today = D+1 → that outfit is not in the top 3 while alternatives exist; with today = D+5 it can be |
| S5-I03 | Learning changes ranking | Save pair A+B in three outfits; run the engine → an outfit with A+B ranks above an otherwise equal one |
| S5-I04 | Linked set is suggested together | Link two items in the store; run the engine with `preferIndian` → both always in the same outfit |
| S5-I05 | Delete all removes files | After delete all, the image root folder is empty and every table has zero rows |
| S5-I06 | AI outfit opened in the builder | Opens with the default card layout; after moving one item and saving, the layout persists and the source stays ai |
| S5-I07 | Manual outfit counts as feedback | Saving a manual outfit writes a `saved` event |

## UI smoke test

| ID | Case | Then |
|---|---|---|
| S5-UI01 | Launch with `-uiTesting`, Outfits → New outfit, tap three drawer items to add them, Save, reopen the outfit | Three items on the canvas after reopening |

## Evals

No new model work this sprint. One check on learning, recorded in `docs/EVAL_ENGINE.md`:

| Check | Do | Pass |
|---|---|---|
| Learning is gentle | Before and after saving 5 outfits and rejecting 5 on your real wardrobe, run the Diwali and office requests | Top results shift toward saved pairs; no single pair appears in all three results |

## Manual test script (iPhone 17)

| Step | Do | Expected | Pass |
|---|---|---|---|
| S5-M01 | Outfits → New outfit; drag a shirt from the drawer onto the canvas | It follows your finger and stays where dropped; the drawer does not scroll during the drag | ☐ |
| S5-M02 | Add trousers and shoes by tapping; drag each around | No jump when a drag starts; items cannot be lost off-screen | ☐ |
| S5-M03 | Pinch the shirt bigger and smaller | Resizes smoothly within limits; does not move the others | ☐ |
| S5-M04 | Tap an item under another; tap remove on one | Tapped item comes to the front; removed item leaves the canvas and is still in the wardrobe | ☐ |
| S5-M05 | Save with a name and occasion; close the app; reopen the outfit | Same items, positions and sizes | ☐ |
| S5-M06 | Look at the Outfits tab | Manual and AI outfits together; the manual one drawn with your layout | ☐ |
| S5-M07 | Open a saved AI outfit, tap Edit, move something, save | Change is kept | ☐ |
| S5-M08 | Mark an outfit worn today; open the item | "Last worn: today" and a wear count | ☐ |
| S5-M09 | Ask the stylist for the same occasion again | The worn outfit is not in the first three | ☐ |
| S5-M10 | Select a kurta and its bottom in the wardrobe → Link as a set | Set badge on both; they appear under Sets in the builder | ☐ |
| S5-M11 | Ask for a festival outfit with Indian wear | The set comes out together | ☐ |
| S5-M12 | Settings → Export | Share sheet opens; the file is readable JSON with your items | ☐ |
| S5-M13 | Settings shows AI status and counts | Numbers look right | ☐ |
| S5-M14 | Export first, then Settings → Delete all data | Confirmation names the counts; afterwards the app is empty, including after restart | ☐ |

Do M14 last, and only after the export in M12.

## Exit gate

- [ ] S5-U01 to U24 pass
- [ ] S5-I01 to I07 pass
- [ ] S5-UI01 passes
- [ ] Sprints 0–4 tests still pass
- [ ] Learning check recorded
- [ ] Manual steps M01 to M14 pass (if the tap-to-add fallback was used, M01 and M03 are marked "deferred to Sprint 6" with a note)
- [ ] No severity 1 or 2 defect open

## Results

| Date | Automated | Evals | Manual | Open defects | Notes |
|---|---|---|---|---|---|
| | | | | | |
