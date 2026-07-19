import SwiftUI
import MapKit
import CoreLocation

struct TyphoonMapView: NSViewRepresentable {
    let snapshot: TyphoonSnapshot
    let localImpact: LocalImpactSummary?
    let windField: [WindFieldSample]
    @Binding var zoomScale: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.showsCompass = false
        map.showsZoomControls = false
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)

        let contours = Self.windContours(snapshot: snapshot, samples: windField)
        for contour in contours.reversed() {
            var coordinates = contour.coordinates
            let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
            polygon.title = "WINDCONTOUR:\(contour.force)"
            map.addOverlay(polygon)
        }

        for radii in snapshot.windRadii.sorted(by: { $0.maximum > $1.maximum }) where radii.maximum > 0 {
            let zone = Self.windZone(center: snapshot.current.coordinate, radii: radii)
            zone.title = "WINDZONE:\(radii.level)"
            map.addOverlay(zone)
        }

        if snapshot.recentTrack.count > 1 {
            Self.addTrackSegments(snapshot.recentTrack.map(\.coordinate), to: map,
                                  localCoordinate: localImpact?.coordinate, isForecast: false)
        }
        if !snapshot.forecast.isEmpty {
            Self.addTrackSegments([snapshot.current.coordinate] + snapshot.forecast.map(\.coordinate), to: map,
                                  localCoordinate: localImpact?.coordinate, isForecast: true)
            snapshot.forecast.prefix(3).forEach { map.addAnnotation(ForecastAnnotation(point: $0)) }
        }

        for contour in contours {
            let coordinate = Self.destination(from: snapshot.current.coordinate, bearing: 42,
                                              distance: contour.labelRadius)
            map.addAnnotation(WindContourAnnotation(coordinate: coordinate, contour: contour))
        }
        for radii in snapshot.windRadii where radii.maximum > 0 {
            let coordinate = Self.destination(from: snapshot.current.coordinate, bearing: 235, distance: radii.maximum)
            map.addAnnotation(WindBoundaryAnnotation(coordinate: coordinate, level: Self.boundaryLevel(radii.level)))
        }

        map.addAnnotation(CurrentAnnotation(snapshot: snapshot))
        if let localImpact { map.addAnnotation(LocalAnnotation(summary: localImpact)) }

        let outer = contours.last?.maximumRadius ?? 350
        let defaultRadius = max(350, outer)
        let visible = [0.0, 90, 180, 270].map {
            Self.destination(from: snapshot.current.coordinate, bearing: $0, distance: defaultRadius)
        }
        let fitKey = "\(snapshot.current.date.timeIntervalSince1970)-\(snapshot.recentTrack.count)-\(snapshot.forecast.count)-\(windField.count)-\(zoomScale)"
        if context.coordinator.lastFitKey != fitKey {
            context.coordinator.lastFitKey = fitKey
            let fittedRect = Self.mapRect(for: visible)
            let scaledSize = MKMapSize(width: fittedRect.size.width * zoomScale,
                                       height: fittedRect.size.height * zoomScale)
            let scaledOrigin = MKMapPoint(x: fittedRect.midX - scaledSize.width / 2,
                                          y: fittedRect.midY - scaledSize.height / 2)
            map.setVisibleMapRect(MKMapRect(origin: scaledOrigin, size: scaledSize),
                                  edgePadding: NSEdgeInsets(top: 24, left: 22, bottom: 24, right: 22),
                                  animated: false)
            map.setCenter(snapshot.current.coordinate, animated: false)
        }
    }

    private static func addTrackSegments(_ coordinates: [CLLocationCoordinate2D], to map: MKMapView,
                                         localCoordinate: CLLocationCoordinate2D?, isForecast: Bool) {
        guard coordinates.count > 1 else { return }
        for index in 0..<(coordinates.count - 1) {
            var segment = [coordinates[index], coordinates[index + 1]]
            let midpoint = CLLocationCoordinate2D(
                latitude: (segment[0].latitude + segment[1].latitude) / 2,
                longitude: (segment[0].longitude + segment[1].longitude) / 2
            )
            let riskScore = localCoordinate.map {
                proximityScore(points: [segment[0], midpoint, segment[1]], localCoordinate: $0)
            } ?? -1
            let overlay = RiskTrackPolyline(coordinates: &segment, count: segment.count)
            overlay.proximityScore = riskScore
            overlay.isForecast = isForecast
            map.addOverlay(overlay)
        }
    }

    private static func proximityScore(points: [CLLocationCoordinate2D],
                                       localCoordinate: CLLocationCoordinate2D) -> Double {
        let local = CLLocation(latitude: localCoordinate.latitude, longitude: localCoordinate.longitude)
        let minimumDistance = points.map {
            local.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) / 1_000
        }.min() ?? .infinity
        return RiskPalette.proximityScore(distance: minimumDistance)
    }

    fileprivate struct WindContour {
        let force: Int
        let coordinates: [CLLocationCoordinate2D]
        let labelRadius: Double
        let maximumRadius: Double
    }

    private static func windContours(snapshot: TyphoonSnapshot, samples: [WindFieldSample]) -> [WindContour] {
        let centerForce = snapshot.current.windForce
        let lowestForce = max(5, centerForce - 3)
        let levels = centerForce >= lowestForce ? Array(stride(from: centerForce, through: lowestForce, by: -1)) : [centerForce]
        let officialSeven = snapshot.windRadii.first(where: { $0.level == "30KTS" })

        return levels.map { force in
            var radii: [Double] = []
            let coordinates = stride(from: 0.0, to: 360.0, by: 10.0).map { bearing -> CLLocationCoordinate2D in
                let sevenRadius = quadrantRadius(officialSeven, bearing: bearing)
                let baseSevenRadius = sevenRadius > 0 ? sevenRadius : 110
                let levelOffset = Double(7 - force)
                var radius = baseSevenRadius * max(0.38, 1 + levelOffset * 0.38)
                radius *= directionalModelAdjustment(samples: samples, center: snapshot.current.coordinate,
                                                     bearing: bearing, targetForce: force)
                radius = max(25, radius)
                radii.append(radius)
                return destination(from: snapshot.current.coordinate, bearing: bearing, distance: radius)
            }
            let northeastIndex = 4
            return WindContour(force: force, coordinates: coordinates,
                               labelRadius: radii[northeastIndex], maximumRadius: radii.max() ?? 350)
        }
    }

    private static func quadrantRadius(_ radii: WindRadii?, bearing: Double) -> Double {
        guard let radii else { return 0 }
        switch bearing {
        case 0..<90: return radii.northeast
        case 90..<180: return radii.southeast
        case 180..<270: return radii.southwest
        default: return radii.northwest
        }
    }

    private static func directionalModelAdjustment(samples: [WindFieldSample], center: CLLocationCoordinate2D,
                                                   bearing: Double, targetForce: Int) -> Double {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearby = samples.compactMap { sample -> (Double, Int)? in
            let location = CLLocation(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude)
            let distance = centerLocation.distance(from: location) / 1_000
            guard distance > 30 else { return nil }
            let sampleBearing = bearingBetween(center, sample.coordinate)
            let difference = min(abs(sampleBearing - bearing), 360 - abs(sampleBearing - bearing))
            return difference <= 32 ? (distance, sample.windForce) : nil
        }.sorted { $0.0 < $1.0 }.prefix(3)
        guard !nearby.isEmpty else { return 1 }
        let meanForce = Double(nearby.reduce(0) { $0 + $1.1 }) / Double(nearby.count)
        return min(1.18, max(0.82, 1 + (meanForce - Double(targetForce)) * 0.035))
    }

    private static func bearingBetween(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func boundaryLevel(_ level: String) -> String {
        switch level { case "64KTS": return "12级风圈"; case "50KTS": return "10级风圈"; default: return "7级风圈" }
    }

    private static func windZone(center: CLLocationCoordinate2D, radii: WindRadii) -> MKPolygon {
        var coordinates = stride(from: 0.0, through: 360.0, by: 5.0).map { bearing -> CLLocationCoordinate2D in
            let radius: Double
            switch bearing {
            case 0..<90: radius = radii.northeast
            case 90..<180: radius = radii.southeast
            case 180..<270: radius = radii.southwest
            default: radius = radii.northwest
            }
            return destination(from: center, bearing: bearing, distance: radius)
        }
        return MKPolygon(coordinates: &coordinates, count: coordinates.count)
    }

    fileprivate static func destination(from center: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let angularDistance = distance / 6_371
        let bearingRadians = bearing * .pi / 180
        let latitude = center.latitude * .pi / 180
        let longitude = center.longitude * .pi / 180
        let targetLatitude = asin(sin(latitude) * cos(angularDistance) + cos(latitude) * sin(angularDistance) * cos(bearingRadians))
        let targetLongitude = longitude + atan2(sin(bearingRadians) * sin(angularDistance) * cos(latitude), cos(angularDistance) - sin(latitude) * sin(targetLatitude))
        return CLLocationCoordinate2D(latitude: targetLatitude * 180 / .pi, longitude: targetLongitude * 180 / .pi)
    }

    private static func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 0, height: 0))) }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastFitKey: String?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon, let title = polygon.title, title.hasPrefix("WINDCONTOUR:") {
                let force = Int(title.split(separator: ":").last ?? "0") ?? 0
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = bandColor(force).withAlphaComponent(force <= 5 ? 0.11 : 0.17)
                renderer.strokeColor = bandColor(force).withAlphaComponent(0.72)
                renderer.lineWidth = 1.2
                return renderer
            }
            if let polygon = overlay as? MKPolygon, let title = polygon.title, title.hasPrefix("WINDZONE:") {
                let level = String(title.split(separator: ":").last ?? "")
                let color: NSColor = switch level { case "64KTS": .systemRed; case "50KTS": .systemOrange; default: .systemYellow }
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = .clear
                renderer.strokeColor = color.withAlphaComponent(0.9)
                renderer.lineWidth = level == "64KTS" ? 2.2 : 1.5
                renderer.lineDashPattern = [5, 3]
                return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            if let track = overlay as? RiskTrackPolyline {
                renderer.strokeColor = track.proximityScore >= 0 ? RiskPalette.nsColor(score: track.proximityScore) : .systemGray
                renderer.lineWidth = track.isForecast ? 5 : 4
                if track.isForecast { renderer.lineDashPattern = [8, 6] }
            } else {
                renderer.strokeColor = NSColor.systemGray.withAlphaComponent(0.7); renderer.lineWidth = 4
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is CurrentAnnotation {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "current")
                view.markerTintColor = .systemRed
                view.glyphImage = NSImage(systemSymbolName: "hurricane", accessibilityDescription: "台风")
                view.titleVisibility = .visible; view.subtitleVisibility = .visible; view.displayPriority = .required
                return view
            }
            if annotation is ForecastAnnotation {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "forecast")
                view.markerTintColor = .systemOrange; view.glyphText = "·"; view.titleVisibility = .adaptive
                return view
            }
            if annotation is LocalAnnotation {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "local")
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "当前位置")
                view.titleVisibility = .visible; view.subtitleVisibility = .visible; view.displayPriority = .required
                return view
            }
            if let contour = annotation as? WindContourAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "contour") as? WindContourLabelView)
                    ?? WindContourLabelView(annotation: contour, reuseIdentifier: "contour")
                view.annotation = contour; view.configure(contour); return view
            }
            if let boundary = annotation as? WindBoundaryAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "boundary") as? BoundaryLabelView)
                    ?? BoundaryLabelView(annotation: boundary, reuseIdentifier: "boundary")
                view.annotation = boundary; view.configure(boundary); return view
            }
            return nil
        }
    }
}

