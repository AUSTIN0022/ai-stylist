import Foundation
import StyleEngine
import WardrobeImaging

extension ReviewModel {
    enum Status { case processing, ready, failed, saved, discarded }
    enum TagState: Equatable { case idle, running, done, failed(String) }

    /// One page of the review: the processed images plus everything the user and the AI have said about it so far.
    struct Photo: Identifiable {
        var id = UUID()
        var status = Status.processing
        var processed: ProcessedImages?
        var overrides = ItemTags()          // fit etc.; saved as userOverridesData, never aiRaw
        var colorAnswer: ColorName?         // replaces the first colour name; hex unchanged
        var colorDone = false, fitDone = false
        var ai: IdentityTags?               // the tagger's answer to call A (AI output; saved to aiRaw, never to overrides)
        var aiMore = ItemTags()             // calls B and C (fabric, pattern, dress codes...); AI output too
        var tagState = TagState.idle
        var aiVersion: String?
        var showAllChoices = false          // "Something else": full category and subcategory lists
        var label: LabelData?               // confirmed; label.jpg already in the item folder
        var labelScan: LabelData?           // the same label as the scanner parsed it, before the user's edits
        var error: String?                  // last re-cut problem
        var featurePrint: Data?             // Vision print of the cut-out; saved on the item for the duplicate check
        var duplicate: DuplicateOffer?      // an existing item this photo may repeat; nil once answered or when none is close
        var duplicateDismissed = false      // the user said "Different"
        var presetCategory: Category?       // added from a category page: that category is the answer; the AI's is only cross-checked
        var existingID: UUID?               // Review again: the saved item this page edits in place (nil for a new photo)

        /// The AI's whole answer for the page (calls A, B and C).
        var rawTags: ItemTags {
            var t = aiMore
            if let a = ai { t.category = a.category; t.subcategory = a.subcategory; t.styleOrigin = a.styleOrigin }
            return t
        }
        /// aiRaw < label < the user's corrections, as the item will read after Save.
        var effectiveTags: ItemTags { ItemTags.effective(aiRaw: rawTags, label: label, userOverrides: overrides) }

        /// A new photo; with `preset` it starts in that category (it is the user's answer, stored as a correction only if the AI differs).
        init(preset: Category? = nil) {
            presetCategory = preset
            overrides.category = preset
        }

        /// A page for a saved item (Review again / Sort these), loaded from its stored files, tags and label.
        init(existing item: Item) {
            existingID = item.id
            let names = item.colorNames.compactMap(ColorName.init(rawValue:))
            // Ask about the colour only while it still shows the extracted name (a differing name was a user answer).
            let ambiguous = names.indices.map { i in
                item.hexColors.indices.contains(i) && ColorExtractor.classify(hex: item.hexColors[i]).name == names[i] && ColorExtractor.classify(hex: item.hexColors[i]).ambiguous
            }
            processed = ProcessedImages(itemID: item.id, originalFile: item.originalFile, cutoutFile: item.cutoutFile, displayFile: item.displayFile,
                                        hexColors: item.hexColors, colorNames: names, cutoutFailed: item.cutoutFailed, lastError: item.lastError,
                                        colorAmbiguous: ambiguous)
            overrides = item.userOverridesData.flatMap { try? JSONDecoder().decode(ItemTags.self, from: $0) } ?? ItemTags()
            label = item.label
            labelScan = item.labelScan
            fitDone = item.tags.fit != nil
            colorDone = ambiguous.first != true
            if let raw = item.aiRawData.flatMap({ try? JSONDecoder().decode(ItemTags.self, from: $0) }),
               let c = raw.category, let s = raw.subcategory, let o = raw.styleOrigin {
                ai = IdentityTags(category: c, subcategory: s, styleOrigin: o); aiVersion = item.taggerVersion
                aiMore = raw; aiMore.category = nil; aiMore.subcategory = nil; aiMore.styleOrigin = nil
                tagState = .done
            }
            status = .ready
        }
    }
}
