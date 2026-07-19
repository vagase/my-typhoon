import Foundation
import CoreLocation

struct HourlyWeather: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let precipitation: Double
    let precipitationProbability: Int
    let windSpeed: Double
    let windGust: Double
}

struct LocalWeatherForecast: Sendable {
    let coordinate: CLLocationCoordinate2D
    let timezone: String
    let hourly: [HourlyWeather]
}

actor LocalWeatherService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func fetch(at coordinate: CLLocationCoordinate2D) async throws -> LocalWeatherForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "precipitation,precipitation_probability,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_hours", value: "72")
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: payload.timezone)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let count = [payload.hourly.time.count, payload.hourly.precipitation.count,
                     payload.hourly.precipitationProbability.count,
                     payload.hourly.windSpeed.count, payload.hourly.windGust.count].min() ?? 0
        let points = (0..<count).compactMap { index -> HourlyWeather? in
            guard let date = formatter.date(from: payload.hourly.time[index]) else { return nil }
            return HourlyWeather(
                date: date,
                precipitation: payload.hourly.precipitation[index],
                precipitationProbability: payload.hourly.precipitationProbability[index],
                windSpeed: payload.hourly.windSpeed[index],
                windGust: payload.hourly.windGust[index]
            )
        }
        return LocalWeatherForecast(coordinate: coordinate, timezone: payload.timezone, hourly: points)
    }

    private struct Response: Decodable {
        let timezone: String
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [String]
            let precipitation: [Double]
            let precipitationProbability: [Int]
            let windSpeed: [Double]
            let windGust: [Double]

            enum CodingKeys: String, CodingKey {
                case time, precipitation
                case precipitationProbability = "precipitation_probability"
                case windSpeed = "wind_speed_10m"
                case windGust = "wind_gusts_10m"
            }
        }
    }
}