private final class CurrentAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let title: String?; let subtitle: String?
    init(snapshot: TyphoonSnapshot) {
        coordinate = snapshot.current.coordinate; title = "\(snapshot.name) · \(snapshot.current.windForce)级"; subtitle = "\(snapshot.current.pressure) hPa"
    }
}
private final class ForecastAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let title: String?
    init(point: TrackPoint) { coordinate = point.coordinate; title = "+\(point.forecastHour ?? 0)h · \(point.windForce)级" }
}
private final class LocalAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let title: String?; let subtitle: String?
    init(summary: LocalImpactSummary) {
        coordinate = summary.coordinate
        title = summary.placeName
        let now = Date()
        let current = summary.periods.min {
            abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now))
        }
        if let current {
            subtitle = "距台风约 \(Int(summary.closestDistance)) km · 当前 \(Self.windForce(current.wind))级风 · \(current.level.rawValue)风险"
        } else {
            subtitle = "距台风约 \(Int(summary.closestDistance)) km"
        }
    }

    private static func windForce(_ speedInKilometersPerHour: Double) -> Int {
        let speed = speedInKilometersPerHour / 3.6
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
        case 8.0..<10.8: return 4
        case 5.5..<8.0: return 3
        case 3.4..<5.5: return 2
        case 1.6..<3.4: return 1
        default: return 0
        }
    }
}
private final class WindContourAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let force: Int; let radius: Double
    init(coordinate: CLLocationCoordinate2D, contour: TyphoonMapView.WindContour) {
        self.coordinate = coordinate; force = contour.force; radius = contour.labelRadius
    }
}
private final class WindBoundaryAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D; let level: String
    init(coordinate: CLLocationCoordinate2D, level: String) { self.coordinate = coordinate; self.level = level }
}

