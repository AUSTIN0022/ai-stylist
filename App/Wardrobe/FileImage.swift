import SwiftUI
import WardrobeImaging

extension Notification.Name {
    /// Posted (object: the item's UUID) after an item's image files were rewritten in place under the same names
    /// (adjusted cut-out, retake, refreshed catalogue image). Views showing those files reload.
    static let itemImagesChanged = Notification.Name("itemImagesChanged")
}

/// Downsampled image from disk, decoded off the main thread. Reloads when the file is rewritten in place.
struct FileImage: View {
    let url: URL
    /// Shown when `url` does not exist (re-checked on every reload): product.jpg first, catalogue image behind it.
    var fallback: URL?
    var maxPixel = 400
    @State private var image: CGImage?
    @State private var reloads = 0

    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() } else { Color.white }
        }
        .task(id: "\(url.path)#\(reloads)") {
            let (u, m) = (FileManager.default.fileExists(atPath: url.path) ? url : (fallback ?? url), maxPixel)
            image = await Task.detached { ImageCodec.cachedThumbnail(at: u, maxPixel: m) }.value
        }
        .onReceive(NotificationCenter.default.publisher(for: .itemImagesChanged)) { n in
            if let id = n.object as? UUID, url.path.contains(id.uuidString) { reloads += 1 }
        }
    }
}
