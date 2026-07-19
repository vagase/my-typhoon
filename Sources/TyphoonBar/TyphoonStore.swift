import Foundation
import Observation
import CoreLocation

@MainActor
@Observable
final class TyphoonStore {
    enum State {
        case idle
        case loading
        case noSelection
        case loaded(TyphoonSnapshot)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var availableTyphoons: [TyphoonSummary] = []
    private(set) var selectedTyphoonID: Int?
    private(set) var catalogPlaceName = "当前位置"
    private(set) var catalogActivityMessage = "正在获取当前位置…"
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
    private var catalogLocation: CLLocation?

    var selectedTyphoon: TyphoonSummary? {
        availableTyphoons.first { $0.id == selectedTyphoonID }
    }

    var isSelectedTyphoonActive: Bool { selectedTyphoon?.isActive == true }

    func start() async {
        guard refreshTask == nil else { return }
        await refresh()
        await refreshCatalogLocalActivity()
        if isSelectedTyphoonActive { await refreshLocalImpact() }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await self?.refresh(silently: true)
                await self?.refreshCatalogLocalActivity()
                if self?.isSelectedTyphoonActive == true, self?.localImpact == nil {
                    await self?.refreshLocalImpact()
                }
            }
        }
    }

    func refresh(silently: Bool = false) async {
        if !silently { state = .loading }
        do {
            let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date().addingTimeInterval(-90 * 86_400)
            let typhoons = try await service.fetchRecentTyphoons(since: cutoff)
            let knownActivities = Dictionary(uniqueKeysWithValues: availableTyphoons.compactMap { typhoon in
                typhoon.localActivity.map { (typhoon.id, $0) }
            })
            availableTyphoons = typhoons.map { typhoon in
                var updated = typhoon
                updated.localActivity = knownActivities[typhoon.id]
                return updated
            }

            let preservedSelection = selectedTyphoonID.flatMap { selected in
                typhoons.contains(where: { $0.id == selected }) ? selected : nil
            }
            selectedTyphoonID = preservedSelection ?? typhoons.first(where: \.isActive)?.id

            guard let selectedTyphoonID else {
                clearTyphoonDetails(message: "近三个月暂无正在活动的台风")
                state = .noSelection
                lastUpdated = Date()
                return
            }
            try await loadTyphoon(id: selectedTyphoonID)
        } catch {
            if case .loaded = state, silently { return }
            state = .failed(error.localizedDescription)
        }
    }

    func selectTyphoon(id: Int) async {
        guard id != selectedTyphoonID else { return }
        selectedTyphoonID = id
        state = .loading
        clearTyphoonDetails(message: "正在准备台风数据…")
        do {
            try await loadTyphoon(id: id)
            if isSelectedTyphoonActive { await refreshLocalImpact() }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshLocalImpact() async {
        guard isSelectedTyphoonActive else {
            localImpact = nil
            localImpactMessage = "历史台风已停止，不提供当前当地影响"
            return
        }
        isLoadingLocalImpact = true
        localImpactMessage = "正在获取你的位置…"
        defer { isLoadingLocalImpact = false }
        do {
            let location = try await currentCatalogLocation()
            localImpactMessage = "正在计算当地逐时影响…"
            let placeName = await resolveName(location)
            guard case .loaded(let snapshot) = state else { return }
            await updateLocalImpact(at: location.coordinate, placeName: placeName, snapshot: snapshot)
        } catch {
            localImpactMessage = error.localizedDescription
        }
    }

    func refreshCatalogLocalActivity() async {
        guard !availableTyphoons.isEmpty else { return }
        catalogActivityMessage = "正在计算台风对当前地区的主要影响日期…"
        do {
            let location = try await currentCatalogLocation()
            catalogPlaceName = await resolveName(location)

            for index in availableTyphoons.indices {
                let snapshot = try await service.fetchTyphoon(id: availableTyphoons[index].id)
                let track = snapshot.observedTrack + snapshot.forecast
                guard let closest = track.min(by: {
                    distance(from: $0.coordinate, to: location.coordinate) < distance(from: $1.coordinate, to: location.coordinate)
                }) else { continue }
                availableTyphoons[index].localActivity = TyphoonLocalActivity(
                    date: closest.date,
                    distance: distance(from: closest.coordinate, to: location.coordinate)
                )
            }
            catalogActivityMessage = "主要影响日按路径最接近当前地区的日期估算"
        } catch {
            catalogActivityMessage = error.localizedDescription
        }
    }

    private func loadTyphoon(id: Int) async throws {
        let snapshot = try await service.fetchTyphoon(id: id)
        state = .loaded(snapshot)
        lastUpdated = Date()

        guard isSelectedTyphoonActive else {
            clearTyphoonDetails(message: "历史台风已停止，不提供当前当地影响")
            return
        }
        await updateWindField(snapshot: snapshot)
        if let localImpact {
            await updateLocalImpact(at: localImpact.coordinate, placeName: localImpact.placeName, snapshot: snapshot)
        }
    }

    private func clearTyphoonDetails(message: String) {
        localImpact = nil
        localImpactMessage = message
        windField = []
        isLoadingWindField = false
    }

    private func currentCatalogLocation() async throws -> CLLocation {
        if let catalogLocation { return catalogLocation }
        let location = try await locationProvider.currentLocation()
        catalogLocation = location
        return location
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to localCoordinate: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: localCoordinate.latitude, longitude: localCoordinate.longitude)) / 1_000
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
