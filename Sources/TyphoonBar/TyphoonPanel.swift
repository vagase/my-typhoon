import SwiftUI
import AppKit

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TyphoonPanel: View {
    let store: TyphoonStore
    @State private var mapZoomScale = 1.0
    @State private var measuredContentHeight: CGFloat = 0

    private var panelHeight: CGFloat {
        let targetHeight = measuredContentHeight > 0 ? ceil(measuredContentHeight) : 520
        guard let availableHeight = NSScreen.main?.visibleFrame.height else { return targetHeight }
        return min(max(360, targetHeight), max(360, availableHeight - 4))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch store.state {
            case .idle, .loading:
                loadingView
            case .failed(let message):
                errorView(message)
            case .loaded(let snapshot):
                content(snapshot)
            }
        }
        .frame(width: 420, height: panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            guard height > 0, abs(height - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = height
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("正在连接中央气象台…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text(message).font(.headline)
            Text("请检查网络，或稍后重试。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重新加载") { Task { await store.refresh() } }
            Spacer().frame(height: 12)
            Button("退出 TyphoonBar") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ snapshot: TyphoonSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
            header(snapshot)

            TyphoonMapView(snapshot: snapshot, localImpact: store.localImpact,
                           windField: store.windField, zoomScale: $mapZoomScale)
                .frame(height: 255)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        mapZoomButton("plus") { mapZoomScale = max(0.25, mapZoomScale / 1.6) }
                        Divider().frame(width: 25)
                        mapZoomButton("minus") { mapZoomScale = min(5, mapZoomScale * 1.6) }
                    }
                    .padding(3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.5)))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    windLegend
                        .padding(8)
                }
                .padding(.horizontal, 14)

            currentRow(snapshot)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            localImpactSection
                .padding(.top, 4)

            Spacer(minLength: 2)
            footer(snapshot)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
    }

    private func mapZoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 25, height: 23)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var localImpactSection: some View {
        if let impact = store.localImpact {
            LocalImpactView(summary: impact) {
                Task { await store.refreshLocalImpact() }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: store.isLoadingLocalImpact ? "location.magnifyingglass" : "location.slash")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当地影响").font(.caption.bold())
                    Text(store.localImpactMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoadingLocalImpact {
                    ProgressView().controlSize(.small)
                } else {
                    Button("重试") { Task { await store.refreshLocalImpact() } }
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
        }
    }

    private func header(_ snapshot: TyphoonSnapshot) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.red.gradient)
                Image(nsImage: .typhoonGlyphIcon)
                    .resizable()
                    .frame(width: 25, height: 25)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(snapshot.name) BAVI").font(.headline)
                    Text("实时")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.green.opacity(0.12), in: Capsule())
                }
                Text("第 \(snapshot.number) 号 · 中央气象台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var windLegend: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Label("中心风力圈层", systemImage: "hurricane")
                    .fontWeight(.bold)
                if store.isLoadingWindField {
                    ProgressView().controlSize(.mini)
                }
            }
            HStack(spacing: 4) {
                legendChip("≤5 风影响低", .green)
                legendChip("6", .yellow)
                legendChip("7–9", .orange)
                legendChip("10–11", .red)
                legendChip("≥12", .purple)
            }
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func legendChip(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 1.5) {
            Circle().fill(color).frame(width: 4.5, height: 4.5)
            Text(text)
        }
    }

    private func currentRow(_ snapshot: TyphoonSnapshot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("当前位置").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(String(format: "%.1f°N  %.1f°E", snapshot.current.coordinate.latitude, snapshot.current.coordinate.longitude))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("台风中心坐标").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            metric("风力", "\(snapshot.current.windForce)级", "\(Int(snapshot.current.windSpeed)) m/s")
                .frame(width: 52, alignment: .leading)
            Divider().frame(height: 42).padding(.horizontal, 9)
            metric("气压", "\(snapshot.current.pressure)", "hPa")
                .frame(width: 52, alignment: .leading)
            Divider().frame(height: 42).padding(.horizontal, 9)
            metric("移动", snapshot.direction, "\(Int(snapshot.movementSpeed)) km/h")
                .frame(width: 57, alignment: .leading)
        }
    }

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func footer(_ snapshot: TyphoonSnapshot) -> some View {
        HStack {
            Text("发布 \(snapshot.issuedAt.formatted(date: .omitted, time: .shortened)) · 15分钟刷新 · 模式预报仅供参考，以气象台预警为准")
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

}
