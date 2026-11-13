import FoundationModels

/// Model availability as text for the Wardrobe banner and Settings. Pure mapping (S2-U29).
enum AIStatus {
    struct Info: Equatable { var banner: String?; var manualMode: Bool }

    static func describe(reason: String?) -> Info {
        guard let reason else { return Info(banner: nil, manualMode: false) }
        return Info(banner: "AI tagging is off. \(reason) You can still add items and tag them by hand; they can be tagged by the AI later.", manualMode: true)
    }
    /// Reads the system model now.
    static var current: Info { describe(reason: SpikeTagger.unavailableReason()) }
}
