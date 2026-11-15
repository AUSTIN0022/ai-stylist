import SwiftUI
import WardrobeImaging

extension Color {
    /// Catalogue backdrop #F4F4F2: behind every item image (wardrobe cells, outfit cards). One source: `Catalogue.background`.
    static let catalogueGrey = Color(red: Double(Catalogue.background.r) / 255, green: Double(Catalogue.background.g) / 255, blue: Double(Catalogue.background.b) / 255)

    /// "RRGGBB" (no #) as a colour.
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}
