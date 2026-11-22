import Foundation
import StyleEngine
import SwiftData
import SwiftUI
import WardrobeImaging

/// Composition root: built once in `AIStylistApp` and injected with `.environment(env)`. Holds the long-lived services
/// (AI provider, background tagging queue, image store) so no view or view model constructs a vendor type itself.
@MainActor @Observable final class AppEnvironment {
    let provider: any AIProvider
    let store: ImageStore
    let tagging: TaggingQueue
    /// Today's weather for the default `weatherFeel` (Open-Meteo, coarse location). Nil in tests that do not want the network.
    let weather: TodaysWeather?

    init(container: ModelContainer, provider: any AIProvider, store: ImageStore = .standard, weather: TodaysWeather? = nil) {
        self.provider = provider; self.store = store; self.weather = weather
        tagging = TaggingQueue(container: container, store: store, tagger: provider.makeTagger())
    }
}
