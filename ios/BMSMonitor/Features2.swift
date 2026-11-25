import Foundation
import SwiftUI
import MapKit
import CoreMotion

// MARK: - 驾驶评分
struct DriveScore: Codable {
    var total: Int
    var start: Int        // 起步平稳
    var brake: Int        // 刹车平稳
    var speed: Int        // 车速克制
    var eco: Int          // 省电
    var hardStarts: Int
    var hardBrakes: Int
    var overPct: Double   // 车速超过 35 km/h 的时间占比
    var tips: [String]
}

/// 用这一趟每 2 秒一个的采样点打分
func scoreTrip(samples: [TripSample], km: Double, whPerKm: Double?) -> DriveScore? {
    guard km >= 0.5, samples.count >= 10 else { return nil }
    var hardStarts = 0, hardBrakes = 0, moving = 0, over = 0
    var startCooldown = 0
    for i in 1..<samples.count {
        let a = samples[i - 1], b = samples[i]
        if b.v > 2 { moving += 1; if b.v > 35 { over += 1 } }
        if startCooldown > 0 { startCooldown -= 1 }
        // 猛起步：车速还不到 12 km/h 时功率就超过 1500 W（基本是油门拧到底）
        if b.v < 12 && b.p > 1500 && startCooldown == 0 { hardStarts += 1; startCooldown = 5 }
        // 急刹：2 秒里车速掉了 9 km/h 以上
        if a.v - b.v >= 9 { hardBrakes += 1 }
    }
    let overPct = moving > 0 ? Double(over) / Double(moving) : 0
    let start = max(0, min(100, Int(100 - Double(hardStarts) / km * 18)))
    let brake = max(0, min(100, Int(100 - Double(hardBrakes) / km * 25)))
    let speed = max(0, min(100, Int(100 - overPct * 250)))
    let eco = whPerKm.map { max(0, min(100, Int(100 - max(0, $0 - 22) * 5))) } ?? 80
    let total = Int((Double(start) * 0.3 + Double(brake) * 0.2 + Double(speed) * 0.2 + Double(eco) * 0.3).rounded())
    var tips: [String] = []
    if hardStarts > 0 { tips.append("起步拧到底 \(hardStarts) 次，慢慢加油门更省电，牙包也少受冲击") }
    if hardBrakes > 0 { tips.append("急刹 \(hardBrakes) 次，提前松油门滑行") }
    if overPct > 0.05 { tips.append(String(format: "有 %.0f%%% 的时间超过 35 km/h，三轮车太快不安全，也更费电", overPct * 100)) }
    if let w = whPerKm, w > 30 { tips.append(String(format: "每公里 %.0f Wh，比平时费电", w)) }
    if tips.isEmpty { tips.append("骑得很平稳，继续保持") }
    return DriveScore(total: total, start: start, brake: brake, speed: speed, eco: eco,
                      hardStarts: hardStarts, hardBrakes: hardBrakes, overPct: overPct, tips: tips)
}

// MARK: - 爬坡：手机里的气压计测高度变化（只算相对高度，不需要网络）
final class AltTracker {
    private let alt = CMAltimeter()
    private(set) var gain = 0.0
    private(set) var loss = 0.0
    private(set) var current: Double?
    private var ref: Double?
    var available: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func start() {
        gain = 0; loss = 0; ref = nil; current = nil
        guard available else { return }
        alt.startRelativeAltitudeUpdates(to: .main) { [weak self] d, _ in
            guard let self, let r = d?.relativeAltitude.doubleValue else { return }
            self.current = r
            guard let base = self.ref else { self.ref = r; return }
            // 变化超过 1 米才算，免得把气压计的小抖动算成爬坡
            if r - base >= 1 { self.gain += r - base; self.ref = r }
            else if base - r >= 1 { self.loss += base - r; self.ref = r }
        }
    }

    func stop() { alt.stopRelativeAltitudeUpdates() }
}

// MARK: - 停车位置
struct ParkSpot: Codable {
    var lat: Double
    var lon: Double
    var t: Date
    var soc: Double?
}

