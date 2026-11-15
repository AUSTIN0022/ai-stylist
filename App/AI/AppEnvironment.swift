import Foundation
import SwiftData
import SwiftUI
import WardrobeImaging

/// Composition root: built once in `AIStylistApp` and injected with `.environment(env)`. Holds the long-lived services
/// (AI provider, background tagging queue, image store) so no view or view model constructs a vendor type itself.
@MainActor @Observable final class AppEnvironment {
    let provider: any AIProvider
    let store: ImageStore
    let tagging: TaggingQueue

    init(container: ModelContainer, provider: any AIProvider, store: ImageStore = .standard) {
        self.provider = provider; self.store = store
        tagging = TaggingQueue(container: container, store: store, tagger: provider.makeTagger())
    }
}
