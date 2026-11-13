# Sprint 6: Own use and fixes

**Dates:** 21–27 Dec 2026 · **Planned:** 12 h · **Spec:** [PRD_MVP.md](../PRD_MVP.md) §8 (success metrics), §9 (open questions), P1 items

## Goal

Your whole wardrobe is in the app, you use it every day, the PRD's numbers are measured, and the next step is decided in writing.

No new screens this sprint. Work is: load data, measure, tune, fix.

## Needs from earlier sprints

Everything from Sprints 1–5 merged and running on the phone.

## What must exist at the end

| Piece | Behaviour |
|---|---|
| Full wardrobe | Every item you own, tagged and reviewed |
| Measurements | Each PRD success metric with its real number in `docs/EVAL_MVP.md` |
| Tuned engine | 2 of the top 3 wearable on all 10 test occasions |
| Fix list | The five most annoying problems from daily use fixed |
| Small additions (P1) | Duplicate check on add; today's weather filled in |
| Wider test (P1) | 10–15 women's and Indian garments tagged, accuracy recorded |
| Decision | What gets built next, written down |

## Work

### 1. Load the whole wardrobe (3 h, you)
- Two or three sessions of 20–25 items, using the in-app camera, not old photos, so the capture guide and quality check get real use.
- Review every item. Do not fix tags silently: every correction is recorded in `userOverrides`, which is the data for step 2.
- Link any sets. Archive anything you no longer wear.
- Note anything that annoys you in a running list (`docs/DOGFOOD_NOTES.md`): one line each, with the screen.

### 2. Measure (1.5 h)
Write `docs/EVAL_MVP.md` with one row per PRD metric:

| Metric | How to get the number |
|---|---|
| Tag accuracy per field | For every item, compare `aiRaw` with merged tags; a field with an override counts as wrong. Report per field |
| Edits per item | Median count of override keys |
| Time to add an item | Median of (ready time − created time); tagging share from the AI log |
| Cut-out success | Items with `cutoutFailed` or a retake, divided by total |
| Outfit acceptance | The rating sheet in step 3 |
| Intent to results | AI log `intent` duration plus engine time, median |
| Running cost | Confirm no paid provider is configured |
| Personal use | Days with at least one stylist request, from the AI log |

A debug screen or a small script over the exported JSON is enough; do not build a dashboard.

