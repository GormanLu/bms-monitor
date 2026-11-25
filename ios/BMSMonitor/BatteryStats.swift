import Foundation

// 循环次数和健康度。
// 保护板里找不到能确认的循环次数（有个字节一直是 3，满放满充一轮也没变），它记的满电容量也一直是出厂的 60 Ah。
// 所以循环次数由 app 自己数：每次看到五块的平均剩余容量变少，就把少的那部分记作"放出"；
// 累计放出的电 ÷ 60 Ah = 等效满充满放次数。没连着 app 时的放电，只要中间没充电，下次连上也能补算出来。
final class BatteryStats: ObservableObject {
    @Published private(set) var dischargedAh: Double
    @Published private(set) var chargedAh: Double
    @Published var baselineCycles: Double {
        didSet { UserDefaults.standard.set(baselineCycles, forKey: "bat.baseline") }
    }
    @Published private(set) var bmsHealth: Int?     // 保护板字节 [25] ÷ 2（推测是健康度）
    @Published private(set) var bmsCycles: [String: Int] = [:]   // 保护板字节 [22]，各块分开（推测是循环计数）

    private var lastMeanAh: Double?
    private var lastSave = Date.distantPast
    static let nominalAh = 60.0
    /// 磷酸铁锂一般按 2000 次循环后剩 80% 容量来估
    static let ratedCycles = 2000.0

    init() {
        let d = UserDefaults.standard
        dischargedAh = d.double(forKey: "bat.discharged")
        chargedAh = d.double(forKey: "bat.charged")
        // 11 月 19 日到 25 日的日志里已经放出约 58 Ah（约 1 次），app 从 25 日才开始数，所以默认先补 1 次
        baselineCycles = d.object(forKey: "bat.baseline") as? Double ?? 1
        lastMeanAh = d.object(forKey: "bat.lastMean") as? Double
    }

    var cycles: Double { baselineCycles + dischargedAh / BatteryStats.nominalAh }
    /// 按循环次数折算的健康度（估算）：0 次 100%，2000 次 80%
    var cycleHealth: Double { max(0, 100 - cycles / BatteryStats.ratedCycles * 20) }

    func feed(blocks: [BlockData]) {
        guard blocks.count >= 5 else { return }
        let mean = blocks.map(\.remainAh).reduce(0, +) / Double(blocks.count)
        if let h = blocks.map({ Int($0.raw25) }).max() { bmsHealth = h / 2 }
        for b in blocks { bmsCycles[b.name] = Int(b.raw22) }
        if let last = lastMeanAh {
            let d = last - mean
            if d > 0 && d < 70 { dischargedAh += d }
            if d < 0 && d > -70 { chargedAh += -d }
        }
        lastMeanAh = mean
        if Date().timeIntervalSince(lastSave) > 30 { save() }
    }

    func save() {
        lastSave = Date()
        let d = UserDefaults.standard
        d.set(dischargedAh, forKey: "bat.discharged")
        d.set(chargedAh, forKey: "bat.charged")
        if let m = lastMeanAh { d.set(m, forKey: "bat.lastMean") }
    }
}
