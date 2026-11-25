import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct BMSWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup { WatchRoot().environmentObject(model) }
    }
}

// MARK: - 收手机发来的数据
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var s = WatchState()
    @Published var got: Date?
    private var lastNavDist = -1
    private var lastNavText = ""
    private var lastOverBuzz = Date.distantPast
    private var lowBuzzed = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var reachable: Bool { WCSession.default.isReachable }

    func toggleRide() {
        WCSession.default.sendMessage(["cmd": "toggleRide"], replyHandler: { _ in }, errorHandler: nil)
        WKInterfaceDevice.current().play(.click)
    }

    private func apply(_ d: [String: Any]) {
        guard let n = WatchState.decode(d) else { return }
        DispatchQueue.main.async {
            self.buzz(n)
            self.s = n
            self.got = Date()
        }
    }

    // 快到路口、超速、电量低时手腕震一下
    private func buzz(_ n: WatchState) {
        let dev = WKInterfaceDevice.current()
        if n.navDist >= 0 {
            if n.navText != lastNavText { lastNavDist = -1 }
            for th in [200, 50] where lastNavDist > th && n.navDist <= th {
                dev.play(th == 50 ? .directionUp : .notification)
            }
            lastNavDist = n.navDist
            lastNavText = n.navText
        } else if lastNavDist >= 0 { lastNavDist = -1; lastNavText = "" }
        if n.limit > 0, n.speed > n.limit, Date().timeIntervalSince(lastOverBuzz) > 30 {
            lastOverBuzz = Date()
            dev.play(.failure)
        }
        if n.soc > 0 && n.soc <= 15 && !lowBuzzed { lowBuzzed = true; dev.play(.retry) }
        if n.soc > 20 { lowBuzzed = false }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let c = session.receivedApplicationContext
        if !c.isEmpty { apply(c) }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { apply(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { apply(applicationContext) }
}

// MARK: - 界面
private let wGreen = Color(red: 0.36, green: 0.87, blue: 0.55)
private let wAmber = Color(red: 1.0, green: 0.75, blue: 0.30)
private let wRed = Color(red: 1.0, green: 0.40, blue: 0.38)
private let wBlue = Color(red: 0.33, green: 0.57, blue: 1.0)
private func socColor(_ s: Double) -> Color { s <= 15 ? wRed : s <= 30 ? wAmber : wGreen }

private func hms(_ t: Double) -> String {
    let s = Int(t)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

struct WatchRoot: View {
    @EnvironmentObject var m: WatchModel
    var body: some View {
        TabView {
            DashPage()
            BatteryPage()
            TripPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct Stale: View {
    @EnvironmentObject var m: WatchModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            if let g = m.got, ctx.date.timeIntervalSince(g) > 15 {
                Text("\(Int(ctx.date.timeIntervalSince(g) / 60)) 分钟前的数据").font(.system(size: 10)).foregroundStyle(wAmber)
            } else if m.got == nil {
                Text("打开手机上的 app").font(.system(size: 10)).foregroundStyle(wAmber)
            }
        }
    }
}

struct DashPage: View {
    @EnvironmentObject var m: WatchModel
    var body: some View {
        let s = m.s
        let over = s.limit > 0 && s.speed > s.limit
        VStack(spacing: 2) {
            if s.navDist >= 0 {
                HStack(spacing: 4) {
                    Image(systemName: navIcon(for: s.navText)).font(.system(size: 18, weight: .bold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.navDist >= 1000 ? String(format: "%.1f km", Double(s.navDist) / 1000) : "\(s.navDist) m").font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(s.navText).font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(wBlue.opacity(0.35)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(s.speed >= 0 ? "\(s.speed)" : "--")
                    .font(.system(size: s.navDist >= 0 ? 52 : 64, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(over ? wRed : .white)
                Text("km/h").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                ZStack {
                    Circle().stroke(socColor(s.soc).opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: max(0.01, s.soc / 100)).stroke(socColor(s.soc), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(Int(s.soc))").font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.range >= 0 ? "续航 \(s.range) km" : "续航 --").font(.system(size: 13, weight: .semibold))
                    Text(s.power < 0 ? "回充 \(-s.power) W" : "\(s.power) W").font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(s.power < 0 ? wGreen : s.power > 1500 ? wRed : .secondary)
                }
                Spacer(minLength: 0)
            }
            Stale()
        }
        .padding(.horizontal, 4)
    }
}

struct BatteryPage: View {
    @EnvironmentObject var m: WatchModel
    var body: some View {
        let s = m.s
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.charging ? "充电中" : "电池").font(.headline)
                Spacer()
                if s.charging { Image(systemName: "bolt.fill").foregroundStyle(wGreen) }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<min(s.names.count, s.socs.count), id: \.self) { i in
                    VStack(spacing: 2) {
                        GeometryReader { g in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).stroke(i == s.lowIndex ? wAmber : Color.white.opacity(0.3), lineWidth: i == s.lowIndex ? 2 : 1)
                                RoundedRectangle(cornerRadius: 3).fill(socColor(Double(s.socs[i])))
                                    .frame(height: max(3, (g.size.height - 4) * CGFloat(min(max(s.socs[i], 0), 100)) / 100)).padding(2)
                            }
                        }
                        .frame(height: 54)
                        Text(s.names[i]).font(.system(size: 11, weight: .bold)).foregroundStyle(i == s.lowIndex ? wAmber : .white)
                        Text("\(s.socs[i])").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Text(s.charging ? (s.eta.map { "预计 \($0) 充满" } ?? "正在充电") : String(format: "%.0f A · 压差 %d mV · %@", abs(s.current), s.gap, s.temp > -99 ? "\(s.temp)°" : "--"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Stale()
        }
        .padding(.horizontal, 4)
    }
}

struct TripPage: View {
    @EnvironmentObject var m: WatchModel
    var body: some View {
        let s = m.s
        ScrollView {
            VStack(spacing: 6) {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { cell(String(format: "%.2f", s.distKm), "里程 km"); cell(hms(s.elapsed), "用时") }
                    GridRow { cell(s.avg >= 0 ? "\(s.avg)" : "--", "平均 km/h"); cell("\(s.maxKmh)", "最高 km/h") }
                    GridRow { cell("\(s.tripWh)", "用电 Wh"); cell(s.whKm >= 0 ? "\(s.whKm)" : "--", "Wh/km") }
                    GridRow { cell("\(s.climb)", "爬升 m"); cell(s.navLeft >= 0 ? String(format: "%.1f", Double(s.navLeft) / 1000) : "--", "离终点 km") }
                }
                Button { m.toggleRide() } label: {
                    Text(s.rideOn ? "结束骑行" : "开始骑行").font(.headline).frame(maxWidth: .infinity)
                }
                .tint(s.rideOn ? wRed : wBlue)
                .disabled(!m.reachable)
                if !m.reachable { Text("手机 app 没在运行时按不了").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
    }
    private func cell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }
}

// 和手机上的一样：按导航文字挑一个箭头
func navIcon(for t: String) -> String {
    if t.contains("掉头") { return "arrow.uturn.left" }
    if t.contains("左后") { return "arrow.down.left" }
    if t.contains("右后") { return "arrow.down.right" }
    if t.contains("向左前") || t.contains("靠左") || t.contains("稍向左") { return "arrow.up.left" }
    if t.contains("向右前") || t.contains("靠右") || t.contains("稍向右") { return "arrow.up.right" }
    if t.contains("左转") { return "arrow.turn.up.left" }
    if t.contains("右转") { return "arrow.turn.up.right" }
    if t.contains("环岛") { return "arrow.triangle.turn.up.right.circle" }
    if t.contains("到达") || t.contains("目的地") { return "flag.checkered" }
    return "arrow.up"
}
