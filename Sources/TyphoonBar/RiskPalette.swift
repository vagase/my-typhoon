import SwiftUI
import AppKit

enum RiskPalette {
    private struct Stop {
        let position: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let stops: [Stop] = [
        Stop(position: 0.00, red: 0.13, green: 0.77, blue: 0.37),
        Stop(position: 0.32, red: 0.52, green: 0.80, blue: 0.09),
        Stop(position: 0.50, red: 0.92, green: 0.70, blue: 0.03),
        Stop(position: 0.70, red: 0.98, green: 0.45, blue: 0.09),
        Stop(position: 0.86, red: 0.94, green: 0.27, blue: 0.24),
        Stop(position: 1.00, red: 0.73, green: 0.07, blue: 0.07)
    ]

    static func color(score: Double) -> Color { Color(nsColor: nsColor(score: score)) }

    static func nsColor(score: Double) -> NSColor {
        let score = min(1, max(0, score))
        guard let upperIndex = stops.firstIndex(where: { $0.position >= score }) else {
            return makeColor(stops.last!)
        }
        guard upperIndex > 0 else { return makeColor(stops[upperIndex]) }
        let lower = stops[upperIndex - 1], upper = stops[upperIndex]
        let span = upper.position - lower.position
        let ratio = span > 0 ? (score - lower.position) / span : 0
        return NSColor(srgbRed: lower.red + (upper.red - lower.red) * ratio,
                       green: lower.green + (upper.green - lower.green) * ratio,
                       blue: lower.blue + (upper.blue - lower.blue) * ratio, alpha: 1)
    }

    static func rainScore(_ value: Double) -> Double { piecewise(value, [(0, 0.05), (10, 0.42), (20, 0.68), (50, 1)]) }
    static func windScore(_ value: Double) -> Double { piecewise(value, [(0, 0.05), (39, 0.42), (62, 0.68), (89, 1)]) }
    static func gustScore(_ value: Double) -> Double { piecewise(value, [(0, 0.05), (62, 0.42), (89, 0.68), (118, 1)]) }
    static func forceScore(_ force: Int) -> Double { piecewise(Double(force), [(0, 0.02), (5, 0.22), (6, 0.42), (9, 0.68), (12, 0.9), (17, 1)]) }
    static func proximityScore(distance: Double) -> Double { piecewise(distance, [(0, 1), (50, 0.9), (150, 0.72), (350, 0.48), (500, 0.18), (800, 0.05)]) }
    static func levelScore(_ level: ImpactLevel) -> Double {
        switch level { case .low: 0.16; case .medium: 0.50; case .high: 0.74; case .extreme: 0.96 }
    }

    private static func piecewise(_ value: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value >= last.0 { return last.1 }
        for index in 1..<points.count where value <= points[index].0 {
            let lower = points[index - 1], upper = points[index]
            let ratio = (value - lower.0) / (upper.0 - lower.0)
            return lower.1 + (upper.1 - lower.1) * ratio
        }
        return last.1
    }

    private static func makeColor(_ stop: Stop) -> NSColor {
        NSColor(srgbRed: stop.red, green: stop.green, blue: stop.blue, alpha: 1)
    }
}
