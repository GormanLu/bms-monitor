import Foundation

// app 和小组件共用的一小份数据（放在 App Group 里，只在这台手机上）
struct WidgetSnap: Codable {
    var t: Date
    var soc: Double              // 最低一块的电量
    var range: Int               // 估算续航 km，-1 = 不知道
    var charging: Bool
    var eta: String?             // 预计几点充满
    var weekKm: Double
    var goalKm: Double
    var todayKm: Double
    var gapMv: Int
    var tempMax: Int
    var names: [String]
    var socs: [Int]
    var parkedAt: Date?
}

enum WidgetShare {
    static let group = "group.com.gormanlu.bmsmonitor"
    static let key = "widget.snap"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    static func save(_ s: WidgetSnap) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        defaults?.set(d, forKey: key)
    }

    static func load() -> WidgetSnap? {
        guard let d = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnap.self, from: d)
    }
}
