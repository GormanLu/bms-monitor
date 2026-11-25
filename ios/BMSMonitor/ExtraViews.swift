import SwiftUI
import Charts
import MapKit

// MARK: - 记录页：骑行 / 充电 / 电池健康
struct TripsView: View {
    @EnvironmentObject var trips: TripStore
    @EnvironmentObject var badges: BadgeStore
    @State private var seg = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    Picker("", selection: $seg) {
                        Text("骑行").tag(0)
                        Text("充电").tag(1)
                        Text("电池健康").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    switch seg {
                    case 1: ChargeListView()
                    case 2: HealthView()
                    default: rides
                    }
                }
            }
            .navigationTitle("记录")
        }
    }

    private var rides: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    NavigationLink { ReportView() } label: { shortcut("月度报告", "chart.bar.doc.horizontal.fill", Theme.accent) }
                    NavigationLink { BadgesView() } label: { shortcut("徽章 \(badges.unlocked.count)/\(BadgeStore.all.count)", "medal.fill", Theme.warn) }
                    NavigationLink { HeatmapView() } label: { shortcut("路线热力图", "flame.fill", Theme.bad) }
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            Section { totals }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            Section { records }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            Section(header: Text("每一趟").foregroundStyle(Theme.sub)) {
                if trips.trips.isEmpty {
                    Text("还没有骑行记录。在仪表盘点\"开始骑行\"，骑完点\"结束骑行\"，这里就会多一条。")
                        .font(.caption).foregroundStyle(Theme.sub).listRowBackground(Theme.card)
                }
                ForEach(trips.trips) { t in
                    NavigationLink { TripDetailView(trip: t) } label: { TripRow(trip: t) }
                        .listRowBackground(Theme.card)
                }
                .onDelete { trips.delete(at: $0) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func shortcut(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
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

// MARK: - 充电记录
struct ChargeListView: View {
    @EnvironmentObject var charges: ChargeStore
    @EnvironmentObject var trips: TripStore
    var body: some View {
        List {
            Section(footer: Text("充电时 app 连着电池才会记（手机放在电池附近、app 在后台也行）。\"先停的块\"是哪一块最先不再进电。")) {
                if charges.sessions.isEmpty {
                    Text("还没有充电记录。下次充电时让 app 连着电池。").font(.caption).foregroundStyle(Theme.sub)
                }
                ForEach(charges.sessions) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: c.complete ? "battery.100.bolt" : "battery.50").foregroundStyle(c.complete ? Theme.good : Theme.warn)
                            Text(c.start.formatted(.dateTime.month().day().hour().minute())).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(c.complete ? "充满" : "中途停").font(.caption).foregroundStyle(c.complete ? Theme.good : Theme.warn)
                        }
                        HStack {
                            StatTile(label: "用时", value: c.duration.hms)
                            StatTile(label: "充进", value: String(format: "%.1f", c.ahIn), unit: "Ah")
                            StatTile(label: "电量", value: String(format: "%.0f→%.0f", c.socStart, c.socEnd), unit: "%")
                            StatTile(label: "电费", value: String(format: "%.2f", c.wh / 1000 / 0.85 * trips.price), unit: "元")
                        }
                        if !c.stops.isEmpty {
                            Text("各块停的先后：" + c.stops.joined(separator: " → ")).font(.caption).foregroundStyle(Theme.sub)
                        }
                        if !c.note.isEmpty { Text(c.note).font(.caption2).foregroundStyle(Theme.faint) }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.card)
                }
                .onDelete { charges.delete(at: $0) }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - 电池健康曲线
struct HealthView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var m: AppModel
    @State private var msg = ""
    var body: some View {
        List {
            Section {
                GlassCard(title: "P 平均每节比其他块低多少（mV）", icon: "waveform.path.ecg") {
                    if health.records.count >= 2 {
                        Chart(health.records) { r in
                            LineMark(x: .value("日期", r.date), y: .value("P 低", r.pLowMv))
                                .foregroundStyle(Theme.warn).interpolationMethod(.monotone)
                            PointMark(x: .value("日期", r.date), y: .value("P 低", r.pLowMv))
                                .foregroundStyle(by: .value("电量段", band(r.soc)))
                        }
                        .chartForegroundStyleScale(["70% 以上": Theme.good, "55～70%": Theme.warn, "35～55%": Theme.accent, "35% 以下": Theme.bad])
                        .frame(height: 200)
                    } else {
                        Text("每天第一次连上电池、电池静置着的时候，会自动记一条。记满两条就能画出曲线。")
                            .font(.caption).foregroundStyle(Theme.sub)
                    }
                    Text("磷酸铁锂的电压和电量关系不是直线：P 在 55%～70% 和 30% 以下时显得低，35%～55% 时和别的块差不多。所以要看同一个电量段的点有没有越来越高，不同颜色之间不能直接比。")
                        .font(.caption2).foregroundStyle(Theme.faint)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            Section {
                Button {
                    let ok = health.add(blocks: m.liveBlocks, summarySoc: m.summary?.soc, manual: true)
                    msg = ok ? "记下了。最好是停车静置半小时以上再记。" : "要先连上主模块、收到五块的数据才能记。"
                } label: { Label("现在记一条", systemImage: "plus.circle.fill") }
                if !msg.isEmpty { Text(msg).font(.caption).foregroundStyle(Theme.sub) }
            }
            .listRowBackground(Theme.card)
            Section(header: Text("每一天").foregroundStyle(Theme.sub)) {
                ForEach(health.records) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.date.formatted(.dateTime.month().day().hour().minute()) + (r.manual ? " · 手动" : ""))
                                .font(.subheadline.weight(.semibold))
                            Text("电量 \(Int(r.soc))% · 整组压差 \(r.packGapMv) mV · 最低的是 \(r.lowName)（低 \(r.lowMv) mV） · \(r.temp)°")
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(r.pLowMv)").font(.system(.headline, design: .rounded)).foregroundStyle(r.pLowMv >= 30 ? Theme.bad : r.pLowMv >= 15 ? Theme.warn : Theme.good)
                            Text("P 低 mV").font(.system(size: 9)).foregroundStyle(Theme.sub)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete { health.delete(at: $0) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func band(_ s: Double) -> String { s >= 70 ? "70% 以上" : s >= 55 ? "55～70%" : s >= 35 ? "35～55%" : "35% 以下" }
}

// MARK: - 徽章
struct BadgesView: View {
    @EnvironmentObject var badges: BadgeStore
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(BadgeStore.all) { b in
                        let got = badges.unlocked[b.id]
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(got != nil ? LinearGradient(colors: [Theme.warn, Theme.bad], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                         : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                                Image(systemName: b.icon).font(.title2).foregroundStyle(got != nil ? .white : Theme.faint)
                            }
                            .frame(width: 60, height: 60)
                            Text(b.title).font(.subheadline.weight(.bold)).foregroundStyle(got != nil ? .white : Theme.sub)
                            Text(b.detail).font(.system(size: 10)).foregroundStyle(Theme.sub).multilineTextAlignment(.center).lineLimit(2)
                            Text(got.map { $0.formatted(.dateTime.month().day()) } ?? "未解锁").font(.system(size: 9)).foregroundStyle(Theme.faint)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("徽章")
    }
}

// MARK: - 月度报告（可以生成图片分享）
struct ReportView: View {
    @EnvironmentObject var trips: TripStore
    @EnvironmentObject var charges: ChargeStore
    @State private var offset = 0          // 0 = 本月，-1 = 上个月
    @State private var image: Image?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(monthTitle(offset)).font(.headline)
                        Spacer()
                        Button { offset = min(0, offset + 1) } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
                    }
                    .padding(.horizontal, 6)
                    ReportCard(s: stats(offset), prev: stats(offset - 1), title: monthTitle(offset))
                    if let image {
                        ShareLink(item: image, preview: SharePreview(monthTitle(offset) + "骑行报告", image: image)) {
                            Label("分享这张卡片", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("月度报告")
        .onAppear(perform: render)
        .onChange(of: offset) { _ in render() }
    }

    @MainActor private func render() {
        let r = ImageRenderer(content: ReportCard(s: stats(offset), prev: stats(offset - 1), title: monthTitle(offset))
            .frame(width: 360).padding(16).background(Color(red: 0.05, green: 0.06, blue: 0.1)).environment(\.colorScheme, .dark))
        r.scale = 3
        image = r.uiImage.map { Image(uiImage: $0) }
    }

    private func monthStart(_ off: Int) -> Date {
        let c = Calendar.current
        let start = c.date(from: c.dateComponents([.year, .month], from: Date()))!
        return c.date(byAdding: .month, value: off, to: start)!
    }
    private func monthTitle(_ off: Int) -> String { monthStart(off).formatted(.dateTime.year().month(.wide)) }

    struct Stats { var n = 0, km = 0.0, hours = 0.0, wh = 0.0, cost = 0.0, maxKmh = 0.0, longest = 0.0, charges = 0, chargeWh = 0.0
        var whPerKm: Double? { km >= 1 ? wh / km : nil } }

    private func stats(_ off: Int) -> Stats {
        let a = monthStart(off), b = monthStart(off + 1)
        let ts = trips.trips.filter { $0.start >= a && $0.start < b }
        let cs = charges.sessions.filter { $0.start >= a && $0.start < b }
        var s = Stats()
        s.n = ts.count
        s.km = ts.reduce(0) { $0 + $1.km }
        s.hours = ts.reduce(0) { $0 + $1.duration } / 3600
        s.wh = ts.reduce(0) { $0 + $1.energyWh }
        s.cost = s.wh / 1000 / 0.85 * trips.price
        s.maxKmh = ts.map(\.maxKmh).max() ?? 0
        s.longest = ts.map(\.km).max() ?? 0
        s.charges = cs.count
        s.chargeWh = cs.reduce(0) { $0 + $1.wh }
        return s
    }
}

struct ReportCard: View {
    let s: ReportView.Stats
    let prev: ReportView.Stats
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.car.fill").foregroundStyle(Theme.accent)
                Text(title + " · 骑行报告").font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", s.km)).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                Text("公里").foregroundStyle(Theme.sub)
                Spacer()
                if prev.km > 0 {
                    let d = (s.km - prev.km) / prev.km * 100
                    Text(String(format: "%@%.0f%%", d >= 0 ? "比上月多 " : "比上月少 ", abs(d)))
                        .font(.caption.weight(.semibold)).foregroundStyle(d >= 0 ? Theme.good : Theme.warn)
                }
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    StatTile(label: "骑了", value: "\(s.n)", unit: "趟")
                    StatTile(label: "用时", value: String(format: "%.1f", s.hours), unit: "小时")
                    StatTile(label: "最高", value: String(format: "%.0f", s.maxKmh), unit: "km/h")
                }
                GridRow {
                    StatTile(label: "用电", value: String(format: "%.2f", s.wh / 1000), unit: "度")
                    StatTile(label: "电费", value: String(format: "%.2f", s.cost), unit: "元")
                    StatTile(label: "每公里", value: s.whPerKm.map { String(format: "%.0f", $0) } ?? "--", unit: "Wh")
                }
                GridRow {
                    StatTile(label: "最远一趟", value: String(format: "%.1f", s.longest), unit: "km")
                    StatTile(label: "充电", value: "\(s.charges)", unit: "次")
                    StatTile(label: "百公里电费", value: s.km >= 1 ? String(format: "%.1f", s.cost / s.km * 100) : "--", unit: "元")
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.38), Color(red: 0.06, green: 0.08, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke))
        .foregroundStyle(.white)
    }
}

// MARK: - 所有路线叠在一起的热力图
struct HeatmapView: View {
    @EnvironmentObject var trips: TripStore
    @AppStorage("map.gcj") private var gcj = true
    var body: some View {
        let tracks = trips.trips.compactMap(\.track).filter { $0.count >= 2 }
        return ZStack(alignment: .bottom) {
            HeatMap(tracks: tracks, gcj: gcj).ignoresSafeArea(edges: .bottom)
            Text(tracks.isEmpty ? "还没有带轨迹的骑行记录" : "共 \(tracks.count) 趟 · 走得越多，线越亮越粗")
                .font(.caption).padding(10)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(.bottom, 24)
        }
        .navigationTitle("路线热力图")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeatMap: UIViewRepresentable {
    let tracks: [[TrackPoint]]
    let gcj: Bool
    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        var rect = MKMapRect.null
        for t in tracks {
            let c = t.map { gcj ? ChinaCoord.toGCJ($0.lat, $0.lon) : CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let line = MKPolyline(coordinates: c, count: c.count)
            m.addOverlay(line)
            rect = rect.union(line.boundingMapRect)
        }
        if !rect.isNull { m.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 80, right: 40), animated: false) }
        return m
    }
    func updateUIView(_ m: MKMapView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = UIColor(red: 1.0, green: 0.45, blue: 0.25, alpha: 0.35)   // 半透明：叠得越多越亮
            r.lineWidth = 6
            r.lineCap = .round
            r.lineJoin = .round
            r.blendMode = .screen
            return r
        }
    }
}

// MARK: - 骑行回放
struct ReplayView: View {
    let trip: Trip
    @AppStorage("map.gcj") private var gcj = true
    @State private var t: Double = 0
    @State private var playing = false
    @State private var rate: Double = 30
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        let track = trip.track ?? []
        let total = max(track.last?.t ?? 0, trip.samples.last?.t ?? 0, 1)
        let pt = point(at: t, in: track)
        let smp = sample(at: t)
        return VStack(spacing: 0) {
            ReplayMap(track: track, current: pt, gcj: gcj)
            VStack(spacing: 12) {
                HStack {
                    StatTile(label: "车速", value: String(format: "%.0f", smp?.v ?? pt?.v ?? 0), unit: "km/h", color: Theme.accent)
                    StatTile(label: "功率", value: String(format: "%.0f", smp?.p ?? 0), unit: "W", color: Theme.warn)
                    StatTile(label: "电量", value: String(format: "%.0f", smp?.soc ?? 0), unit: "%", color: Theme.good)
                    StatTile(label: "时间", value: t.hms)
                }
                Slider(value: $t, in: 0...total)
                HStack {
                    Button { if t >= total { t = 0 }; playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 54, height: 44)
                            .background(Capsule().fill(Theme.accent)).foregroundStyle(.white)
                    }
                    Spacer()
                    Picker("速度", selection: $rate) {
                        Text("10 倍").tag(10.0)
                        Text("30 倍").tag(30.0)
                        Text("60 倍").tag(60.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .padding(16)
            .background(Color.black)
        }
        .navigationTitle("回放")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            guard playing else { return }
            t = min(total, t + 0.05 * rate)
            if t >= total { playing = false }
        }
        .preferredColorScheme(.dark)
    }

    private func point(at t: Double, in track: [TrackPoint]) -> TrackPoint? {
        guard !track.isEmpty else { return nil }
        var lo = 0, hi = track.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if track[mid].t <= t { lo = mid } else { hi = mid - 1 } }
        return track[lo]
    }

    private func sample(at t: Double) -> TripSample? {
        let s = trip.samples
        guard !s.isEmpty else { return nil }
        var lo = 0, hi = s.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if s[mid].t <= t { lo = mid } else { hi = mid - 1 } }
        return s[lo]
    }
}

struct ReplayMap: UIViewRepresentable {
    let track: [TrackPoint]
    let current: TrackPoint?
    let gcj: Bool

    private func coord(_ p: TrackPoint) -> CLLocationCoordinate2D {
        gcj ? ChinaCoord.toGCJ(p.lat, p.lon) : CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
    }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        let c = track.map(coord)
        if c.count >= 2 {
            let line = MKPolyline(coordinates: c, count: c.count)
            m.addOverlay(line)
            m.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30), animated: false)
        }
        m.addAnnotation(context.coordinator.dot)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        if let p = current { context.coordinator.dot.coordinate = coord(p) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let dot = MKPointAnnotation()
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = UIColor(white: 1, alpha: 0.35)
            r.lineWidth = 4
            return r
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let v = MKAnnotationView(annotation: annotation, reuseIdentifier: "dot")
            let size: CGFloat = 22
            v.frame = CGRect(x: 0, y: 0, width: size, height: size)
            v.layer.cornerRadius = size / 2
            v.backgroundColor = UIColor(red: 0.33, green: 0.57, blue: 1.0, alpha: 1)
            v.layer.borderColor = UIColor.white.cgColor
            v.layer.borderWidth = 3
            return v
        }
    }
}