### 3. Rate and tune the engine (3 h)
- The rating sheet: 10 occasions (office, interview, date, party, Diwali at a friend's, wedding guest, temple visit, travel day, casual weekend, cold evening out). For each, look at the top 3 and mark each outfit wear / wouldn't wear, with a one-word reason for each no.
- Group the reasons. Typical groups and where the fix goes:

| Reason for "wouldn't wear" | Fix in |
|---|---|
| Too plain or too dark | Colour table: penalty for all-same-neutral; boost one accent |
| Too casual or too formal for the event | Occasion table: formality range |
| Wrong shoes | Occasion rules for footwear; `formalityMatch` weight |
| Clashing colours | Colour table clash list |
| Fine, but I always get the same thing | Diversity rule; `variety` and `freshness` weights |
| Item tagged wrongly | Not the engine: fix the tag, and note the field for step 2 |

- Change tables and weights only. After each change run the Sprint 3 tests; they assert properties, so they should still pass.
- Re-rate once after tuning. Record both rounds in `docs/EVAL_MVP.md`.

### 4. Fix the top five annoyances (3 h)
- Take the five items from `DOGFOOD_NOTES.md` that you hit most often. Fix those, nothing else.
- Crashes and data loss go first regardless of count.

### 5. Duplicate check on add (P1, 1.5 h)
- When a cut-out is made, compute an image feature print with Vision and store it on the item.
- On add, compare with existing items of similar colour; under a distance threshold, ask "Is this the same as <item>?" with Same (discard the new one, or replace the photo) and Different.
- Set the threshold from your own wardrobe: the two pairs of black chinos should read as different or at least ask; the same shirt photographed twice should match.

### 6. Today's weather (P1, 1 h)
- One request to Open-Meteo (free, no key) for the phone's coarse location: today's feels-like max and min and rain chance. Cache for the day.
- Map to `weatherFeel`: hot, mild, cold, rainy. Use it as the default when the user's message does not mention weather; the intent chip shows it and can be changed.
- If location is denied or the request fails, `weatherFeel` stays `unknown` and nothing breaks.

### 7. Wider garment test (P1, 1.5 h, you)
- Collect 10–15 single-item photos of garments your wardrobe lacks: saree, blouse, lehenga, kurti, dupatta, dress, heels, kurta set, sherwani or Nehru jacket. Use photos you took yourself of family members' clothes, with their permission, processed on-device only.
- Run them through the normal add flow. Record per field whether the tag was right.
- Add the result to `docs/EVAL_MVP.md` as a separate table. This is the first evidence for the women-first, Indian-wear plan in the brief.

### 8. Optional: TestFlight (stretch)
- Needs the paid Apple developer account. Testers need an iPhone that supports Apple Intelligence.
- All processing is on-device, so no other person's photos leave their phone; the rule about a paid AI tier does not apply while the tagger is on-device. It does apply if the tagger was switched to Gemini.
- Add a one-screen privacy note before the first photo: photos stay on this phone; delete everything from Settings.

### 9. Decide what is next
Write the decision at the top of `docs/EVAL_MVP.md`. Inputs: the measured numbers, how many days you actually used it, the wider garment test, and the research note's concerns (a direct competitor; Android reach).

| If | Then |
|---|---|
| You used it most days and outfits are good | Plan the cross-platform launch build (brief §5), porting the taxonomy and engine tables; wedding planner first |
| Tagging or outfits are still weak after tuning | One more sprint on tags and rules before anything else; or move tagging to a paid model and re-measure |
| You stopped using it after a few days | Write down why. That is the most useful finding; do not start the launch build |

## Expected behaviour

- Asking for an outfit on a normal morning takes under 10 seconds from opening the app to a card you would wear.
- A week passes with no crash and no lost item.
- Adding the same shirt twice asks whether it is a duplicate.
- On a cold day the default suggestions include a layer without you saying so.

## What can go wrong and how to fix it

| Wrong behaviour | Likely cause | Fix |
|---|---|---|
| Accuracy looks far worse than Sprint 0 | Real photos are messier than the eval set, or you corrected to a near-synonym (cotton → cottonLinen) | Report strict and lenient accuracy; improve the capture guide text before touching prompts |
| Tuning for one occasion breaks another | Weights changed globally | Prefer per-occasion table changes; re-rate all 10 after each change |
| Sprint 3 tests fail after tuning | A test asserted too exact a result, or a real regression | Read the failing property; if it still describes good behaviour, the tuning is wrong |
| Engine slow with the full wardrobe | More seeds and candidates than the fixture | Check the 200-item speed test; cap candidates per slot |
| Duplicate check asks on every black item | Threshold too loose | Tighten; compare only within the same subcategory |
| Weather request blocks or fails | No network or location denied | Run it in the background with a short timeout; fall back to `unknown` |
| The fix list keeps growing | Fixing as you find | Only the top five this sprint; the rest stays in the notes file |
| You stop using the app mid-week | It is slower than deciding yourself | Note the exact moment and reason in `DOGFOOD_NOTES.md`; this drives the step 9 decision |

## Tests

**Tests first** for the duplicate check, weather and each fix. Full cases, final evals, the rating sheet and the manual acceptance pass are in [SPRINT_6_TESTS.md](SPRINT_6_TESTS.md).

## Checklist

- [ ] Every owned item added, reviewed, sets linked
- [ ] `docs/DOGFOOD_NOTES.md` kept through the week
- [ ] Every PRD metric measured and written to `docs/EVAL_MVP.md`
- [ ] Rating sheet done before and after tuning
- [ ] 2 of top 3 wearable on all 10 occasions
- [ ] Sprint 3 tests still pass after tuning
- [ ] Top five annoyances fixed
- [ ] Duplicate check works on a repeated photo
- [ ] Weather fills `weatherFeel` and fails quietly
- [ ] 10–15 women's and Indian garments tested, results recorded
- [ ] No crash in 7 days
- [ ] 14-day use streak started
- [ ] Next-step decision written on line 1 of `docs/EVAL_MVP.md`

## How it lands

- Branch `sprint-6`, merge to `main`, tag `mvp-prototype-done`.
- Update the status line in `docs/PRD_MVP.md` and the note at the top of `PROJECT_BRIEF.md` with the decision.

## Not this sprint

Any new feature not listed above, backend work, Android, subscriptions.