final class ParkingStore: ObservableObject {
    @Published private(set) var spot: ParkSpot?
    private let file = JSONFile<ParkSpot>("parking.json")
    init() { spot = file.load() }
    func save(_ loc: CLLocation?, soc: Double?) {
        guard let l = loc else { return }
        let s = ParkSpot(lat: l.coordinate.latitude, lon: l.coordinate.longitude, t: Date(), soc: soc)
        spot = s
        file.save(s)
        LogStore.shared.log("记下了停车位置")      // 不记坐标
    }
}

struct ParkMap: UIViewRepresentable {
    let coord: CLLocationCoordinate2D
    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        m.showsUserLocation = true
        m.isUserInteractionEnabled = false
        return m
    }
    func updateUIView(_ m: MKMapView, context: Context) {
        m.removeAnnotations(m.annotations.filter { !($0 is MKUserLocation) })
        let a = MKPointAnnotation(); a.coordinate = coord; a.title = "车在这"
        m.addAnnotation(a)
        m.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500), animated: false)
    }
}

struct ParkCard: View {
    @EnvironmentObject var parking: ParkingStore
    @EnvironmentObject var ride: RideTracker
    @EnvironmentObject var m: AppModel
    @AppStorage("map.gcj") private var gcj = true

    var body: some View {
        GlassCard(title: "停车位置", icon: "parkingsign.circle.fill") {
            if let s = parking.spot {
                let c = gcj ? ChinaCoord.toGCJ(s.lat, s.lon) : CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)
                ParkMap(coord: c)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t.formatted(.relative(presentation: .named)) + "停的").font(.subheadline.weight(.semibold))
                        if let here = ride.lastLocation {
                            Text("离你 " + distText(here.distance(from: CLLocation(latitude: s.lat, longitude: s.lon))) + (s.soc.map { " · 停车时电量 \(Int($0))%" } ?? ""))
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                    Spacer()
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
                        item.name = "我的三轮车"
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: { Label("带我回去", systemImage: "figure.walk") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else {
                Text("结束骑行时会自动记下停在哪。").font(.caption).foregroundStyle(Theme.sub)
            }
            Button("记下现在的位置") { parking.save(ride.lastLocation, soc: m.lowest?.soc) }
                .font(.caption).buttonStyle(.bordered).tint(.white)
        }
    }

    private func distText(_ d: Double) -> String { d >= 1000 ? String(format: "%.1f 公里", d / 1000) : "\(Int(d)) 米" }
}

// MARK: - 加速测试
struct AccelRun: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var t10: Double?
    var t20: Double?
    var t30: Double?
    var peakW: Double
    var peakA: Double
    var socAtStart: Double?
}

final class PerfTester: ObservableObject {
    enum Phase { case idle, waitStop, ready, running, done }
    @Published var phase: Phase = .idle
    @Published var live: AccelRun?
    @Published var elapsed: Double = 0
    @Published private(set) var runs: [AccelRun] = []
    @Published var message = "点\"开始\"，停稳后按提示全力起步"
    private let file = JSONFile<[AccelRun]>("accel.json")
    private var still = 0
    private var t0: Date?
    private var prev: (t: Date, v: Double)?

    init() { runs = file.load() ?? [] }

    var best30: Double? { runs.compactMap(\.t30).min() }
    var best20: Double? { runs.compactMap(\.t20).min() }

    func begin() {
        phase = .waitStop; still = 0; live = nil; elapsed = 0; prev = nil; t0 = nil
        message = "先把车停稳…"
    }
    func cancel() { phase = .idle; message = "已取消" }

