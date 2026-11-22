import CoreGraphics
import Foundation
import Vision

/// Vision image feature prints for the duplicate check. A print is stored as archived data on the item.
public enum FeaturePrint {
    public static func compute(from image: CGImage) -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let obs = request.results?.first else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
    }

    private static func observation(_ d: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: d)
    }

    /// nil when either print cannot be read (or they came from different Vision revisions).
    public static func distance(_ a: Data, _ b: Data) -> Double? {
        guard let x = observation(a), let y = observation(b) else { return nil }
        var d: Float = 0
        guard (try? x.computeDistance(&d, to: y)) != nil else { return nil }
        return Double(d)
    }
}
