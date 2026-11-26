import Foundation

// 一趟骑行的记录：每 2 秒记一个点（车速、功率、电量），结束时算好汇总。只存在手机里。
struct TripSample: Codable {
    var t: Double      // 从出发开始的秒数
    var v: Double      // 车速 km/h
    var p: Double      // 电池输出功率 W（回充为负）
    var soc: Double    // 最低一块的电量 %
    var a: Double? = nil       // 相对出发点的高度（米，气压计）
    var bv: [Double]? = nil    // 各块平均每节电压
}

/// 轨迹点：经纬度是手机定位给的原始坐标（WGS-84），只存在手机里
struct TrackPoint: Codable {
    var lat: Double
    var lon: Double
    var t: Double      // 从出发开始的秒数
    var v: Double      // 车速 km/h
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var distM: Double
    var movingS: Double
    var maxKmh: Double
    var energyWh: Double
    var maxPowerW: Double
    var socStart: Double
    var socEnd: Double
    var samples: [TripSample]
    var track: [TrackPoint]? = nil
    var climbM: Double? = nil
    var descentM: Double? = nil
    var score: DriveScore? = nil
    var blockNames: [String]? = nil
    var ana: RideAnalysis? = nil    // 电池分析（第 10 版起）
    var tag: String? = nil          // 用户写的控制器参数

    var km: Double { distM / 1000 }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var avgMovingKmh: Double? { movingS > 10 ? distM / movingS * 3.6 : nil }
    var whPerKm: Double? { km >= 0.5 && energyWh > 1 ? energyWh / km : nil }
}

final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    @Published var price: Double = UserDefaults.standard.object(forKey: "price") as? Double ?? 0.6 {
        didSet { UserDefaults.standard.set(price, forKey: "price") }
    }
    private let url: URL

    init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("trips.json")
        if let d = try? Data(contentsOf: url), let t = try? JSONDecoder().decode([Trip].self, from: d) { trips = t }
    }

    func add(_ t: Trip) {
        trips.insert(t, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        save()
    }

    func setTag(_ id: UUID, _ s: String) {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        trips[i].tag = v.isEmpty ? nil : v
        save()
    }

    func delete(_ t: Trip) {
        trips.removeAll { $0.id == t.id }
        save()
    }

    private func save() {
        let snapshot = trips, u = url
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: u, options: .atomic) }
        }
    }

    // MARK: 统计
    var totalKm: Double { trips.reduce(0) { $0 + $1.km } }
    var totalWh: Double { trips.reduce(0) { $0 + $1.energyWh } }
    /// 电费：充电器和充电损耗按 85% 效率算
    var totalCost: Double { totalWh / 1000 / 0.85 * price }
    var maxSpeed: Trip? { trips.max { $0.maxKmh < $1.maxKmh } }
    var longest: Trip? { trips.max { $0.distM < $1.distM } }
    var mostEfficient: Trip? {
        trips.filter { $0.km >= 2 && $0.whPerKm != nil }.min { ($0.whPerKm ?? 0) < ($1.whPerKm ?? 0) }
    }
    /// 最近几趟（至少 1 公里）的平均每公里耗电，用来估算续航
    var recentWhPerKm: Double? {
        let r = trips.filter { $0.km >= 1 && $0.energyWh > 5 }.prefix(5)
        let km = r.reduce(0) { $0 + $1.km }, wh = r.reduce(0) { $0 + $1.energyWh }
        return km >= 3 ? wh / km : nil
    }
}
