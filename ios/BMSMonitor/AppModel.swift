import Foundation
import UIKit

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let ble = BLEManager()
    let ride = RideTracker()
    let trips = TripStore()
    let nav = NavManager()
    let charges = ChargeStore()
    let health = HealthStore()
    let badges = BadgeStore()
    let stats = BatteryStats()
    @Published var voiceKm: Bool = UserDefaults.standard.object(forKey: "voice.km") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceKm, forKey: "voice.km") }
    }
    private var lastKmSpoken = 0
    private let live = LiveActivityManager()
    private let parser = FrameParser()
    private var lastRx: Date?

    @Published var tab = 0
    @Published var blocks: [UInt8: BlockData] = [:]
    @Published var summary: SummaryData?
    @Published var lastDataAt: Date?
    @Published var uploading = false
    @Published var uploadMsg = ""
    @Published var storedBytes = 0
    @Published var autoUpload: Bool = UserDefaults.standard.object(forKey: "autoUpload") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoUpload, forKey: "autoUpload") }
    }

    // 这一趟骑行的电池数据
    @Published private(set) var tripWh: Double = 0
    @Published private(set) var tripMaxW: Double = 0
    private var tripSamples: [TripSample] = []
    private var tripSocStart: Double = 0
    private var tick: Timer?
    private var lastTick = Date()
    private var tickCount = 0

    private init() {
        LogStore.shared.log("App 启动（\(Uploader.appVersion)）")
        Notifier.shared.setup()
        ble.onData = { [weak self] bytes in self?.onBytes(bytes) }
        charges.onSaved = { [weak self] _ in self?.evaluateBadges() }
        nav.onArrived = { [weak self] in self?.badges.navArrived(); self?.evaluateBadges() }
        badges.evaluate(badgeCtx(), silent: true)       // 按已有记录补发，不弹提示
        Notifier.shared.onAlert = { [weak self] text in
            if self?.ride.on == true { Speaker.shared.say(text) }     // 骑车时把提醒也念出来
        }
        ride.onLocation = { [weak self] loc in
            self?.nav.update(loc, gcj: UserDefaults.standard.object(forKey: "map.gcj") as? Bool ?? true)
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            LogStore.shared.log("App 切到后台")
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            LogStore.shared.log("App 回到前台")
            self?.refreshStored()
        }
        refreshStored()
    }

    private func onBytes(_ bytes: [UInt8]) {
        let now = Date()
        if let l = lastRx, now.timeIntervalSince(l) > 15 {
            LogStore.shared.log("中间有 \(Int(now.timeIntervalSince(l))) 秒没有收到电池数据")
        }
        lastRx = now
        LogStore.shared.log("收 " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        let frames = parser.feed(bytes)
        for fr in frames {
            switch fr {
            case .block(let b): blocks[b.id] = b
            case .summary(let s): summary = s
            }
            lastDataAt = now
        }
        if !frames.isEmpty {
            let bs = liveBlocks
            Notifier.shared.check(blocks: bs)
            charges.feed(blocks: bs, power: power)
            let n = health.records.count
            health.feed(blocks: bs, summarySoc: summary?.soc)
            if health.records.count != n { evaluateBadges() }
            stats.feed(blocks: bs)
        }
    }

    // MARK: 给界面用的数
    var liveBlocks: [BlockData] {
        blocks.values.filter { Date().timeIntervalSince($0.at) < 30 }.sorted { $0.id < $1.id }
    }
    /// 剩余容量最低的一块：五块串联，哪一块先放空，整车就断电
    var lowest: BlockData? { liveBlocks.min { $0.remainAh < $1.remainAh } }
    var current: Double? {
        let l = liveBlocks
        return l.isEmpty ? nil : l.map(\.current).reduce(0, +) / Double(l.count)
    }
    var cells: [Double] { liveBlocks.flatMap(\.cells) }
    var totalV: Double? { cells.isEmpty ? nil : cells.reduce(0, +) }
    /// 电池输出功率，放电为正、充电为负；零点几安的读数当作 0
    var power: Double? {
        guard let i = current, let v = totalV else { return nil }
        return abs(i) < 0.6 ? 0 : -i * v
    }
    var tempRange: (Int, Int)? {
        let t = liveBlocks.flatMap(\.temps)
        guard let lo = t.min(), let hi = t.max() else { return nil }
        return (lo, hi)
    }
    var packGapMv: Int? {
        guard let hi = cells.max(), let lo = cells.min() else { return nil }
        return Int(((hi - lo) * 1000).rounded())
    }
    var isCharging: Bool {
        let l = liveBlocks
        return l.contains { $0.current > 0.5 } && !l.contains { $0.current < -2 }
    }
    /// 充满还要多久（小时）：还在进电的几块里，离满最远的那一块按它自己的电流算
    var chargeHours: Double? {
        let ins = liveBlocks.filter { $0.current > 0.5 }
        guard !ins.isEmpty else { return nil }
        return ins.map { max(0, $0.nominalAh - $0.remainAh) / $0.current }.max()
    }
    /// 每公里耗电：最近几趟的平均，没有记录时按实测的 27 Wh/km
    var whPerKm: Double { trips.recentWhPerKm ?? 27 }
    /// 估算还能跑多远：最低一块剩下的电（按每节 3.2 V 算），留一成余量
    var rangeKm: Double? {
        guard let lo = lowest, liveBlocks.count >= 2 else { return nil }
        let wh = lo.remainAh * 3.2 * Double(cells.count) * 0.9
        return max(0, wh / whPerKm)
    }

    // MARK: 骑行
    func toggleRide() {
        if ride.on { stopRide() } else { startRide() }
    }

    private func startRide() {
        ride.start()
        tripWh = 0; tripMaxW = 0; tripSamples = []; tickCount = 0
        tripSocStart = lowest?.soc ?? 0
        lastKmSpoken = 0
        lastTick = Date()
        UIApplication.shared.isIdleTimerDisabled = true          // 骑车时屏幕常亮
        live.start(liveState())
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.rideTick() }
        tab = 1
    }

    private func stopRide() {
        tick?.invalidate(); tick = nil
        rideTick()
        let start = ride.startedAt ?? Date()
        let dist = ride.distM, moving = ride.movingS, vmax = ride.vMaxKmh, track = ride.track
        nav.stop()
        live.end(liveState())
        ride.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if dist >= 100 {
            trips.add(Trip(start: start, end: Date(), distM: dist, movingS: moving, maxKmh: vmax,
                           energyWh: tripWh, maxPowerW: tripMaxW,
                           socStart: tripSocStart, socEnd: lowest?.soc ?? tripSocStart, samples: tripSamples,
                           track: track.count >= 2 ? track : nil))
            LogStore.shared.log(String(format: "这一趟用电 %.0f Wh，最大功率 %.0f W", tripWh, tripMaxW))
            evaluateBadges()
        }
        if autoUpload && Keychain.load() != nil { upload() }   // 骑完自动传一次
    }

    private func rideTick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 5)
        lastTick = now
        guard ride.on else { return }
        if let p = power, let t = lastDataAt, now.timeIntervalSince(t) < 10 {
            tripWh += p * dt / 3600
            tripMaxW = max(tripMaxW, p)
        }
        tickCount += 1
        if tickCount % 2 == 0, let start = ride.startedAt {
            tripSamples.append(TripSample(t: now.timeIntervalSince(start), v: ride.freshSpeed ?? 0,
                                          p: power ?? 0, soc: lowest?.soc ?? 0))
        }
        live.update(liveState())
        // 每骑 1 公里报一次
        let k = Int(ride.distM / 1000)
        if k > lastKmSpoken {
            lastKmSpoken = k
            if voiceKm {
                var s = "已骑 \(k) 公里"
                if let lo = lowest { s += "，电量 \(Int(lo.soc))%" }
                if let r = rangeKm { s += "，还能跑 \(Int(r)) 公里" }
                if let w = tripWhPerKm { s += "，每公里 \(Int(w.rounded())) 瓦时" }
                Speaker.shared.say(s)
            }
        }
    }

    private func liveState() -> RideAttributes.ContentState {
        let bs = liveBlocks
        var s = RideAttributes.ContentState(
            speed: ride.freshSpeed.map { Int($0.rounded()) } ?? -1,
            soc: lowest?.soc ?? 0,
            power: Int((power ?? 0).rounded()),
            distKm: ride.distM / 1000,
            rangeKm: rangeKm.map { Int($0) } ?? -1,
            charging: isCharging)
        let i = current ?? 0
        s.current = abs(i) < 0.6 ? 0 : -i
        s.voltage = totalV ?? 0
        s.tempMax = tempRange?.1 ?? -99
        s.avgKmh = ride.movingS > 10 ? Int((ride.distM / ride.movingS * 3.6).rounded()) : -1
        s.maxKmh = Int(ride.vMaxKmh.rounded())
        s.tripWh = Int(tripWh.rounded())
        s.whPerKm = tripWhPerKm.map { Int($0.rounded()) } ?? -1
        s.blockNames = bs.map(\.name)
        s.blockSocs = bs.map { Int($0.soc) }
        s.lowIndex = lowest.flatMap { lo in bs.firstIndex { $0.id == lo.id } } ?? -1
        s.left = UserDefaults.standard.string(forKey: "island.left") ?? "speed"
        s.right = UserDefaults.standard.string(forKey: "island.right") ?? "soc"
        if nav.active {
            s.navText = nav.nextText
            s.navDist = Int(nav.nextDist.rounded())
            s.navLeftM = Int(nav.remainingM.rounded())
        }
        return s
    }

    var tripWhPerKm: Double? { ride.distM >= 500 && tripWh > 1 ? tripWh / (ride.distM / 1000) : nil }

    // MARK: 徽章
    func badgeCtx() -> BadgeCtx {
        BadgeCtx(trips: trips.trips, charges: charges.sessions, health: health.records, navArrivals: badges.navCount, cycles: stats.cycles)
    }
    func evaluateBadges() { badges.evaluate(badgeCtx()) }

    // MARK: 上传
    func upload() {
        guard !uploading else { return }
        uploading = true
        uploadMsg = "正在上传…"
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "upload") { UIApplication.shared.endBackgroundTask(bg) }
        Task {
            let msg = await Uploader.upload()
            let size = await LogStore.shared.storedBytes()
            await MainActor.run {
                self.uploadMsg = msg
                self.uploading = false
                self.storedBytes = size
                UIApplication.shared.endBackgroundTask(bg)
            }
        }
    }

    func refreshStored() {
        Task {
            let size = await LogStore.shared.storedBytes()
            await MainActor.run { self.storedBytes = size }
        }
    }
}
