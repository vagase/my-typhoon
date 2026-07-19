import Foundation
import CoreLocation

struct TrackPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let coordinate: CLLocationCoordinate2D
    let pressure: Int
    let windSpeed: Double
    let grade: String
    let forecastHour: Int?

    var windForce: Int {
        switch windSpeed {
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
        default: return max(1, Int(windSpeed / 2))
        }
    }
}

struct WindRadii: Sendable {
    let level: String
    let northeast: Double
    let southeast: Double
    let southwest: Double
    let northwest: Double

    var maximum: Double { max(northeast, southeast, southwest, northwest) }
}

struct TyphoonSnapshot: Sendable {
    let name: String
    let englishName: String
    let number: String
    let current: TrackPoint
    let recentTrack: [TrackPoint]
    let forecast: [TrackPoint]
    let windRadii: [WindRadii]
    let direction: String
    let movementSpeed: Double
    let issuedAt: Date

    var windImpact: ImpactLevel {
        switch current.windSpeed {
        case 41.5...: .extreme
        case 32.7..<41.5: .high
        case 24.5..<32.7: .medium
        default: .low
        }
    }

    var rainImpact: ImpactLevel {
        // NMC track data does not contain point rainfall. This is an explicitly
        // labelled indication based on cyclone intensity and circulation size.
        let radius = windRadii.first(where: { $0.level == "30KTS" })?.maximum ?? 0
        if current.windSpeed >= 41.5 || radius >= 400 { return .high }
        if current.windSpeed >= 24.5 || radius >= 250 { return .medium }
        return .low
    }

    var waveImpact: ImpactLevel {
        current.windSpeed >= 32.7 ? .extreme : (current.windSpeed >= 24.5 ? .high : .medium)
    }
}

enum ImpactLevel: String, Sendable {
    case low = "较低"
    case medium = "关注"
    case high = "较高"
    case extreme = "很高"
}

extension TrackPoint {
    static let fallbackCurrent = TrackPoint(
        date: Date(),
        coordinate: CLLocationCoordinate2D(latitude: 27.4, longitude: 121.9),
        pressure: 950,
        windSpeed: 40,
        grade: "TY",
        forecastHour: nil
    )
}
