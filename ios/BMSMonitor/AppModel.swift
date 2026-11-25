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
    let snaps = SnapStore()
    let parking = ParkingStore()
    let perf = PerfTester()
    let maint = MaintStore()
    let favs = FavStore()
    let engine = EngineSound()
    private let alt = AltTracker()
    private let crash = CrashDetector()
    @Published var crashAlert = false
    @Published var engineOn = false {
        didSet { if engineOn && ride.on { engine.start() } else { engine.stop() } }
    }
    private var autoMoveSince: Date?
    private var stillSince: Date?
    private var manualStopAt = Date.distantPast
    private var overCount = 0
    private var lastOverAt = Date.distantPast
    private var lastEtaAt = Date.distantPast
    private var etaScheduled: Date?
    private var lastIdleAt = Date.distantPast
    @Published var checkInMsg = ""
    @Published var checkingIn = false
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
            guard let self else { return }
            self.nav.update(loc, gcj: UserDefaults.standard.object(forKey: "map.gcj") as? Bool ?? true)
            if let msg = self.perf.feed(loc, power: self.power, current: self.current, soc: self.lowest?.soc) {
                self.say(msg)
                if self.perf.phase == .done { self.evaluateBadges() }
            }
        }
        crash.onImpact = { [weak self] in
            guard let self, self.ride.on, Pref.crashOn else { return }
            LogStore.shared.log("摔车检测：检测到剧烈撞击")
            self.crashAlert = true
            self.say("检测到剧烈撞击，你没事吧？没事的话点我没事。")
        }
        maint.checkDue(odo: maint.odo(trips.trips))
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
            autoStartCheck()
            chargeEta()
            idleReminder()
            if engine.running { engine.update(speed: ride.freshSpeed ?? 0, power: power ?? 0) }
        }
    }

    func say(_ s: String) { Speaker.shared.say(s) }

    // MARK: 自动开始骑行：电池在持续放电（电机在转）6 秒以上
    private func autoStartCheck() {
        guard !ride.on, Pref.autoStart, !isCharging, Date().timeIntervalSince(manualStopAt) > 180 else { autoMoveSince = nil; return }
        if (power ?? 0) > 250 {
            if autoMoveSince == nil { autoMoveSince = Date() }
            else if Date().timeIntervalSince(autoMoveSince!) >= 6 {
                autoMoveSince = nil
                LogStore.shared.log("检测到电机在转，自动开始骑行" + (UIApplication.shared.applicationState == .background ? "（app 在后台）" : ""))
                startRide()
                say("检测到在骑车，已自动开始记录")
            }
        } else { autoMoveSince = nil }
    }

    // MARK: 充好时间预告：按现在的电流算出几点充满，提前 15 分钟提醒
    private func chargeEta() {
        let now = Date()
        guard now.timeIntervalSince(lastEtaAt) > 60 else { return }
        lastEtaAt = now
        if isCharging, let h = chargeHours, h > 0.3 {
            let eta = now.addingTimeInterval(h * 3600)
            if etaScheduled.map({ abs($0.timeIntervalSince(eta)) > 600 }) ?? true {
                etaScheduled = eta
                Notifier.shared.schedule("charge.eta", "大约 15 分钟后充满", "预计 " + eta.formatted(date: .omitted, time: .shortened) + " 充满。磷酸铁锂充满后保护板会自己停，不用急着拔。", at: eta.addingTimeInterval(-900))
                LogStore.shared.log("预计 " + eta.formatted(date: .omitted, time: .shortened) + " 充满")
            }
        } else if etaScheduled != nil, !isCharging {
            etaScheduled = nil
            Notifier.shared.cancel("charge.eta")
        }
    }
    var chargeEtaText: String? {
        guard isCharging, let h = chargeHours else { return nil }
        return Date().addingTimeInterval(h * 3600).formatted(date: .omitted, time: .shortened)
    }

    // MARK: 久放提醒：14 天没收到电池数据就提醒一次（每次收到数据都往后推）
    private func idleReminder() {
        guard Date().timeIntervalSince(lastIdleAt) > 600 else { return }
        lastIdleAt = Date()
        let soc = Int(lowest?.soc ?? 0)
        Notifier.shared.schedule("idle", "车已经两周没动了", "上次看到电量 \(soc)%。磷酸铁锂长期放着最好保持在 50%～60%，每个月至少充一次。", at: Date().addingTimeInterval(14 * 86400))
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
        alt.start()
        if Pref.crashOn { crash.start() }
        if engineOn { engine.start() }
        stillSince = nil; overCount = 0
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

    private func stopRide(auto: Bool = false) {
        tick?.invalidate(); tick = nil
        rideTick()
        if !auto { manualStopAt = Date() }
        let endAt = auto ? (stillSince ?? Date()) : Date()
        parking.save(ride.lastLocation, soc: lowest?.soc)
        alt.stop(); crash.stop(); engine.stop()
        let climb = alt.gain, descent = alt.loss
        let names = liveBlocks.map(\.name)
        let start = ride.startedAt ?? Date()
        let dist = ride.distM, moving = ride.movingS, vmax = ride.vMaxKmh, track = ride.track
        nav.stop()
        live.end(liveState())
        ride.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if dist >= 100 {
            let km = dist / 1000
            let samples = tripSamples.filter { $0.t <= endAt.timeIntervalSince(start) + 2 }
            let score = scoreTrip(samples: samples, km: km, whPerKm: km >= 0.5 && tripWh > 1 ? tripWh / km : nil)
            trips.add(Trip(start: start, end: endAt, distM: dist, movingS: moving, maxKmh: vmax,
                           energyWh: tripWh, maxPowerW: tripMaxW,
                           socStart: tripSocStart, socEnd: lowest?.soc ?? tripSocStart, samples: samples,
                           track: track.count >= 2 ? track : nil,
                           climbM: alt.available ? climb : nil, descentM: alt.available ? descent : nil,
                           score: score, blockNames: names.isEmpty ? nil : names))
            LogStore.shared.log(String(format: "这一趟用电 %.0f Wh，最大功率 %.0f W，爬升 %.0f m，评分 %d", tripWh, tripMaxW, climb, score?.total ?? -1))
            if let c = ChallengeStore.shared.check(trips.trips) {
                Notifier.shared.postNow("今日挑战完成", c.title + "，+\(ChallengeStore.pointsEach) 分")
            }
            maint.checkDue(odo: maint.odo(trips.trips))
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
            let bs = liveBlocks
            tripSamples.append(TripSample(t: now.timeIntervalSince(start), v: ride.freshSpeed ?? 0,
                                          p: power ?? 0, soc: lowest?.soc ?? 0,
                                          a: alt.current,
                                          bv: bs.count >= 2 ? bs.map { $0.cells.reduce(0, +) / Double(max($0.cells.count, 1)) } : nil))
        }
        // 超速提醒：连续 3 秒超过设定车速，30 秒内只说一次
        if Pref.speedAlertOn, let v = ride.freshSpeed, v > Pref.speedLimit {
            overCount += 1
            if overCount >= 3 && now.timeIntervalSince(lastOverAt) > 30 {
                lastOverAt = now
                say("超速了，现在 \(Int(v)) 公里")
            }
        } else { overCount = 0 }
        // 自动结束：车速和电流都停了 5 分钟
        if Pref.autoStop {
            let fresh = lastDataAt.map { now.timeIntervalSince($0) < 15 } ?? false
            let moving = (ride.freshSpeed ?? 0) > 3 || (fresh && abs(power ?? 0) > 150)
            if moving { stillSince = nil }
            else if stillSince == nil { stillSince = now }
            else if now.timeIntervalSince(stillSince!) >= 300 && perf.phase == .idle {
                LogStore.shared.log("停了 5 分钟，自动结束骑行")
                say("停了 5 分钟，已自动结束骑行")
                stopRide(auto: true)
                return
            }
        }
        if engine.running { engine.update(speed: ride.freshSpeed ?? 0, power: power ?? 0) }
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
        BadgeCtx(trips: trips.trips, charges: charges.sessions, health: health.records, navArrivals: badges.navCount, cycles: stats.cycles,
                 accelBest: perf.best30, challenges: ChallengeStore.shared.done.count)
    }
    func evaluateBadges() { badges.evaluate(badgeCtx()) }

    // MARK: 一键打卡：连上电池 → 等五块数据收齐 → 等电流稳定 → 记一条快照 → 上传
    func checkIn() {
        guard !checkingIn else { return }
        checkingIn = true
        checkInMsg = "正在连接电池…"
        if !ble.connected { ble.connect() }
        Task { @MainActor in
            defer { self.checkingIn = false }
            let t0 = Date()
            while self.liveBlocks.count < 5 || self.summary == nil {
                if Date().timeIntervalSince(t0) > 40 {
                    self.checkInMsg = self.ble.connected ? "40 秒内没收齐五块的数据，没有记录。请靠近电池再试一次。" : "没连上电池，没有记录。请靠近电池再试一次。"
                    return
                }
                if self.ble.scanning { self.checkInMsg = "请在弹出的列表里选名称结尾 01 的那一块" }
                else if self.ble.connected { self.checkInMsg = "已连接，正在等五块的数据收齐…" }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            // 电流还在变就等一会儿（最多 20 秒），各块电流差 3 安以内才记
            let t1 = Date()
            while Date().timeIntervalSince(t1) < 20 {
                let cs = self.liveBlocks.map(\.current)
                if let a = cs.max(), let b = cs.min(), a - b <= 3 { break }
                self.checkInMsg = "电流还在变，等它稳定再记…"
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let bs = self.liveBlocks
            let cells = bs.flatMap(\.cells)
            let means = bs.map { b in (b, b.cells.reduce(0, +) / Double(b.cells.count)) }
            guard let hi = cells.max(), let lo = cells.min(), let low = means.min(by: { $0.1 < $1.1 }) else { return }
            let others = means.filter { $0.0.id != low.0.id }.map(\.1)
            let lowMv = Int(((others.reduce(0, +) / Double(max(others.count, 1)) - low.1) * 1000).rounded())
            let temps = bs.flatMap(\.temps)
            let snap = Snap(t: Date(), note: self.snaps.note, soc: self.summary?.soc ?? (self.lowest?.soc ?? 0),
                            gapMv: Int(((hi - lo) * 1000).rounded()), lowName: low.0.name, lowMv: lowMv,
                            current: self.current ?? 0, lo: lo, hi: hi,
                            temp: "\(temps.min() ?? 0)~\(temps.max() ?? 0)", socMin: self.lowest?.soc ?? 0)
            self.snaps.add(snap)
            LogStore.shared.log(String(format: "打卡（%@）：电量 %g%%，整组压差 %d mV，最低的一块 %@ 平均每节低 %d mV，电流 %.2f A",
                                       snap.note, snap.soc, snap.gapMv, snap.lowName, snap.lowMv, snap.current))
            if ["放了一夜", "静置几小时", "静置半小时以上"].contains(snap.note) {
                if !(self.health.records.first.map { Calendar.current.isDateInToday($0.date) } ?? false) {
                    self.health.add(blocks: bs, summarySoc: self.summary?.soc, manual: true)
                }
            }
            let summary = "已记下：整组压差 \(snap.gapMv) mV，\(snap.lowName) 低 \(snap.lowMv) mV。"
            if Keychain.load() == nil { self.checkInMsg = summary + "还没有保存上传密钥，所以没有上传。"; return }
            self.checkInMsg = summary + "正在上传…"
            let tail = "=== 快照 ===\n" + self.snaps.csv()
            let msg = await Uploader.upload(tail: tail)
            self.checkInMsg = summary + (msg.hasPrefix("已上传") ? "已上传。" : msg)
            self.refreshStored()
        }
    }

    // MARK: 上传
    func upload() {
        guard !uploading else { return }
        uploading = true
        uploadMsg = "正在上传…"
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "upload") { UIApplication.shared.endBackgroundTask(bg) }
        Task {
            let tail = await MainActor.run { "=== 快照 ===\n" + self.snaps.csv() }
            let msg = await Uploader.upload(tail: tail)
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
