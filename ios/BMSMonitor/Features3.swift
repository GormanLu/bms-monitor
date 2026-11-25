import Foundation
import SwiftUI
import CoreMotion
import AVFoundation
import MapKit

// MARK: - 设置项
enum Pref {
    static var d: UserDefaults { .standard }
    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static func double(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    static var speedAlertOn: Bool { bool("speed.alert", true) }
    static var speedLimit: Double { double("speed.limit", 30) }
    static var autoStart: Bool { bool("ride.autoStart", true) }
    static var autoStop: Bool { bool("ride.autoStop", true) }
    static var weeklyKm: Double { double("goal.week", 30) }
    static var fuelPrice: Double { double("cost.fuel", 7.5) }
    static var fuelPer100: Double { double("cost.l100", 6) }
    static var taxiPerKm: Double { double("cost.taxi", 2.5) }
}

// MARK: - 仪表主题（按等级解锁）
enum ThemeKind: String, CaseIterable, Identifiable {
    case blue, green, orange, purple, gold
    var id: String { rawValue }
    var title: String { ["默认蓝", "霓虹绿", "落日橙", "赛博紫", "黑金"][index] }
    var unlockLevel: Int { [1, 2, 3, 4, 5][index] }
    var index: Int { ThemeKind.allCases.firstIndex(of: self)! }
    var accent: Color {
        switch self {
        case .blue: return Color(red: 0.33, green: 0.57, blue: 1.0)
        case .green: return Color(red: 0.20, green: 0.95, blue: 0.60)
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.25)
        case .purple: return Color(red: 0.72, green: 0.45, blue: 1.0)
        case .gold: return Color(red: 0.95, green: 0.78, blue: 0.35)
        }
    }
    static var current: ThemeKind { ThemeKind(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "blue") ?? .blue }
}

// MARK: - 省钱和减碳
struct Savings {
    var km = 0.0, elec = 0.0, fuel = 0.0, taxi = 0.0, co2 = 0.0
    var trees: Double { co2 / 18 }          // 一棵树一年大约吸收 18 kg 二氧化碳
}

func savings(_ trips: [Trip], price: Double) -> Savings {
    let km = trips.reduce(0) { $0 + $1.km }, kwh = trips.reduce(0) { $0 + $1.energyWh } / 1000 / 0.85
    let litres = km / 100 * Pref.fuelPer100
    // 汽油每升约排 2.3 kg 二氧化碳，电网每度电约 0.57 kg
    return Savings(km: km, elec: kwh * price, fuel: litres * Pref.fuelPrice, taxi: km * Pref.taxiPerKm, co2: max(0, litres * 2.3 - kwh * 0.57))
}

func weekStart(_ d: Date = Date()) -> Date {
    var c = Calendar(identifier: .gregorian); c.firstWeekday = 2
    return c.dateInterval(of: .weekOfYear, for: d)?.start ?? d
}

// MARK: - 每日挑战
struct Challenge {
    let id: String, title: String, icon: String
    let done: ([Trip]) -> Bool
}

final class ChallengeStore: ObservableObject {
    static let shared = ChallengeStore()
    @Published private(set) var done: [String: String] = [:]        // 日期 → 挑战 id
    private let file = JSONFile<[String: String]>("challenges.json")
    static let pointsEach = 15
    init() { done = file.load() ?? [:] }

    static let all: [Challenge] = [
        Challenge(id: "km5", title: "今天骑满 5 公里", icon: "road.lanes") { $0.reduce(0) { $0 + $1.km } >= 5 },
        Challenge(id: "score85", title: "骑一趟评分 85 分以上", icon: "star.fill") { $0.contains { ($0.score?.total ?? 0) >= 85 } },
        Challenge(id: "eco25", title: "骑一趟 3 公里以上，每公里不到 25 Wh", icon: "leaf.fill") { $0.contains { $0.km >= 3 && ($0.whPerKm ?? 99) < 25 } },
        Challenge(id: "nospeed", title: "骑一趟 3 公里以上，全程不超过 35 km/h", icon: "tortoise.fill") { $0.contains { $0.km >= 3 && $0.maxKmh <= 35 } },
        Challenge(id: "two", title: "今天骑两趟", icon: "2.circle.fill") { $0.count >= 2 },
        Challenge(id: "climb20", title: "今天累计爬升 20 米", icon: "mountain.2.fill") { $0.reduce(0) { $0 + ($1.climbM ?? 0) } >= 20 },
        Challenge(id: "smooth", title: "骑一趟 2 公里以上，一次都不猛起步", icon: "hand.thumbsup.fill") { $0.contains { $0.km >= 2 && $0.score?.hardStarts == 0 } },
    ]

    private static func key(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    var today: Challenge {
        let n = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return ChallengeStore.all[n % ChallengeStore.all.count]
    }
    var doneToday: Bool { done[ChallengeStore.key(Date())] != nil }
    var points: Int { done.count * ChallengeStore.pointsEach }
    var streak: Int {
        var s = 0, d = Date()
        if done[ChallengeStore.key(d)] == nil { d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        while done[ChallengeStore.key(d)] != nil { s += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d)! }
        return s
    }

    /// 骑完一趟检查；完成了返回挑战
    func check(_ trips: [Trip]) -> Challenge? {
        guard !doneToday else { return nil }
        let todays = trips.filter { Calendar.current.isDateInToday($0.start) }
        let c = today
        guard c.done(todays) else { return nil }
        done[ChallengeStore.key(Date())] = c.id
        file.save(done)
        return c
    }
}

// MARK: - 保养提醒
struct MaintItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var icon: String
    var everyKm: Double?
    var everyDays: Double?
    var lastKm: Double
    var lastDate: Date
    var notified = false
}

