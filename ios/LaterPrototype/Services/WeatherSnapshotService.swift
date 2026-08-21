import Foundation
import CoreLocation

/// Looks up the weather for a memory's place and day using Open-Meteo, which
/// needs no API key. Recent days come from the forecast endpoint; older days
/// from the historical archive.
nonisolated enum WeatherSnapshotService {
    private struct Response: Decodable {
        struct Daily: Decodable {
            let weather_code: [Int?]?
            let temperature_2m_max: [Double?]?
        }
        let daily: Daily?
    }

    /// Fetches the day's peak temperature and conditions. Returns nil when
    /// the service has no data for that day or the request fails.
    static func fetch(coordinate: CLLocationCoordinate2D, date: Date) async -> WeatherSnapshot? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let day = formatter.string(from: min(date, Date()))

        let daysAgo = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0

        // The archive lags a few days behind; the forecast endpoint covers
        // roughly the last three months plus the future.
        let base = daysAgo > 60
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast"

        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
        ]
        guard let url = components.url else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let code = decoded.daily?.weather_code?.first ?? nil
        let temperature = decoded.daily?.temperature_2m_max?.first ?? nil
        guard code != nil || temperature != nil else { return nil }
        return WeatherSnapshot(temperatureCelsius: temperature, weatherCode: code, mood: nil)
    }
}
