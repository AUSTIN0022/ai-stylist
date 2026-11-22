import Foundation

// Sprint 6: today's weather as a default `weatherFeel`. Pure logic and a seam; the real network and location live in the app.

public struct WeatherSnapshot: Equatable, Sendable, Codable {
    public var feelsLikeMax: Double      // °C
    public var feelsLikeMin: Double
    public var rainChance: Double        // percent, 0...100
    public init(feelsLikeMax: Double, feelsLikeMin: Double, rainChance: Double) {
        self.feelsLikeMax = feelsLikeMax; self.feelsLikeMin = feelsLikeMin; self.rainChance = rainChance
    }
}

/// Thresholds as data: tune here.
public enum WeatherFeelMapper {
    public static let rainyFrom = 60.0       // % chance of rain; rain wins over temperature
    public static let hotFrom = 32.0         // feels-like max, °C
    public static let coldBelow = 18.0

    public static func feel(_ w: WeatherSnapshot) -> WeatherFeel {
        if w.rainChance >= rainyFrom { return .rainy }
        if w.feelsLikeMax >= hotFrom { return .hot }
        if w.feelsLikeMax < coldBelow { return .cold }
        return .mild
    }
}

/// Where the weather comes from. `location` is nil when the user has not allowed it (no request is made then).
public protocol WeatherSource: Sendable {
    func location() async -> (lat: Double, lon: Double)?
    func snapshot(lat: Double, lon: Double) async throws -> WeatherSnapshot
}

/// One request per calendar day (cached), never blocks for long, never throws: anything wrong gives `.unknown`.
public actor TodaysWeather {
    private let source: WeatherSource, calendar: Calendar, timeout: Duration
    private var cached: (day: DateComponents, feel: WeatherFeel)?

    public init(source: WeatherSource, calendar: Calendar = .current, timeout: Duration = .seconds(4)) {
        self.source = source; self.calendar = calendar; self.timeout = timeout
    }

    public func feel(on date: Date) async -> WeatherFeel {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        if let c = cached, c.day == day { return c.feel }
        guard let loc = await source.location() else { return .unknown }
        let source = source, timeout = timeout
        let snapshot: WeatherSnapshot? = await withTaskGroup(of: WeatherSnapshot?.self) { group in
            group.addTask { try? await source.snapshot(lat: loc.lat, lon: loc.lon) }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let snapshot else { return .unknown }       // failures are not cached: the next call tries again
        let f = WeatherFeelMapper.feel(snapshot)
        cached = (day, f)
        return f
    }
}

/// Open-Meteo (free, no key): today's feels-like max and min and rain chance.
public enum OpenMeteo {
    /// Coordinates are rounded to one decimal (about 10 km): enough for the weather, coarse for privacy.
    public static func url(lat: Double, lon: Double) -> URL? {
        func r(_ v: Double) -> String { String(format: "%.1f", (v * 10).rounded() / 10) }
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(r(lat))&longitude=\(r(lon))"
            + "&daily=apparent_temperature_max,apparent_temperature_min,precipitation_probability_max&timezone=auto&forecast_days=1")
    }

    public static func parse(_ data: Data) -> WeatherSnapshot? {
        struct Reply: Decodable {
            struct Daily: Decodable {
                var apparent_temperature_max: [Double?]?
                var apparent_temperature_min: [Double?]?
                var precipitation_probability_max: [Double?]?
            }
            var daily: Daily?
        }
        guard let d = (try? JSONDecoder().decode(Reply.self, from: data))?.daily,
              let hi = d.apparent_temperature_max?.first ?? nil, let lo = d.apparent_temperature_min?.first ?? nil else { return nil }
        return WeatherSnapshot(feelsLikeMax: hi, feelsLikeMin: lo, rainChance: (d.precipitation_probability_max?.first ?? nil) ?? 0)
    }
}