final class MaintStore: ObservableObject {
    @Published var items: [MaintItem] = []
    @Published var odoBase: Double { didSet { UserDefaults.standard.set(odoBase, forKey: "odo.base") } }
    private let file = JSONFile<[MaintItem]>("maint.json")

    init() {
        odoBase = UserDefaults.standard.double(forKey: "odo.base")
        if let s = file.load() { items = s } else {
            let now = Date()
            items = [
                MaintItem(name: "检查胎压", icon: "circle.circle", everyKm: nil, everyDays: 30, lastKm: 0, lastDate: now),
                MaintItem(name: "检查刹车", icon: "exclamationmark.octagon", everyKm: 1000, everyDays: 60, lastKm: 0, lastDate: now),
                MaintItem(name: "换齿轮油", icon: "drop.fill", everyKm: 3000, everyDays: 365, lastKm: 0, lastDate: now),
                MaintItem(name: "换刹车片", icon: "circle.dashed", everyKm: 3000, everyDays: nil, lastKm: 0, lastDate: now),
                MaintItem(name: "检查电池接线柱", icon: "bolt.horizontal", everyKm: nil, everyDays: 90, lastKm: 0, lastDate: now),
            ]
            save()
        }
    }

    func save() { file.save(items) }
    func odo(_ trips: [Trip]) -> Double { odoBase + trips.reduce(0) { $0 + $1.km } }

    /// 还剩多少：返回（到期了吗，说明）
    func status(_ i: MaintItem, odo: Double) -> (Bool, String, Double) {
        var parts: [String] = [], due = false, frac = 0.0
        if let k = i.everyKm {
            let left = k - (odo - i.lastKm)
            due = due || left <= 0; frac = max(frac, (odo - i.lastKm) / k)
            parts.append(left > 0 ? String(format: "还有 %.0f 公里", left) : String(format: "超了 %.0f 公里", -left))
        }
        if let dd = i.everyDays {
            let left = dd - Date().timeIntervalSince(i.lastDate) / 86400
            due = due || left <= 0; frac = max(frac, (dd - left) / dd)
            parts.append(left > 0 ? String(format: "还有 %.0f 天", left) : String(format: "超了 %.0f 天", -left))
        }
        return (due, parts.joined(separator: "，"), min(max(frac, 0), 1))
    }

    func done(_ id: UUID, odo: Double) {
        guard let k = items.firstIndex(where: { $0.id == id }) else { return }
        items[k].lastKm = odo; items[k].lastDate = Date(); items[k].notified = false
        save()
        LogStore.shared.log("保养：" + items[k].name + " 已完成")
    }

    func checkDue(odo: Double) {
        var changed = false
        for k in items.indices where !items[k].notified {
            let s = status(items[k], odo: odo)
            if s.0 { items[k].notified = true; changed = true; Notifier.shared.postNow("该" + items[k].name + "了", s.1) }
        }
        if changed { save() }
    }
}

// MARK: - 常去地点
struct FavPlace: Codable, Identifiable {
    var id = UUID()
    var name: String
    var lat: Double          // 地图自己的坐标
    var lon: Double
    var item: MKMapItem {
        let i = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        i.name = name
        return i
    }
}

final class FavStore: ObservableObject {
    @Published private(set) var places: [FavPlace] = []
    private let file = JSONFile<[FavPlace]>("favorites.json")
    init() { places = file.load() ?? [] }
    func add(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        guard !places.contains(where: { abs($0.lat - c.latitude) < 1e-5 && abs($0.lon - c.longitude) < 1e-5 }) else { return }
        places.insert(FavPlace(name: item.name ?? "收藏的地点", lat: c.latitude, lon: c.longitude), at: 0)
        file.save(places)
    }
    func has(_ item: MKMapItem) -> Bool {
        let c = item.placemark.coordinate
        return places.contains { abs($0.lat - c.latitude) < 1e-5 && abs($0.lon - c.longitude) < 1e-5 }
    }
    func delete(at o: IndexSet) { places.remove(atOffsets: o); file.save(places) }
}

// MARK: - 声浪模拟：按车速和功率合成一个类似发动机的声音
final class EngineSound {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode!
    private var phase = 0.0
    private var freq = 40.0, amp = 0.0
    private(set) var running = false

    init() {
        let sr = 44100.0
        node = AVAudioSourceNode { [unowned self] _, _, frameCount, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frameCount) {
                self.phase += self.freq / sr
                if self.phase >= 1 { self.phase -= 1 }
                let saw = 2 * self.phase - 1
                let pulse = self.phase < 0.25 ? 1.0 : -0.35
                let s = Float((saw * 0.45 + pulse * 0.45 + Double.random(in: -0.12...0.12)) * self.amp)
                for b in bufs { b.mData?.assumingMemoryBound(to: Float.self)[f] = s }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1))
    }

    func start() {
        guard !running else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        do { try engine.start(); running = true; Speaker.shared.hold = true } catch { LogStore.shared.log("声浪打不开：\(error.localizedDescription)") }
    }

    func stop() {
        guard running else { return }
        engine.stop(); running = false; Speaker.shared.hold = false
    }

    func update(speed: Double, power: Double) {
        freq = 32 + speed * 3.0 + max(power, 0) / 70
        amp = running ? min(0.32, 0.04 + max(power, 0) / 2500 * 0.28 + speed / 60 * 0.05) : 0
    }
}