    /// 每个定位点调用（km/h），power/current 是电池那边当时的读数
    func feed(_ loc: CLLocation, power: Double?, current: Double?, soc: Double?) -> String? {
        let v = max(loc.speed, 0) * 3.6, t = loc.timestamp
        defer { prev = (t, v) }
        switch phase {
        case .idle, .done: return nil
        case .waitStop:
            still = v < 1 ? still + 1 : 0
            if still >= 2 { phase = .ready; message = "准备好了，全力起步！"; return "准备好了，起步" }
        case .ready:
            if v >= 1.5, let p = prev {
                // 起步时刻：上一个点到这个点之间，车速越过 1 km/h 的那一刻
                let f = p.v < v ? (1 - p.v) / (v - p.v) : 0
                t0 = p.t.addingTimeInterval(t.timeIntervalSince(p.t) * min(max(f, 0), 1))
                phase = .running
                live = AccelRun(date: Date(), peakW: 0, peakA: 0, socAtStart: soc)
                message = "计时中…"
            }
        case .running:
            guard let s = t0, var r = live, let p = prev else { return nil }
            r.peakW = max(r.peakW, power ?? 0)
            r.peakA = max(r.peakA, -(current ?? 0))
            func cross(_ target: Double) -> Double? {
                guard p.v < target, v >= target else { return nil }
                let f = (target - p.v) / (v - p.v)
                return p.t.addingTimeInterval(t.timeIntervalSince(p.t) * f).timeIntervalSince(s)
            }
            if r.t10 == nil { r.t10 = cross(10) }
            if r.t20 == nil { r.t20 = cross(20) }
            if r.t30 == nil { r.t30 = cross(30) }
            elapsed = t.timeIntervalSince(s)
            live = r
            if r.t30 != nil || elapsed > 25 || (v < p.v - 3 && elapsed > 3) {
                phase = .done
                runs.insert(r, at: 0)
                file.save(runs)
                message = r.t30.map { String(format: "0～30 用了 %.1f 秒", $0) } ?? (r.t20.map { String(format: "没到 30，0～20 用了 %.1f 秒", $0) } ?? "没测完，再试一次")
                LogStore.shared.log("加速测试：" + message)
                return message
            }
        }
        return nil
    }

    func delete(at o: IndexSet) { runs.remove(atOffsets: o); file.save(runs) }
}

struct PerfTestView: View {
    @EnvironmentObject var perf: PerfTester
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ride: RideTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    Section {
                        VStack(spacing: 10) {
                            Text(perf.message).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                            Text(String(format: "%.1f 秒", perf.elapsed)).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(perf.phase == .running ? Theme.warn : .white)
                            HStack {
                                StatTile(label: "0～10", value: perf.live?.t10.map { String(format: "%.1f", $0) } ?? "--", unit: "秒")
                                StatTile(label: "0～20", value: perf.live?.t20.map { String(format: "%.1f", $0) } ?? "--", unit: "秒")
                                StatTile(label: "0～30", value: perf.live?.t30.map { String(format: "%.1f", $0) } ?? "--", unit: "秒")
                            }
                            HStack {
                                StatTile(label: "车速", value: ride.freshSpeed.map { String(format: "%.0f", $0) } ?? "--", unit: "km/h")
                                StatTile(label: "峰值功率", value: perf.live.map { String(format: "%.0f", $0.peakW) } ?? "--", unit: "W")
                                StatTile(label: "峰值电流", value: perf.live.map { String(format: "%.0f", $0.peakA) } ?? "--", unit: "A")
                            }
                            if perf.phase == .idle || perf.phase == .done {
                                Button {
                                    if !ride.on { m.toggleRide() }
                                    perf.begin()
                                    m.say("先把车停稳")
                                } label: { Text(perf.phase == .done ? "再测一次" : "开始").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10) }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                            } else {
                                Button("取消") { perf.cancel() }.buttonStyle(.bordered).tint(.white)
                            }
                            Text("用手机定位测车速，每秒一个点，计时误差大约正负 0.3 秒。请在空旷、平直、没车没人的路上测，注意安全。")
                                .font(.caption2).foregroundStyle(Theme.faint).multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.card)
                    Section(header: Text("历史成绩").foregroundStyle(Theme.sub)) {
                        if let b = perf.best30 {
                            Label(String(format: "最好成绩：0～30 用 %.1f 秒", b), systemImage: "trophy.fill").foregroundStyle(Theme.warn)
                        }
                        ForEach(perf.runs) { r in
                            HStack {
                                Text(r.date.formatted(.dateTime.month().day().hour().minute())).font(.caption)
                                Spacer()
                                Text([r.t10.map { String(format: "10: %.1f", $0) }, r.t20.map { String(format: "20: %.1f", $0) }, r.t30.map { String(format: "30: %.1f", $0) }]
                                    .compactMap { $0 }.joined(separator: "  ") + String(format: "  · %.0f W", r.peakW))
                                    .font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
                            }
                        }
                        .onDelete { perf.delete(at: $0) }
                    }
                    .listRowBackground(Theme.card)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("加速测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { perf.cancel(); dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
