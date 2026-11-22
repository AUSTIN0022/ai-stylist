import Foundation
import Testing
@testable import StyleEngine

// S6-U06..U09 (+ the Open-Meteo JSON): the network is always a stub.

private final class StubSource: WeatherSource, @unchecked Sendable {
    var coordinates: (lat: Double, lon: Double)? = (12.9, 77.6)
    var result: Result<WeatherSnapshot, Error> = .success(WeatherSnapshot(feelsLikeMax: 24, feelsLikeMin: 18, rainChance: 10))
    var hang = false
    private(set) var requests = 0, locationAsks = 0
    func location() async -> (lat: Double, lon: Double)? { locationAsks += 1; return coordinates }
    func snapshot(lat: Double, lon: Double) async throws -> WeatherSnapshot {
        requests += 1
        if hang { try await Task.sleep(for: .seconds(60)) }
        return try result.get()
    }
    struct Boom: Error {}
}

private func at(_ day: Int, hour: Int = 9) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 12, day: day, hour: hour))!
}
private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

@Suite("S6 weather") struct WeatherTests {
    @Test("S6-U06 mapping: hot, mild, cold, and rain wins") func mapping() {
        func f(_ max: Double, _ rain: Double = 0) -> WeatherFeel { WeatherFeelMapper.feel(WeatherSnapshot(feelsLikeMax: max, feelsLikeMin: max - 6, rainChance: rain)) }
        #expect(f(36) == .hot)
        #expect(f(24) == .mild)
        #expect(f(12) == .cold)
        #expect(f(36, 70) == .rainy)
        #expect(f(12, 70) == .rainy)
        #expect(f(36, 30) == .hot)
    }

    @Test("S6-U07 a failed request is quiet") func failure() async {
        let s = StubSource(); s.result = .failure(StubSource.Boom())
        let w = TodaysWeather(source: s, calendar: utc)
        #expect(await w.feel(on: at(1)) == .unknown)
    }

    @Test("S6-U07 a hanging request times out to unknown") func timeout() async {
        let s = StubSource(); s.hang = true
        let w = TodaysWeather(source: s, calendar: utc, timeout: .milliseconds(50))
        let start = ContinuousClock.now
        #expect(await w.feel(on: at(1)) == .unknown)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("S6-U08 location denied: unknown and no request") func denied() async {
        let s = StubSource(); s.coordinates = nil
        let w = TodaysWeather(source: s, calendar: utc)
        #expect(await w.feel(on: at(1)) == .unknown)
        #expect(s.requests == 0)
    }

    @Test("S6-U09 cached for the day, new request the next day") func cache() async {
        let s = StubSource(); s.result = .success(WeatherSnapshot(feelsLikeMax: 36, feelsLikeMin: 28, rainChance: 0))
        let w = TodaysWeather(source: s, calendar: utc)
        #expect(await w.feel(on: at(1, hour: 8)) == .hot)
        #expect(await w.feel(on: at(1, hour: 20)) == .hot)
        #expect(s.requests == 1)
        s.result = .success(WeatherSnapshot(feelsLikeMax: 12, feelsLikeMin: 6, rainChance: 0))
        #expect(await w.feel(on: at(2)) == .cold)
        #expect(s.requests == 2)
    }

    @Test("a failure is not cached: the next call tries again") func retry() async {
        let s = StubSource(); s.result = .failure(StubSource.Boom())
        let w = TodaysWeather(source: s, calendar: utc)
        _ = await w.feel(on: at(1))
        s.result = .success(WeatherSnapshot(feelsLikeMax: 36, feelsLikeMin: 28, rainChance: 0))
        #expect(await w.feel(on: at(1)) == .hot)
    }

    @Test("Open-Meteo daily JSON is read") func parse() throws {
        let json = #"{"latitude":12.9,"daily":{"time":["2026-12-01"],"apparent_temperature_max":[33.4],"apparent_temperature_min":[21.0],"precipitation_probability_max":[55]}}"#
        let s = try #require(OpenMeteo.parse(Data(json.utf8)))
        #expect(s == WeatherSnapshot(feelsLikeMax: 33.4, feelsLikeMin: 21.0, rainChance: 55))
        #expect(OpenMeteo.parse(Data("{}".utf8)) == nil)
        #expect(OpenMeteo.parse(Data("nope".utf8)) == nil)
        // No rain figure at all counts as no rain.
        let dry = #"{"daily":{"apparent_temperature_max":[30],"apparent_temperature_min":[20]}}"#
        #expect(OpenMeteo.parse(Data(dry.utf8))?.rainChance == 0)
    }

    @Test("the request URL carries coarse coordinates only") func url() throws {
        let u = try #require(OpenMeteo.url(lat: 12.97163, lon: 77.59456))
        #expect(u.absoluteString.contains("latitude=13.0") && u.absoluteString.contains("longitude=77.6"))
        #expect(!u.absoluteString.contains("12.97"))
        #expect(u.host == "api.open-meteo.com")
    }
}
