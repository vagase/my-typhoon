import Foundation
import Observation
import CoreLocation

@MainActor
@Observable
final class TyphoonStore {
    enum State {
        case idle
        case loading
        case loaded(TyphoonSnapshot)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastUpdated: Date?
    private(set) var localImpact: LocalImpactSummary?
    private(set) var localImpactMessage = "正在获取你的位置…"
    private(set) var isLoadingLocalImpact = false
    private(set) var windField: [WindFieldSample] = []
    private(set) var isLoadingWindField = false
    private let service = NMCService()
    private let weatherService = LocalWeatherService()
    private let windFieldService = WindFieldService()
    private let locationProvider = LocationProvider()
    private var refreshTask: Task<Void, Never>?

    func start() async {
        guard refreshTask == nil else { return }
        await refresh()
        await refreshLocalImpact()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await self?.refresh(silently: true)
            }
        }
    }

    func refresh(silently: Bool = false) async {
        if !silently { state = .loading }
        do {
            let snapshot = try await service.fetchBavi()
            state = .loaded(snapshot)
            lastUpdated = Date()
            await updateWindField(snapshot: snapshot)
            if let localImpact {
                await updateLocalImpact(at: localImpact.coordinate, placeName: localImpact.placeName, snapshot: snapshot)
            }
        } catch {
            if case .loaded = state, silently { return }
            state = .failed(error.localizedDescription)
        }
    }

    func refreshLocalImpact() async {
        isLoadingLocalImpact = true
        localImpactMessage = "正在获取你的位置…"
        defer { isLoadingLocalImpact = false }
        do {
            let location = try await locationProvider.currentLocation()
            localImpactMessage = "正在计算当地逐时影响…"
            let placeName = await resolveName(location)
            guard case .loaded(let snapshot) = state else { return }
            await updateLocalImpact(at: location.coordinate, placeName: placeName, snapshot: snapshot)
        } catch {
            localImpactMessage = error.localizedDescription
        }
    }

    private func updateWindField(snapshot: TyphoonSnapshot) async {
        isLoadingWindField = true
        defer { isLoadingWindField = false }
        do {
            windField = try await windFieldService.fetch(around: snapshot.current.coordinate)
        } catch {
            if windField.isEmpty { windField = [] }
        }
    }

    private func updateLocalImpact(at coordinate: CLLocationCoordinate2D, placeName: String, snapshot: TyphoonSnapshot) async {
        do {
            let weather = try await weatherService.fetch(at: coordinate)
            localImpact = LocalImpactAnalyzer.analyze(weather: weather, typhoon: snapshot, placeName: placeName)
            localImpactMessage = ""
        } catch {
            localImpactMessage = "当地逐时预报暂时不可用"
        }
    }

    private func resolveName(_ location: CLLocation) async -> String {
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            guard let mark = marks.first else { return "当前位置" }
            return mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? "当前位置"
        } catch {
            return "当前位置"
        }
    }
}
