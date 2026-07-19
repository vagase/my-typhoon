import Foundation
import CoreLocation

struct WindFieldSample: Identifiable, Sendable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let speed: Double
    let gust: Double
    let observedAt: Date

    var windForce: Int {
        switch speed {
        case 61.3...: return 17
        case 56.1..<61.3: return 16
        case 51.0..<56.1: return 15
        case 46.2..<51.0: return 14
        case 41.5..<46.2: return 13
        case 36.9..<41.5: return 12
        case 32.7..<36.9: return 11
        case 28.5..<32.7: return 10
        case 24.5..<28.5: return 9
        case 20.8..<24.5: return 8
        case 17.2..<20.8: return 7
        case 13.9..<17.2: return 6
        case 10.8..<13.9: return 5
        default: return max(1, Int(speed / 2.5))
        }
    }
}

actor WindFieldService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func fetch(around center: CLLocationCoordinate2D) async throws -> [WindFieldSample] {
        let offsets = [-3.75, -2.5, -1.25, 0, 1.25, 2.5, 3.75]
        var coordinates: [CLLocationCoordinate2D] = []
        for latitudeOffset in offsets {
            let latitude = center.latitude + latitudeOffset
            let longitudeScale = max(0.35, cos(latitude * .pi / 180))
            for longitudeOffset in offsets {
                coordinates.append(CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: center.longitude + longitudeOffset / longitudeScale
                ))
            }
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinates.map { String(format: "%.4f", $0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: coordinates.map { String(format: "%.4f", $0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let payloads = try JSONDecoder().decode([Response].self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return payloads.compactMap { payload in
            guard let date = formatter.date(from: payload.current.time) else { return nil }
            return WindFieldSample(
                coordinate: CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude),
                speed: payload.current.windSpeed,
                gust: payload.current.windGust,
                observedAt: date
            )
        }
    }

    private struct Response: Decodable {
        let latitude: Double
        let longitude: Double
        let current: Current

        struct Current: Decodable {
            let time: String
            let windSpeed: Double
            let windGust: Double
            enum CodingKeys: String, CodingKey {
                case time
                case windSpeed = "wind_speed_10m"
                case windGust = "wind_gusts_10m"
            }
        }
    }
}
