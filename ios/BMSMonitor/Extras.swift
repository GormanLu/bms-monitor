import Foundation

// MARK: - 小工具：把一组 Codable 存成一个 JSON 文件
final class JSONFile<T: Codable> {
    private let url: URL
    init(_ name: String) {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }
    func load() -> T? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    func save(_ v: T) {
        let u = url
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(v) { try? d.write(to: u, options: .atomic) }
        }
    }
}

// MARK: - 充电记录
struct ChargeSession: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var ahIn: Double          // 五块平均充进去多少安时
    var wh: Double            // 充进去多少瓦时（电池这边量的）
    var maxW: Double
    var socStart: Double      // 最低一块
    var socEnd: Double
    var stops: [String] = []  // 各块停止进电的先后顺序
    var complete: Bool        // 是不是充满后保护板自己停的
    var note: String = ""

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

final class ChargeStore: ObservableObject {
    @Published private(set) var sessions: [ChargeSession] = []
    private let file = JSONFile<[ChargeSession]>("charges.json")

    // 正在进行的这一次
    private var cur: ChargeSession?
    private var curMeanAh0 = 0.0
    private var lastAt = Date()
    private var idleSince: Date?

    init() { sessions = file.load() ?? [] }

    var onSaved: ((ChargeSession) -> Void)?

    func delete(at o: IndexSet) { sessions.remove(atOffsets: o); file.save(sessions) }

    /// 每收到一批数据调用一次
    func feed(blocks: [BlockData], power: Double?) {
        let now = Date()
        guard blocks.count >= 2 else { return }
        let meanAh = blocks.map(\.remainAh).reduce(0, +) / Double(blocks.count)
        let lowSoc = blocks.min { $0.remainAh < $1.remainAh }?.soc ?? 0
        let charging = blocks.contains { $0.current > 0.5 } && !blocks.contains { $0.current < -2 }
        let discharging = blocks.contains { $0.current < -2 }

        // 断开很久又连上：之前那次就算结束了
        if var c = cur, now.timeIntervalSince(lastAt) > 1800 {
            c.note = "中途断开过，后半段没记到"
            finish(c, meanAh: meanAh, soc: lowSoc, at: lastAt)
        }
        let dt = min(now.timeIntervalSince(lastAt), 10)
        lastAt = now

        if cur == nil {
            if charging {
                cur = ChargeSession(start: now, end: now, ahIn: 0, wh: 0, maxW: 0, socStart: lowSoc, socEnd: lowSoc, complete: false)
                curMeanAh0 = meanAh
                idleSince = nil
                LogStore.shared.log("开始记录这次充电")
            }
            return
        }
        guard var c = cur else { return }
        if let p = power, p < 0 { c.wh += -p * dt / 3600; c.maxW = max(c.maxW, -p) }
        c.end = now
        // 记下各块停止进电的先后（别的块还在充时）
        if charging {
            for b in blocks where abs(b.current) < 0.2 && !c.stops.contains(b.name) { c.stops.append(b.name) }
            idleSince = nil
        }
        if blocks.contains(where: \.chargeShut) { c.complete = true }
        cur = c
        if discharging {
            finish(c, meanAh: meanAh, soc: lowSoc, at: now)
        } else if !charging {
            if idleSince == nil { idleSince = now }
            if let s = idleSince, now.timeIntervalSince(s) > 60 {    // 所有块都不进电一分钟：这次充电结束
                for b in blocks where !c.stops.contains(b.name) { c.stops.append(b.name) }
                finish(c, meanAh: meanAh, soc: lowSoc, at: s)
            }
        }
    }

    private func finish(_ c0: ChargeSession, meanAh: Double, soc: Double, at: Date) {
        var c = c0
        cur = nil
        idleSince = nil
        c.end = at
        c.ahIn = max(0, meanAh - curMeanAh0)
        c.socEnd = soc
        guard c.duration >= 300 else { return }      // 不到 5 分钟的不算
        sessions.insert(c, at: 0)
        file.save(sessions)
        LogStore.shared.log(String(format: "这次充电：%.1f 小时，充进 %.1f Ah / %.0f Wh，%@", c.duration / 3600, c.ahIn, c.wh, c.complete ? "保护板充满后停的" : "中途停的"))
        onSaved?(c)
    }
}

// MARK: - 电池健康：每天记一次静置时的数
struct HealthRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var soc: Double           // 保护板汇总电量（没有就用最低块）
    var packGapMv: Int        // 整组最高最低差
    var pLowMv: Int           // P 平均每节比其他块低多少（负数表示比别的高）
    var lowName: String       // 平均电压最低的一块
    var lowMv: Int            // 它比其他块平均低多少
    var temp: Int
    var manual: Bool = false
}

final class HealthStore: ObservableObject {
    @Published private(set) var records: [HealthRecord] = []
    private let file = JSONFile<[HealthRecord]>("health.json")
    private var restSince: Date?

    init() { records = file.load() ?? [] }

    func delete(at o: IndexSet) { records.remove(atOffsets: o); file.save(records) }

