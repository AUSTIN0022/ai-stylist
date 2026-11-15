import Foundation
import StyleEngine

/// Template images per garment shape: Application Support/templates/<file>.jpg (made in Settings > Developer) beats the one in the app bundle.
public struct TemplateStore: Sendable {
    public let directory: URL
    let bundled: @Sendable (TemplateShape) -> URL?

    public init(directory: URL, bundled: @escaping @Sendable (TemplateShape) -> URL?) { self.directory = directory; self.bundled = bundled }

    public static var standard: TemplateStore {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return TemplateStore(directory: base.appendingPathComponent("templates", isDirectory: true)) { shape in
            // Xcode's synced folder normally flattens App/Templates into the bundle root; the subfolder is checked too.
            Bundle.main.url(forResource: shape.fileName, withExtension: "jpg") ?? Bundle.main.url(forResource: shape.fileName, withExtension: "jpg", subdirectory: "Templates")
        }
    }

    func savedURL(_ shape: TemplateShape) -> URL { directory.appendingPathComponent(shape.fileName + ".jpg") }
    public func isSaved(_ shape: TemplateShape) -> Bool { FileManager.default.fileExists(atPath: savedURL(shape).path) }
    public func url(for shape: TemplateShape) -> URL? { isSaved(shape) ? savedURL(shape) : bundled(shape) }
    public var available: Set<TemplateShape> { Set(TemplateShape.allCases.filter { url(for: $0) != nil }) }

    public func save(_ jpeg: Data, for shape: TemplateShape) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: savedURL(shape), options: .atomic)
    }
    public func remove(_ shape: TemplateShape) { try? FileManager.default.removeItem(at: savedURL(shape)) }
}
