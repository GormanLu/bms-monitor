import Foundation
import SwiftUI

// 成就系统：每个徽章分铜、银、金、钻石四级，有进度条；拿到的级别给积分，积分决定等级和称号。
// 第一次打开时会按已有的记录补发（不弹提示），之后新拿到的会弹出来。

struct BadgeCtx {
    var trips: [Trip]
    var charges: [ChargeSession]
    var health: [HealthRecord]
    var navArrivals: Int
    var cycles: Double
}

struct BadgeDef: Identifiable {
    let id: String
    let title: String
    let icon: String
    let category: String
    let unit: String
    let tiers: [Double]
    var lowerIsBetter = false
    let how: String                      // 说明，{n} 换成门槛
    let value: (BadgeCtx) -> Double?

    func tier(_ v: Double?) -> Int {
        guard let v else { return 0 }
        return tiers.filter { lowerIsBetter ? (v > 0 && v <= $0) : v >= $0 }.count
    }
    func text(_ i: Int) -> String {
        let n = tiers[min(i, tiers.count - 1)]
        return how.replacingOccurrences(of: "{n}", with: n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n))
    }
}

struct BadgeUnlock: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    let tier: Int
}

enum Tier {
    static let names = ["铜", "银", "金", "钻石"]
    static let points = [10, 25, 50, 100]
    static func color(_ t: Int) -> Color {
        switch t {
        case 1: return Color(red: 0.80, green: 0.50, blue: 0.25)
        case 2: return Color(red: 0.78, green: 0.80, blue: 0.85)
        case 3: return Color(red: 1.00, green: 0.80, blue: 0.25)
        case 4: return Color(red: 0.55, green: 0.85, blue: 1.00)
        default: return Color.white.opacity(0.15)
        }
    }
}

final class BadgeStore: ObservableObject {
    private struct Saved: Codable { var tiers: [String: Int] = [:]; var dates: [String: Date] = [:]; var navCount = 0 }

    @Published private(set) var tiers: [String: Int] = [:]
    @Published private(set) var dates: [String: Date] = [:]
    @Published private(set) var navCount = 0
    @Published var justUnlocked: BadgeUnlock?
    @Published private(set) var lastCtx: BadgeCtx?
    private let file = JSONFile<Saved>("badges2.json")

    init() {
        if let s = file.load() { tiers = s.tiers; dates = s.dates; navCount = s.navCount }
    }

    private func save() { file.save(Saved(tiers: tiers, dates: dates, navCount: navCount)) }

    func navArrived() { navCount += 1; save() }

    var points: Int { tiers.values.reduce(0) { acc, t in acc + Tier.points.prefix(max(0, min(t, 4))).reduce(0, +) } }
    var unlockedCount: Int { tiers.values.filter { $0 > 0 }.count }

    static let levels: [(Int, String)] = [(0, "新手骑手"), (60, "熟练骑手"), (180, "老司机"), (400, "骑行达人"), (800, "电驴传奇"), (1500, "三轮之王")]
    var level: (index: Int, title: String, floor: Int, next: Int?) {
        let p = points
        let i = BadgeStore.levels.lastIndex { p >= $0.0 } ?? 0
        return (i + 1, BadgeStore.levels[i].1, BadgeStore.levels[i].0, i + 1 < BadgeStore.levels.count ? BadgeStore.levels[i + 1].0 : nil)
    }

    /// 重新算一遍所有徽章；silent = 只补发，不弹提示
    func evaluate(_ ctx: BadgeCtx, silent: Bool = false) {
        lastCtx = ctx
        var best: BadgeUnlock?
        for d in BadgeStore.all {
            let t = d.tier(d.value(ctx))
            if t > (tiers[d.id] ?? 0) {
                tiers[d.id] = t
                dates[d.id] = Date()
                let u = BadgeUnlock(title: d.title + " · " + Tier.names[t - 1], detail: d.text(t - 1), icon: d.icon, tier: t)
                if best == nil || t > best!.tier { best = u }
                LogStore.shared.log("解锁徽章：" + u.title)
                if !silent { Notifier.shared.badge(u) }
            }
        }
        save()
        if !silent, let b = best { justUnlocked = b }
    }

