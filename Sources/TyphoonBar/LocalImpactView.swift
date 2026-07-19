import SwiftUI
import Charts

struct LocalImpactView: View {
    let summary: LocalImpactSummary
    let refresh: () -> Void
    @State private var selectedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            impactOverview
            riskTimeline
            selectedDetail
            rainCard
            gustCard
        }
    }

    private var impactOverview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(summary.placeName, systemImage: "location.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)
                Text("未来24小时")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.09), in: Capsule())
                Spacer()
                Button(action: refresh) { Image(systemName: "location.circle.fill") }
                    .buttonStyle(.borderless).help("重新定位并刷新当地预报")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.blue.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
            riskHero
            overviewMetrics
        }
        .padding(8)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.055), Color.primary.opacity(0.018)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.18)))
        .shadow(color: Color.black.opacity(0.055), radius: 6, y: 2)
        .padding(.horizontal, 14)
    }

    private var riskHero: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(riskColor.opacity(0.16))
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3).foregroundStyle(riskColor)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("最高风险时段").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(riskWindow).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("\(peakPeriod?.level.rawValue ?? "较低")风险")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(riskColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(riskColor.opacity(0.13), in: Capsule())
                }
                Text(peakFactors)
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            Spacer()
            Text(trendText).font(.system(size: 9, weight: .bold)).foregroundStyle(riskColor)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(riskColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(riskColor.opacity(0.32)))
    }

    private var overviewMetrics: some View {
        HStack(spacing: 5) {
            summaryMetric("location.circle.fill", .blue, "最近距离", "\(Int(summary.closestDistance)) km", "预计 \(hour(summary.closestTime))")
            summaryMetric("drop.fill", .cyan, "24h累计降雨", String(format: "%.0f mm", summary.rain24h), rainDescription(summary.rain24h))
            summaryMetric("wind", .orange, "24h最大阵风", String(format: "%.0f km/h", summary.maxGust24h), gustDescription(summary.maxGust24h))
        }
    }

    private var riskTimeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("综合风险走势").font(.system(size: 10, weight: .bold))
                Text("点击色块或拖动图表查看").font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                legend("低", .green); legend("中", .yellow); legend("高", .orange); legend("极高", .red)
            }
            HStack(spacing: 2) {
                ForEach(hours) { period in
                    Button { selectedTime = period.start } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(RiskPalette.color(score: period.riskIndex / 100))
                            .frame(height: selectedPeriod?.id == period.id ? 12 : 8)
                            .overlay {
                                if selectedPeriod?.id == period.id {
                                    RoundedRectangle(cornerRadius: 3).stroke(.primary, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("\(hour(period.start)) · \(period.level.rawValue)风险 · \(period.advice)")
                    .onHover { hovering in
                        if hovering { selectedTime = period.start }
                    }
                }
            }
            HStack {
                Text("现在"); Spacer(); Text("+6h"); Spacer(); Text("+12h"); Spacer(); Text("+18h"); Spacer(); Text("+24h")
            }
            .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var rainCard: some View {
        VStack(spacing: 3) {
            chartHeader(icon: "cloud.heavyrain.fill", color: .blue, title: "逐小时降雨",
                        explanation: "柱形颜色 = 降雨风险等级",
                        value: selectedPeriod.map { String(format: "%.1f mm/h", $0.rain) } ?? "—",
                        detail: selectedPeriod.map { "降水概率 \($0.probability)%" } ?? "")
            Chart(hours) { period in
                BarMark(x: .value("时间", period.start), y: .value("雨量", period.rain))
                    .foregroundStyle(RiskPalette.color(score: RiskPalette.rainScore(period.rain)))
                if let selectedPeriod, selectedPeriod.id == period.id {
                    RuleMark(x: .value("选中", period.start)).foregroundStyle(.blue.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.16)); AxisValueLabel().font(.system(size: 7))
                }
            }
            .chartXSelection(value: $selectedTime)
            .frame(height: 48)
            HStack(spacing: 9) {
                threshold("<10 低", .green); threshold("10–20 关注", .yellow)
                threshold("20–50 较高", .orange); threshold("≥50 很高", .red); Spacer()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.16)))
        .padding(.horizontal, 14)
    }

    private var gustCard: some View {
        VStack(spacing: 3) {
            gustChartHeader
            Chart {
                ForEach(hours) { period in
                    AreaMark(x: .value("时间", period.start), y: .value("阵风", period.gust))
                        .foregroundStyle(.linearGradient(colors: [.secondary.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", period.start), y: .value("持续风", period.wind),
                             series: .value("类型", "持续风"))
                        .foregroundStyle(Color.blue.opacity(0.78))
                        .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    LineMark(x: .value("时间", period.start), y: .value("阵风", period.gust),
                             series: .value("类型", "瞬时阵风"))
                        .foregroundStyle(gustRiskGradient).lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    if let selectedPeriod, selectedPeriod.id == period.id {
                        RuleMark(x: .value("选中", period.start)).foregroundStyle(.orange.opacity(0.58))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                if gustChartMaximum >= 62 {
                    RuleMark(y: .value("关注", 62)).foregroundStyle(.yellow.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                if gustChartMaximum >= 89 {
                    RuleMark(y: .value("较高", 89)).foregroundStyle(.orange.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                if gustChartMaximum >= 118 {
                    RuleMark(y: .value("很高", 118)).foregroundStyle(.red.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .chartYScale(domain: 0...gustChartMaximum)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour()).font(.system(size: 7))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: gustAxisValues) {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15)); AxisValueLabel().font(.system(size: 7))
                }
            }
            .chartXSelection(value: $selectedTime)
            .frame(height: 64)
            HStack(spacing: 9) {
                threshold("<62 低", .green); threshold("62–89 关注", .yellow)
                threshold("89–118 较高", .orange); threshold("≥118 很高", .red); Spacer()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.orange.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.16)))
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var selectedDetail: some View {
        if let period = selectedPeriod {
            VStack(spacing: 5) {
                HStack {
                    Text("\(hour(period.start))–\(hour(period.end)) 当地影响详情").font(.system(size: 10, weight: .bold))
                    Spacer()
                    Text("\(period.level.rawValue)风险").font(.system(size: 10, weight: .bold)).foregroundStyle(color(period.level))
                }
                HStack(spacing: 0) {
                    detailMetric("降雨", String(format: "%.1f mm", period.rain), "概率 \(period.probability)%")
                    divider; detailMetric("持续风", String(format: "%.0f km/h", period.wind), "时段平均")
                    divider; detailMetric("瞬时阵风", String(format: "%.0f km/h", period.gust), "短时最大")
                    divider; detailMetric("中心距离", "\(Int(period.typhoonDistance)) km", "预测位置")
                }
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color(period.level))
                    Text(period.advice).fontWeight(.semibold); Spacer()
                }
                .font(.system(size: 9))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color(period.level).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
        }
    }

    private var divider: some View { Divider().frame(height: 28).padding(.horizontal, 8) }
    private var hours: [LocalImpactPeriod] { Array(summary.periods.prefix(24)) }
    private var maxGust: Double { hours.map(\.gust).max() ?? 0 }
    private var gustChartMaximum: Double {
        ceil(max(20, maxGust * 1.20) / 10) * 10
    }
    private var gustAxisValues: [Double] {
        let visibleThresholds = [62.0, 89.0, 118.0].filter { $0 <= gustChartMaximum }
        if visibleThresholds.isEmpty { return [0, gustChartMaximum / 2, gustChartMaximum] }
        return [0] + visibleThresholds
    }
    private var gustRiskGradient: LinearGradient {
        let stops = (0...16).map { index -> Gradient.Stop in
            let location = Double(index) / 16
            return .init(color: RiskPalette.color(score: RiskPalette.gustScore(gustChartMaximum * location)), location: location)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .bottom, endPoint: .top)
    }
    private var selectedPeriod: LocalImpactPeriod? {
        guard let selectedTime else { return peakPeriod }
        return hours.min { abs($0.start.timeIntervalSince(selectedTime)) < abs($1.start.timeIntervalSince(selectedTime)) }
    }
    private var peakPeriod: LocalImpactPeriod? {
        hours.max { $0.severity == $1.severity ? $0.riskIndex < $1.riskIndex : $0.severity < $1.severity }
    }
    private var riskColor: Color { color(peakPeriod?.level ?? .low) }
    private var peakFactors: String {
        guard let peak = peakPeriod else { return "暂无当地风雨数据" }
        return String(format: "持续风 %.0f km/h · 阵风 %.0f km/h · 雨 %.1f mm/h", peak.wind, peak.gust, peak.rain)
    }
    private var riskWindow: String {
        guard let peak = peakPeriod, peak.severity >= 2,
              let index = hours.firstIndex(where: { $0.id == peak.id }) else { return "无高风险窗口" }
        let threshold = peak.severity == 3 ? 2 : peak.severity
        var start = index, end = index
        while start > 0, hours[start - 1].severity >= threshold { start -= 1 }
        while end + 1 < hours.count, hours[end + 1].severity >= threshold { end += 1 }
        return "\(hour(hours[start].start))–\(hour(hours[end].end))"
    }
    private var trendText: String {
        guard let peak = peakPeriod, let first = hours.first else { return "趋势未知" }
        let offset = Int(peak.start.timeIntervalSince(first.start) / 3600)
        if offset <= 1 { return "当前接近峰值" }
        if offset <= 6 { return "未来\(offset)小时增强 ↑" }
        return peak.severity >= 2 ? "稍后明显增强 ↑" : "整体较平稳 →"
    }

    private func chartHeader(icon: String, color: Color, title: String, explanation: String, value: String, detail: String) -> some View {
        HStack(spacing: 7) {
            ZStack { RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)); Image(systemName: icon).foregroundStyle(color) }
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .bold)); Text(explanation).font(.system(size: 8)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(.system(size: 12, weight: .bold, design: .rounded)); Text(detail).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
    private var gustChartHeader: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.12))
                Image(systemName: "wind").foregroundStyle(.orange)
            }
            .frame(width: 24, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("逐小时风力").font(.system(size: 11, weight: .bold))
                Text("蓝线持续风 · 彩线瞬时阵风").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            windHeaderMetric("持续风", selectedPeriod?.wind, "时段平均", .blue)
            Divider().frame(height: 27)
            windHeaderMetric("瞬时阵风", selectedPeriod?.gust, "短时最大", .orange)
        }
    }
    private func windHeaderMetric(_ title: String, _ value: Double?, _ detail: String, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("km/h").font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(detail).font(.system(size: 7)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 58, alignment: .trailing)
    }
    private func summaryMetric(_ icon: String, _ tint: Color, _ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 8, weight: .medium))
            Text(value).font(.system(size: 12, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(tint.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.13)))
    }
    private func detailMetric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 7)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 2) { Circle().fill(color).frame(width: 5, height: 5); Text(text) }
            .font(.system(size: 7)).foregroundStyle(.secondary)
    }
    private func threshold(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) { Rectangle().fill(color).frame(width: 10, height: 1); Text(text) }
            .font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
    }
    private func hour(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
    private func color(_ level: ImpactLevel) -> Color {
        RiskPalette.color(score: RiskPalette.levelScore(level))
    }
    private func rainDescription(_ value: Double) -> String {
        if value >= 100 { return "大暴雨量级" }; if value >= 50 { return "暴雨量级" }
        if value >= 25 { return "大雨量级" }; if value >= 10 { return "中雨量级" }; return "小雨或更低"
    }
    private func gustDescription(_ value: Double) -> String {
        if value >= 103 { return "11级以上" }; if value >= 88 { return "10级左右" }
        if value >= 75 { return "9级左右" }; if value >= 62 { return "8级左右" }
        if value >= 50 { return "7级左右" }; return "6级以下"
    }
}
