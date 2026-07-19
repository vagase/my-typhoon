import Foundation
import CoreLocation

enum NMCServiceError: LocalizedError {
    case malformedResponse
    case missingTrack

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "中央气象台返回了无法识别的数据"
        case .missingTrack: "暂时没有可用的台风路径"
        }
    }
}

actor NMCService {
    private let session: URLSession
    private let baseURL = "https://typhoon.nmc.cn/weatherservice/typhoon/jsons"
    private var snapshotCache: [Int: TyphoonSnapshot] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func fetchRecentTyphoons(since cutoff: Date) async throws -> [TyphoonSummary] {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())
        let cutoffYear = calendar.component(.year, from: cutoff)
        var summaries: [TyphoonSummary] = []
        var listedTyphoonCount = 0
        var loadedTyphoonCount = 0

        for year in stride(from: currentYear, through: cutoffYear, by: -1) {
            let listObject = try await fetchJSONP("\(baseURL)/list_\(year)?callback=typhoon_jsons_list_\(year)")
            guard let dictionary = listObject as? [String: Any],
                  let list = dictionary["typhoonList"] as? [[Any]] else {
                throw NMCServiceError.malformedResponse
            }
            listedTyphoonCount += list.count

            for item in list {
                guard let internalID = number(item, 0).map({ Int($0) }) else { continue }
                do {
                    let snapshot = try await fetchTyphoon(id: internalID)
                    loadedTyphoonCount += 1
                    guard snapshot.issuedAt >= cutoff else { continue }
                    summaries.append(TyphoonSummary(
                        id: internalID,
                        name: snapshot.name,
                        englishName: snapshot.englishName,
                        number: snapshot.number == "0" ? "" : snapshot.number,
                        isActive: string(item, 7).lowercased() == "start",
                        lastUpdated: snapshot.issuedAt,
                        localActivity: nil
                    ))
                } catch {
                    continue
                }
            }
        }

        if listedTyphoonCount > 0, loadedTyphoonCount == 0 {
            throw NMCServiceError.missingTrack
        }

        return summaries.sorted { left, right in
            if left.isActive != right.isActive { return left.isActive }
            return left.lastUpdated > right.lastUpdated
        }
    }

    func fetchTyphoon(id internalID: Int) async throws -> TyphoonSnapshot {
        if let cached = snapshotCache[internalID] { return cached }

        let detailObject = try await fetchJSONP(
            "\(baseURL)/view_\(internalID)?callback=typhoon_jsons_view_\(internalID)"
        )
        guard
            let dictionary = detailObject as? [String: Any],
            let typhoon = dictionary["typhoon"] as? [Any]
        else { throw NMCServiceError.malformedResponse }

        let snapshot = try parseTyphoon(typhoon)
        snapshotCache[internalID] = snapshot
        return snapshot
    }

    private func fetchJSONP(_ address: String) async throws -> Any {
        guard let url = URL(string: address) else { throw NMCServiceError.malformedResponse }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 TyphoonBar/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              var text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "("),
              let end = text.lastIndex(of: ")")
        else { throw NMCServiceError.malformedResponse }
        text = String(text[text.index(after: start)..<end])
        guard let jsonData = text.data(using: .utf8) else { throw NMCServiceError.malformedResponse }
        return try JSONSerialization.jsonObject(with: jsonData)
    }

    private func parseTyphoon(_ data: [Any]) throws -> TyphoonSnapshot {
        guard let rows = data[safe: 8] as? [[Any]], let latest = rows.last else {
            throw NMCServiceError.missingTrack
        }

        let observed = rows.compactMap(parseObserved)
        guard let current = observed.last else { throw NMCServiceError.missingTrack }
        let historyStart = current.date.addingTimeInterval(-72 * 3600)
        let recent = observed.filter { $0.date >= historyStart && $0.date <= current.date }

        var forecast: [TrackPoint] = []
        if let agencies = latest[safe: 11] as? [String: Any],
           let babj = agencies["BABJ"] as? [[Any]] {
            forecast = babj.compactMap { parseForecast($0, issuedAt: current.date) }
        }

        let radii = (latest[safe: 10] as? [[Any]] ?? []).compactMap(parseRadii)
        return TyphoonSnapshot(
            name: string(data, 2),
            englishName: string(data, 1),
            number: String(Int(number(data, 3) ?? 0)),
            current: current,
            observedTrack: observed,
            recentTrack: recent,
            forecast: forecast,
            windRadii: radii,
            direction: Self.directionName(string(latest, 8)),
            movementSpeed: number(latest, 9) ?? 0,
            issuedAt: current.date
        )
    }

    private func parseObserved(_ row: [Any]) -> TrackPoint? {
        guard let dateText = row[safe: 1] as? String,
              let date = Self.date(dateText),
              let longitude = number(row, 4),
              let latitude = number(row, 5),
              let pressure = number(row, 6),
              let wind = number(row, 7)
        else { return nil }
        return TrackPoint(
            date: date,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            pressure: Int(pressure),
            windSpeed: wind,
            grade: string(row, 3),
            forecastHour: nil
        )
    }

    private func parseForecast(_ row: [Any], issuedAt: Date) -> TrackPoint? {
        guard let hour = number(row, 0),
              let longitude = number(row, 2),
              let latitude = number(row, 3),
              let pressure = number(row, 4),
              let wind = number(row, 5)
        else { return nil }
        return TrackPoint(
            date: issuedAt.addingTimeInterval(hour * 3600),
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            pressure: Int(pressure),
            windSpeed: wind,
            grade: string(row, 7),
            forecastHour: Int(hour)
        )
    }

    private func parseRadii(_ row: [Any]) -> WindRadii? {
        guard row.count >= 5 else { return nil }
        return WindRadii(
            level: string(row, 0),
            northeast: number(row, 1) ?? 0,
            southeast: number(row, 2) ?? 0,
            southwest: number(row, 3) ?? 0,
            northwest: number(row, 4) ?? 0
        )
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.date(from: value)
    }

    private static func directionName(_ value: String) -> String {
        ["N":"北", "NNE":"东北偏北", "NE":"东北", "ENE":"东北偏东",
         "E":"东", "ESE":"东南偏东", "SE":"东南", "SSE":"东南偏南",
         "S":"南", "SSW":"西南偏南", "SW":"西南", "WSW":"西南偏西",
         "W":"西", "WNW":"西北偏西", "NW":"西北", "NNW":"西北偏北"][value] ?? value
    }
}

private func string(_ array: [Any], _ index: Int) -> String {
    guard let value = array[safe: index], !(value is NSNull) else { return "" }
    return String(describing: value)
}

private func number(_ array: [Any], _ index: Int) -> Double? {
    guard let value = array[safe: index] else { return nil }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