    /// 每收到一批数据调用一次：电流连续 1 分钟都接近 0，而且今天还没记过，就记一条
    func feed(blocks: [BlockData], summarySoc: Double?) {
        let now = Date()
        guard blocks.count >= 5 else { restSince = nil; return }
        let resting = blocks.allSatisfy { abs($0.current) < 0.3 }
        if !resting { restSince = nil; return }
        if restSince == nil { restSince = now }
        guard let s = restSince, now.timeIntervalSince(s) >= 60 else { return }
        if let last = records.first, Calendar.current.isDate(last.date, inSameDayAs: now) { return }
        add(blocks: blocks, summarySoc: summarySoc, manual: false)
    }

    @discardableResult
    func add(blocks: [BlockData], summarySoc: Double?, manual: Bool) -> Bool {
        guard blocks.count >= 2 else { return false }
        let means = blocks.map { b in (b, b.cells.reduce(0, +) / Double(b.cells.count)) }
        let cells = blocks.flatMap(\.cells)
        guard let hi = cells.max(), let lo = cells.min(), let low = means.min(by: { $0.1 < $1.1 }) else { return false }
        func othersMean(_ x: BlockData) -> Double {
            let o = means.filter { $0.0.id != x.id }.map(\.1)
            return o.reduce(0, +) / Double(max(o.count, 1))
        }
        let p = means.first { $0.0.id == 0x50 }
        let r = HealthRecord(
            date: Date(),
            soc: summarySoc ?? (blocks.min { $0.remainAh < $1.remainAh }?.soc ?? 0),
            packGapMv: Int(((hi - lo) * 1000).rounded()),
            pLowMv: p.map { Int(((othersMean($0.0) - $0.1) * 1000).rounded()) } ?? 0,
            lowName: low.0.name,
            lowMv: Int(((othersMean(low.0) - low.1) * 1000).rounded()),
            temp: blocks.flatMap(\.temps).max() ?? 0,
            manual: manual)
        records.insert(r, at: 0)
        file.save(records)
        LogStore.shared.log("电池健康记录：电量 \(Int(r.soc))%，整组压差 \(r.packGapMv) mV，P 平均每节低 \(r.pLowMv) mV")
        return true
    }
}

// MARK: - 成就徽章
struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
}

final class BadgeStore: ObservableObject {
    static let all: [Badge] = [
        Badge(id: "first", title: "出发", detail: "完成第一次骑行记录", icon: "flag.fill"),
        Badge(id: "ride10", title: "十公里", detail: "单趟骑满 10 公里", icon: "10.circle.fill"),
        Badge(id: "ride20", title: "远行", detail: "单趟骑满 20 公里", icon: "map.fill"),
        Badge(id: "total100", title: "百里", detail: "累计骑满 100 公里", icon: "100.circle.fill"),
        Badge(id: "total500", title: "五百里", detail: "累计骑满 500 公里", icon: "star.circle.fill"),
        Badge(id: "total1000", title: "千里", detail: "累计骑满 1000 公里", icon: "crown.fill"),
        Badge(id: "speed30", title: "疾风", detail: "车速到过 30 km/h", icon: "wind"),
        Badge(id: "eco", title: "省电达人", detail: "单趟 3 公里以上、每公里不到 25 Wh", icon: "leaf.fill"),
        Badge(id: "night", title: "夜骑", detail: "晚上 8 点以后出发", icon: "moon.stars.fill"),
        Badge(id: "early", title: "早起", detail: "早上 5 点到 7 点出发", icon: "sunrise.fill"),
        Badge(id: "streak3", title: "三天不停", detail: "连续 3 天都骑了车", icon: "flame.fill"),
        Badge(id: "streak7", title: "一周全勤", detail: "连续 7 天都骑了车", icon: "calendar.badge.checkmark"),
        Badge(id: "charge", title: "满电", detail: "记到一次保护板自己停的完整充电", icon: "battery.100.bolt"),
        Badge(id: "nav", title: "认路", detail: "第一次用导航到达目的地", icon: "location.north.circle.fill"),
    ]

    @Published private(set) var unlocked: [String: Date] = [:]
    @Published var justUnlocked: Badge?
    private let file = JSONFile<[String: Date]>("badges.json")

    init() { unlocked = file.load() ?? [:] }

    func unlock(_ id: String) {
        guard unlocked[id] == nil, let b = BadgeStore.all.first(where: { $0.id == id }) else { return }
        unlocked[id] = Date()
        file.save(unlocked)
        justUnlocked = b
        Notifier.shared.badge(b)
        LogStore.shared.log("解锁徽章：" + b.title)
    }

    func check(trips: [Trip]) {
        guard let t = trips.first else { return }
        unlock("first")
        if t.km >= 10 { unlock("ride10") }
        if t.km >= 20 { unlock("ride20") }
        let total = trips.reduce(0) { $0 + $1.km }
        if total >= 100 { unlock("total100") }
        if total >= 500 { unlock("total500") }
        if total >= 1000 { unlock("total1000") }
        if t.maxKmh >= 30 { unlock("speed30") }
        if t.km >= 3, let w = t.whPerKm, w < 25 { unlock("eco") }
        let h = Calendar.current.component(.hour, from: t.start)
        if h >= 20 || h < 3 { unlock("night") }
        if h >= 5 && h < 7 { unlock("early") }
        // 连续几天都骑了
        let days = Set(trips.map { Calendar.current.startOfDay(for: $0.start) })
        var streak = 0
        var d = Calendar.current.startOfDay(for: Date())
        while days.contains(d) { streak += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        if streak >= 3 { unlock("streak3") }
        if streak >= 7 { unlock("streak7") }
    }
}
