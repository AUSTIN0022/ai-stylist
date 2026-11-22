import CoreLocation
import Foundation
import StyleEngine

/// The real weather source: the phone's coarse location, then one Open-Meteo request (free, no key).
/// Location denied or unavailable returns nil, so no request is made and the weather stays `unknown`.
struct OpenMeteoSource: WeatherSource {
    func location() async -> (lat: Double, lon: Double)? {
        guard let l = await CoarseLocation.shared.current() else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }

    func snapshot(lat: Double, lon: Double) async throws -> WeatherSnapshot {
        guard let url = OpenMeteo.url(lat: lat, lon: lon) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 4
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let s = OpenMeteo.parse(data) else { throw URLError(.cannotParseResponse) }
        return s
    }
}

/// One-shot coarse location. Asks for permission the first time; `nil` when denied or when no fix arrives.
@MainActor final class CoarseLocation: NSObject, CLLocationManagerDelegate {
    static let shared = CoarseLocation()
    private let manager = CLLocationManager()
    private var auth: CheckedContinuation<Void, Never>?
    private var fix: CheckedContinuation<CLLocation?, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { auth = $0; manager.requestWhenInUseAuthorization() }
        }
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else { return nil }
        if let last = manager.location, abs(last.timestamp.timeIntervalSinceNow) < 6 * 3600 { return last }
        return await withCheckedContinuation { fix = $0; manager.requestLocation() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in if status != .notDetermined { auth?.resume(); auth = nil } }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in fix?.resume(returning: locations.last); fix = nil }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in fix?.resume(returning: nil); fix = nil }
    }
}
