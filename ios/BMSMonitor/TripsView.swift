import SwiftUI
import Charts

struct TripsView: View {
    @EnvironmentObject var trips: TripStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if trips.trips.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "map").font(.system(size: 44)).foregroundStyle(Theme.faint)
                        Text("还没有骑行记录").font(.headline)
                        Text("在仪表盘点\"开始骑行\"，骑完点\"结束骑行\"，这里就会多一条。").font(.caption).foregroundStyle(Theme.sub)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                } else {
                    List {
                        Section { totals }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        Section { records }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        Section(header: Text("每一趟").foregroundStyle(Theme.sub)) {
                            ForEach(trips.trips) { t in
                                NavigationLink { TripDetailView(trip: t) } label: { TripRow(trip: t) }
                                    .listRowBackground(Theme.card)
                            }
                            .onDelete { trips.delete(at: $0) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("骑行记录")
        }
    }

    private var totals: some View {
        GlassCard(title: "累计", icon: "sum") {
            HStack {
                StatTile(label: "里程", value: String(format: "%.1f", trips.totalKm), unit: "km")
                StatTile(label: "用电", value: String(format: "%.2f", trips.totalWh / 1000), unit: "度")
                StatTile(label: "电费", value: String(format: "%.2f", trips.totalCost), unit: "元")
            }
            Text(String(format: "共 %d 趟 · 电价按 %.2f 元/度、充电效率 85%% 算，可以在设置里改", trips.trips.count, trips.price))
                .font(.caption2).foregroundStyle(Theme.faint)
        }
    }

    private var records: some View {
        GlassCard(title: "最佳纪录", icon: "trophy.fill") {
            HStack {
                StatTile(label: "最高车速", value: trips.maxSpeed.map { String(format: "%.0f", $0.maxKmh) } ?? "--", unit: "km/h", color: Theme.warn)
                StatTile(label: "最远一趟", value: trips.longest.map { String(format: "%.1f", $0.km) } ?? "--", unit: "km", color: Theme.accent)
                StatTile(label: "最省电", value: trips.mostEfficient.flatMap(\.whPerKm).map { String(format: "%.0f", $0) } ?? "--", unit: "Wh/km", color: Theme.good)
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18))
                Image(systemName: "figure.outdoor.cycle").foregroundStyle(Theme.accent)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.start.formatted(.dateTime.month().day().hour().minute())).font(.subheadline.weight(.semibold))
                Text(String(format: "%.2f km · %@ · 最高 %.0f km/h", trip.km, trip.duration.hms, trip.maxKmh))
                    .font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer()
            if let w = trip.whPerKm {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f", w)).font(.system(.headline, design: .rounded)).monospacedDigit()
                    Text("Wh/km").font(.system(size: 9)).foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TripDetailView: View {
    let trip: Trip
    @EnvironmentObject var trips: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard(title: trip.start.formatted(date: .complete, time: .shortened), icon: "calendar") {
                        Grid(horizontalSpacing: 10, verticalSpacing: 14) {
                            GridRow {
                                StatTile(label: "里程", value: String(format: "%.2f", trip.km), unit: "km")
                                StatTile(label: "用时", value: trip.duration.hms)
                                StatTile(label: "最高", value: String(format: "%.0f", trip.maxKmh), unit: "km/h")
                            }
                            GridRow {
                                StatTile(label: "平均（不算停车）", value: trip.avgMovingKmh.map { String(format: "%.0f", $0) } ?? "--", unit: "km/h")
                                StatTile(label: "用电", value: String(format: "%.0f", trip.energyWh), unit: "Wh")
                                StatTile(label: "每公里", value: trip.whPerKm.map { String(format: "%.0f", $0) } ?? "--", unit: "Wh")
                            }
                            GridRow {
                                StatTile(label: "最大功率", value: String(format: "%.0f", trip.maxPowerW), unit: "W")
                                StatTile(label: "电量", value: String(format: "%.0f→%.0f", trip.socStart, trip.socEnd), unit: "%")
                                StatTile(label: "电费", value: String(format: "%.2f", trip.energyWh / 1000 / 0.85 * trips.price), unit: "元")
                            }
                        }
                    }
                    if trip.samples.count > 3 {
                        chart(title: "车速", unit: "km/h", color: Theme.accent) { $0.v }
                        chart(title: "功率", unit: "W", color: Theme.warn) { $0.p }
                        chart(title: "电量（最低的一块）", unit: "%", color: Theme.good) { $0.soc }
                    }
                    Button(role: .destructive) { trips.delete(trip); dismiss() } label: {
                        Label("删除这一趟", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
        }
        .navigationTitle("这一趟")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(title: String, unit: String, color: Color, _ value: @escaping (TripSample) -> Double) -> some View {
        let pts = Array(trip.samples.enumerated())
        return GlassCard(title: title + "（" + unit + "）") {
            Chart(pts, id: \.offset) { item in
                AreaMark(x: .value("分钟", item.element.t / 60), y: .value(title, value(item.element)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("分钟", item.element.t / 60), y: .value(title, value(item.element)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
            .frame(height: 150)
            Text("横轴是出发后的分钟数").font(.caption2).foregroundStyle(Theme.faint)
        }
    }
}
