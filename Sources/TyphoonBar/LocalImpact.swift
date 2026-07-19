import Foundation
import CoreLocation

struct LocalImpactPeriod: Identifiable, Sendable {
    let id = UUID()
    let start: Date
    let end: Date
    let rain: Double
    let maxHourlyRain: Double
    let probability: Int
    let wind: Double
    let gust: Double
    let typhoonDistance: Double
    let level: ImpactLevel
    let advice: String

    var riskIndex: Double {
        max(RiskPalette.rainScore(rain), RiskPalette.windScore(wind), RiskPalette.gustScore(gust)) * 100
    }

    var severity: Int {
        switch level {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .extreme: return 3
        }
    }
}

struct LocalImpactSummary: Sendable {
    let coordinate: CLLocationCoordinate2D
    let placeName: String
    let periods: [LocalImpactPeriod]
    let closestDistance: Double
    let closestTime: Date
    let rain24h: Double
    let maxGust24h: Double
    let headline: String
    let advice: [String]
}

enum LocalImpactAnalyzer {
    static func analyze(
        weather: LocalWeatherForecast,
        typhoon: TyphoonSnapshot,
        placeName: String
    ) -> LocalImpactSummary {
        let futureTrack = [typhoon.current] + typhoon.forecast
        let closest = futureTrack.min { distance($0.coordinate, weather.coordinate) < distance($1.coordinate, weather.coordinate) } ?? typhoon.current
        let closestDistance = distance(closest.coordinate, weather.coordinate)
        let next24 = weather.hourly.filter { $0.date < Date().addingTimeInterval(24 * 3600) }
        let rain24 = next24.reduce(0) { $0 + $1.precipitation }
        let maxGust = next24.map(\.windGust).max() ?? 0

        let periods = weather.hourly.prefix(48).map { hour -> LocalImpactPeriod in
            let rain = hour.precipitation
            let gust = hour.windGust
            let stormCoordinate = interpolatedTrack(at: hour.date, points: futureTrack)
            let stormDistance = distance(stormCoordinate, weather.coordinate)
            let level = riskLevel(rain: rain, wind: hour.windSpeed, gust: gust)
            return LocalImpactPeriod(
                start: hour.date,
                end: hour.date.addingTimeInterval(3600),
                rain: rain,
                maxHourlyRain: rain,
                probability: hour.precipitationProbability,
                wind: hour.windSpeed,
                gust: gust,
                typhoonDistance: stormDistance,
                level: level,
                advice: periodAdvice(rain: rain, gust: gust, distance: stormDistance)
            )
        }

        var advice: [String] = []
        if rain24 >= 100 { advice.append("24小时累计雨量可能达大暴雨量级，低洼地、地下空间和山洪地质灾害风险很高。") }
        else if rain24 >= 50 { advice.append("24小时累计雨量可能达到暴雨量级，注意城市积水、山洪及滑坡。") }
        else if rain24 >= 25 { advice.append("存在明显强降雨过程，出行请避开积水路段。") }
        if maxGust >= 75 { advice.append("阵风可能达到9级以上，停止高空和临水作业，远离窗户及临时构筑物。") }
        else if maxGust >= 50 { advice.append("阵风较强，请固定阳台物品，避免骑行和在树木、广告牌附近停留。") }
        if closestDistance <= 100 { advice.append("预测路径非常接近当地；台风路径仍可能摆动，应按更高一级风险准备。") }
        else if closestDistance <= 300 { advice.append("当地处于台风显著影响范围，持续关注气象台预警升级。") }
        if advice.isEmpty { advice.append("目前当地直接影响有限，但路径和降雨预报仍会变化，请保持更新。") }

        let headline: String
        if closestDistance <= 100 { headline = "台风核心可能经过附近" }
        else if rain24 >= 50 || maxGust >= 75 { headline = "将有显著风雨影响" }
        else if closestDistance <= 300 { headline = "位于台风外围影响区" }
        else { headline = "当前直接影响相对有限" }

        return LocalImpactSummary(
            coordinate: weather.coordinate,
            placeName: placeName,
            periods: periods,
            closestDistance: closestDistance,
            closestTime: closest.date,
            rain24h: rain24,
            maxGust24h: maxGust,
            headline: headline,
            advice: advice
        )
    }

    private static func riskLevel(rain: Double, wind: Double, gust: Double) -> ImpactLevel {
        if rain >= 50 || wind >= 89 || gust >= 118 { return .extreme }
        if rain >= 20 || wind >= 62 || gust >= 89 { return .high }
        if rain >= 10 || wind >= 39 || gust >= 62 { return .medium }
        return .low
    }

    private static func periodAdvice(rain: Double, gust: Double, distance: Double) -> String {
        if rain >= 50 { return "小时雨强极端，警惕内涝和山洪" }
        if gust >= 90 { return "破坏性阵风，避免一切非必要外出" }
        if rain >= 20 { return "短时强降雨，避免低洼和山区道路" }
        if gust >= 75 { return "强阵风，停止非必要户外活动" }
        if gust >= 50 { return "加固易坠物，谨慎出行" }
        if rain >= 5 { return "雨势明显增强，注意道路积水" }
        if distance <= 150 { return "预测路径接近，持续关注最新预报" }
        return "影响相对有限"
    }

    private static func interpolatedTrack(at date: Date, points: [TrackPoint]) -> CLLocationCoordinate2D {
        guard let first = points.first, let last = points.last else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        if date <= first.date { return first.coordinate }
        if date >= last.date { return last.coordinate }
        for index in 0..<(points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            guard date >= left.date && date <= right.date else { continue }
            let duration = right.date.timeIntervalSince(left.date)
            let ratio = duration > 0 ? date.timeIntervalSince(left.date) / duration : 0
            return CLLocationCoordinate2D(
                latitude: left.coordinate.latitude + (right.coordinate.latitude - left.coordinate.latitude) * ratio,
                longitude: left.coordinate.longitude + (right.coordinate.longitude - left.coordinate.longitude) * ratio
            )
        }
        return last.coordinate
    }

    private static func distance(_ left: CLLocationCoordinate2D, _ right: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude)) / 1_000
    }
}
