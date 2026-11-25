import Foundation
import MapKit
import AVFoundation

// 导航：用苹果地图的骑行路线（没有骑行路线时退回步行路线），自己跟踪进度、报转弯、偏航重算。
// 路线和地图用的是地图自己的坐标；手机定位是 WGS-84，比对前按设置里的"轨迹偏移校正"换算。
final class NavManager: NSObject, ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var searching = false
    @Published var planning = false
    @Published var destination: MKMapItem?
    @Published var route: MKRoute?
    @Published var mode = "骑行"
    @Published var active = false
    @Published var nextText = ""          // 下一个动作，例如"右转进入人民路"
    @Published var nextDist: Double = -1  // 离下一个动作还有多少米
    @Published var remainingM: Double = 0
    @Published var message = ""
    @Published var voiceOn: Bool = UserDefaults.standard.object(forKey: "nav.voice") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceOn, forKey: "nav.voice") }
    }

    private let synth = AVSpeechSynthesizer()
    private var pts: [MKMapPoint] = []        // 路线上的点
    private var cum: [Double] = []            // 每个点离起点的路程（米）
    private var stepEnds: [Double] = []       // 每一步结束处离起点的路程
    private var spoken: Set<String> = []
    private var offCount = 0
    private var lastReplan = Date.distantPast
    private var lastMapPoint: MKMapPoint?

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: 搜索
    func search(_ q: String, near: CLLocation?) {
        let text = q.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        message = ""
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        if let c = near?.coordinate {
            req.region = MKCoordinateRegion(center: c, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        MKLocalSearch(request: req).start { [weak self] resp, err in
            guard let self else { return }
            self.searching = false
            self.results = resp?.mapItems ?? []
            if self.results.isEmpty { self.message = "没搜到，换个说法试试。" + (err.map { "（\($0.localizedDescription)）" } ?? "") }
        }
    }

    // MARK: 规划路线：先要骑行路线，没有就用步行路线
    func plan(to item: MKMapItem, completion: ((Bool) -> Void)? = nil) {
        destination = item
        planning = true
        message = ""
        request(item, type: .cycling) { [weak self] r in
            guard let self else { return }
            if let r {
                self.setRoute(r, mode: "骑行"); completion?(true)
            } else {
                self.request(item, type: .walking) { r2 in
                    if let r2 {
                        self.setRoute(r2, mode: "步行")
                        self.message = "这里没有骑行路线，用的是步行路线，可能会走人行道和小路。"
                        completion?(true)
                    } else {
                        self.planning = false
                        self.message = "路线规划失败，检查一下网络再试。"
                        completion?(false)
                    }
                }
            }
        }
    }

    private func request(_ item: MKMapItem, type: MKDirectionsTransportType, done: @escaping (MKRoute?) -> Void) {
        let req = MKDirections.Request()
        req.source = MKMapItem.forCurrentLocation()
        req.destination = item
        req.transportType = type
        MKDirections(request: req).calculate { resp, _ in done(resp?.routes.first) }
    }

    private func setRoute(_ r: MKRoute, mode: String) {
        planning = false
        route = r
        self.mode = mode
        let n = r.polyline.pointCount
        let p = r.polyline.points()
        pts = (0..<n).map { p[$0] }
        cum = [0]
        for i in 1..<max(n, 1) { cum.append(cum[i - 1] + pts[i - 1].distance(to: pts[i])) }
        var acc = 0.0
        stepEnds = r.steps.map { acc += $0.distance; return acc }
        remainingM = r.distance
        spoken = []
        offCount = 0
        updateNext(along: 0)
    }

    // MARK: 开始和结束
    func start() {
        guard route != nil else { return }
        active = true
        spoken = []
        LogStore.shared.log(String(format: "开始导航：%@路线 %.1f km", mode, (route?.distance ?? 0) / 1000))
        say("开始导航，全程 \(km(remainingM))。" + (nextText.isEmpty ? "" : "\(dist(nextDist))后，\(nextText)"))
    }

    func stop(arrived: Bool = false) {
        if active { LogStore.shared.log(arrived ? "导航结束：已到达" : "导航结束") }
        if active && arrived { say("已到达目的地附近，导航结束。"); onArrived?() }
        active = false
        route = nil
        destination = nil
        nextText = ""
        nextDist = -1
        pts = []; cum = []; stepEnds = []
    }

    // MARK: 每来一个定位点就更新一次
    func update(_ loc: CLLocation, gcj: Bool) {
        guard active, pts.count >= 2 else { return }
        let c = gcj ? ChinaCoord.toGCJ(loc.coordinate.latitude, loc.coordinate.longitude) : loc.coordinate
        let mp = MKMapPoint(c)
        lastMapPoint = mp
        // 找路线上离现在最近的位置
        var best = Double.greatestFiniteMagnitude, along = 0.0
        for i in 0..<(pts.count - 1) {
            let (d, t) = distToSegment(mp, pts[i], pts[i + 1])
            if d < best { best = d; along = cum[i] + t * pts[i].distance(to: pts[i + 1]) }
        }
        let total = cum.last ?? 0
        remainingM = max(0, total - along)
        // 到了
        if remainingM < 30 || (destination.map { MKMapPoint($0.placemark.coordinate).distance(to: mp) < 25 } ?? false) {
            stop(arrived: true)
            return
        }
        // 偏离路线：连续 3 次离路线 50 米以上，重新规划（至少隔 20 秒）
        if best > max(50, loc.horizontalAccuracy * 1.5) {
            offCount += 1
            if offCount >= 3, Date().timeIntervalSince(lastReplan) > 20, let dest = destination {
                offCount = 0
                lastReplan = Date()
                say("已偏离路线，正在重新规划。")
                LogStore.shared.log("导航：偏离路线，重新规划")
                let keepActive = active
                plan(to: dest) { [weak self] ok in
                    guard let self, ok, keepActive else { return }
                    self.active = true
                    if !self.nextText.isEmpty { self.say("\(self.dist(self.nextDist))后，\(self.nextText)") }
                }
            }
        } else {
            offCount = 0
        }
        updateNext(along: along)
        // 播报：离下一个动作 300 米和 50 米时各说一次
        if nextDist >= 0, !nextText.isEmpty {
            let key = nextText
            if nextDist <= 300 && nextDist > 120 && !spoken.contains(key + "300") {
                spoken.insert(key + "300"); say("前方\(dist(nextDist))，\(nextText)")
                Notifier.shared.tap("tap.nav", "前方\(dist(nextDist))", nextText)
            } else if nextDist <= 50 && !spoken.contains(key + "50") {
                spoken.insert(key + "50"); spoken.insert(key + "300"); say(nextText)
                Notifier.shared.tap("tap.nav", nextText, "就在前面")
            }
        }
    }

    /// 现在走在第几步，下一个动作是什么、还有多远
    private func updateNext(along: Double) {
        guard let r = route else { return }
        var i = 0
        while i < stepEnds.count - 1 && stepEnds[i] <= along + 5 { i += 1 }
        // 第 i 步正在走；下一个动作是第 i+1 步开头的说明，在第 i 步结束处
        let steps = r.steps
        var j = i + 1
        while j < steps.count && steps[j].instructions.trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
        if j < steps.count {
            nextText = steps[j].instructions
            nextDist = max(0, stepEnds[j - 1] - along)
        } else {
            nextText = "到达目的地"
            nextDist = remainingM
        }
    }

    private func distToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> (Double, Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
        t = min(max(t, 0), 1)
        let q = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
        return (p.distance(to: q), t)
    }

    // MARK: 语音
    var onArrived: (() -> Void)?

    func say(_ s: String) {
        guard voiceOn, !s.isEmpty else { return }
        Speaker.shared.say(s)
    }

    private func sayOld(_ s: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.52
        synth.speak(u)
    }

    func km(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f 公里", m / 1000) : "\(Int(m / 10) * 10) 米" }
    func dist(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f 公里", m / 1000) : "\(max(10, Int(m / 10) * 10)) 米" }

    /// 下一个动作对应的箭头图标
    var nextIcon: String { navIcon(for: nextText) }
}

extension NavManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {   // 说完把声音还给别的 app（音乐、高德）
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