    // MARK: 徽章定义
    static let all: [BadgeDef] = {
        func streak(_ trips: [Trip]) -> Double {
            let days = Set(trips.map { Calendar.current.startOfDay(for: $0.start) }).sorted()
            var best = 0, cur = 0
            var prev: Date?
            for d in days {
                if let p = prev, Calendar.current.date(byAdding: .day, value: 1, to: p) == d { cur += 1 } else { cur = 1 }
                best = max(best, cur); prev = d
            }
            return Double(best)
        }
        func hourCount(_ trips: [Trip], _ ok: (Int) -> Bool) -> Double {
            Double(trips.filter { ok(Calendar.current.component(.hour, from: $0.start)) }.count)
        }
        func bestMonthKm(_ trips: [Trip]) -> Double {
            var m: [String: Double] = [:]
            for t in trips {
                let c = Calendar.current.dateComponents([.year, .month], from: t.start)
                m["\(c.year!)-\(c.month!)", default: 0] += t.km
            }
            return m.values.max() ?? 0
        }
        return [
            BadgeDef(id: "km", title: "里程", icon: "road.lanes", category: "骑行", unit: "km", tiers: [10, 100, 500, 2000], how: "累计骑 {n} 公里") { Double($0.trips.reduce(0) { $0 + $1.km }) },
            BadgeDef(id: "far", title: "远行", icon: "map.fill", category: "骑行", unit: "km", tiers: [5, 10, 20, 40], how: "单趟骑满 {n} 公里") { $0.trips.map(\.km).max() },
            BadgeDef(id: "trips", title: "常客", icon: "figure.outdoor.cycle", category: "骑行", unit: "趟", tiers: [1, 10, 50, 200], how: "骑行 {n} 趟") { Double($0.trips.count) },
            BadgeDef(id: "hours", title: "时光", icon: "clock.fill", category: "骑行", unit: "小时", tiers: [1, 10, 50, 200], how: "累计骑 {n} 小时") { $0.trips.reduce(0) { $0 + $1.duration } / 3600 },
            BadgeDef(id: "long", title: "一口气", icon: "timer", category: "骑行", unit: "分钟", tiers: [15, 30, 60, 120], how: "单趟骑 {n} 分钟") { ($0.trips.map(\.duration).max() ?? 0) / 60 },
            BadgeDef(id: "month", title: "月度骑手", icon: "calendar", category: "骑行", unit: "km", tiers: [50, 150, 300, 600], how: "一个月里骑 {n} 公里") { bestMonthKm($0.trips) },
            BadgeDef(id: "speed", title: "疾风", icon: "wind", category: "技术", unit: "km/h", tiers: [25, 30, 35, 40], how: "车速到过 {n} km/h") { $0.trips.map(\.maxKmh).max() },
            BadgeDef(id: "eco", title: "省电达人", icon: "leaf.fill", category: "技术", unit: "Wh/km", tiers: [30, 27, 24, 21], lowerIsBetter: true, how: "单趟 3 公里以上、每公里不到 {n} Wh") {
                $0.trips.filter { $0.km >= 3 }.compactMap(\.whPerKm).min()
            },
            BadgeDef(id: "nav", title: "认路", icon: "location.north.circle.fill", category: "技术", unit: "次", tiers: [1, 5, 20, 50], how: "用导航到达 {n} 次") { Double($0.navArrivals) },
            BadgeDef(id: "streak", title: "坚持", icon: "flame.fill", category: "习惯", unit: "天", tiers: [3, 7, 14, 30], how: "连续 {n} 天都骑车") { streak($0.trips) },
            BadgeDef(id: "days", title: "活跃", icon: "calendar.badge.checkmark", category: "习惯", unit: "天", tiers: [5, 20, 60, 150], how: "骑车的日子累计 {n} 天") {
                Double(Set($0.trips.map { Calendar.current.startOfDay(for: $0.start) }).count)
            },
            BadgeDef(id: "night", title: "夜骑", icon: "moon.stars.fill", category: "习惯", unit: "次", tiers: [1, 5, 20, 50], how: "晚上 8 点后出发 {n} 次") { hourCount($0.trips) { $0 >= 20 || $0 < 3 } },
            BadgeDef(id: "early", title: "早起", icon: "sunrise.fill", category: "习惯", unit: "次", tiers: [1, 5, 20, 50], how: "早上 5～7 点出发 {n} 次") { hourCount($0.trips) { $0 >= 5 && $0 < 7 } },
            BadgeDef(id: "charges", title: "充电", icon: "powerplug.fill", category: "电池", unit: "次", tiers: [1, 10, 50, 150], how: "记录到 {n} 次充电") { Double($0.charges.count) },
            BadgeDef(id: "full", title: "满电", icon: "battery.100.bolt", category: "电池", unit: "次", tiers: [1, 5, 20, 50], how: "保护板自己停的完整充电 {n} 次") { Double($0.charges.filter(\.complete).count) },
            BadgeDef(id: "cycles", title: "循环", icon: "arrow.triangle.2.circlepath", category: "电池", unit: "次", tiers: [1, 10, 50, 100], how: "等效满充满放 {n} 次") { $0.cycles },
            BadgeDef(id: "health", title: "体检", icon: "stethoscope", category: "电池", unit: "天", tiers: [1, 7, 30, 100], how: "记了 {n} 天电池健康") { Double($0.health.count) },
        ]
    }()
}