private final class WindContourLabelView: MKAnnotationView {
    private let label = NSTextField(labelWithString: "")
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = NSRect(x: 0, y: 0, width: 88, height: 24); displayPriority = .required
        label.frame = bounds; label.alignment = .center; label.font = .systemFont(ofSize: 9, weight: .bold)
        label.isBordered = false; label.drawsBackground = true; label.wantsLayer = true; label.layer?.cornerRadius = 7
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ annotation: WindContourAnnotation) {
        label.stringValue = "\(annotation.force)级风区 · 约\(Int(annotation.radius))km"
        label.backgroundColor = bandColor(annotation.force).withAlphaComponent(0.88)
        label.textColor = annotation.force == 7 || annotation.force == 6 ? .black : .white
    }
}
private final class BoundaryLabelView: MKAnnotationView {
    private let label = NSTextField(labelWithString: "")
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = NSRect(x: 0, y: 0, width: 60, height: 17); displayPriority = .defaultHigh
        label.frame = bounds; label.alignment = .center; label.font = .systemFont(ofSize: 8, weight: .bold)
        label.isBordered = false; label.drawsBackground = true; label.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82)
        label.wantsLayer = true; label.layer?.cornerRadius = 5; addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ annotation: WindBoundaryAnnotation) { label.stringValue = annotation.level }
}

private func bandColor(_ force: Int) -> NSColor {
    RiskPalette.nsColor(score: RiskPalette.forceScore(force))
}

private final class RiskTrackPolyline: MKPolyline, @unchecked Sendable {
    var proximityScore: Double = -1
    var isForecast = false
}
