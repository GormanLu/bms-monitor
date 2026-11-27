import SwiftUI
import Charts

struct TripRow: View {
    let trip: Trip
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.15))
                if let tr = trip.track, tr.count >= 2 {
                    TrackShape(track: tr).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).padding(7)
                } else {
                    Image(systemName: "figure.outdoor.cycle").foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.start.formatted(.dateTime.month().day().hour().minute())).font(.subheadline.weight(.semibold))
                Text(String(format: "%.2f km · %@ · 最高 %.0f km/h", trip.km, trip.duration.hms, trip.maxKmh))
                    .font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer()
            if let w = trip.whPerKm {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f", w)).font(.system(.headline, design: Theme.font)).monospacedDigit()
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
    @AppStorage("map.gcj") private var gcj = true
    @State private var gpx: URL?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    if let tr = trip.track, tr.count >= 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            TrackMap(track: tr, gcj: gcj)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                            HStack(spacing: 10) {
                                ForEach([("慢", 5.0), ("15", 15.0), ("28", 28.0), ("40+", 40.0)], id: \.0) { item in
                                    HStack(spacing: 4) {
                                        Circle().fill(Color(speedColor(item.1))).frame(width: 8, height: 8)
                                        Text(item.0).font(.caption2).foregroundStyle(Theme.sub)
                                    }
                                }
                                Spacer()
                                Text("颜色是车速（km/h）").font(.caption2).foregroundStyle(Theme.faint)
                            }
                        }
                    }
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
                    RideAnalysisCard(trip: trip)
                    if let s = trip.score ?? scoreTrip(samples: trip.samples, km: trip.km, whPerKm: trip.whPerKm) { ScoreCard(s: s) }
                    let same = sameRoute(trip, in: trips.trips)
                    if !same.isEmpty { SameRouteCard(trip: trip, others: same) }
                    NavigationLink { PosterView(trip: trip) } label: {
                        Label("生成骑行海报", systemImage: "photo.artframe")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().stroke(Color.white.opacity(0.4))).foregroundStyle(.white)
                    }
                    if let tr = trip.track, tr.count >= 2 {
                        NavigationLink { ReplayView(trip: trip) } label: {
                            Label("回放这一趟", systemImage: "play.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(Theme.accent)).foregroundStyle(.white)
                        }
                    }
                    if trip.samples.count > 3 {
                        chart(title: "车速", unit: "km/h", color: Theme.accent) { $0.v }
                        chart(title: "功率", unit: "W", color: Theme.warn) { $0.p }
                        chart(title: "电量（最低的一块）", unit: "%", color: Theme.good) { $0.soc }
                    }
                    TripExtraCharts(trip: trip)
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
        .toolbar {
            if let gpx {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: gpx) { Label("导出轨迹", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task { gpx = trip.gpxFile() }
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
