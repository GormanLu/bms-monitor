import Foundation
import ActivityKit

// 锁屏和灵动岛上显示的内容（app 和小组件扩展共用这个定义）
struct RideAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speed: Int          // 公里/小时，-1 表示暂时没有车速
        var soc: Double         // 最低一块的电量 %
        var power: Int          // 瓦，放电为正
        var distKm: Double      // 这一趟的里程
        var rangeKm: Int        // 估算还能跑多远，-1 表示还算不出来
        var charging: Bool
        var current: Double = 0         // 安，放电为正
        var voltage: Double = 0         // 总电压
        var tempMax: Int = -99          // 最高温度 °C
        var avgKmh: Int = -1            // 平均车速（不算停车）
        var maxKmh: Int = 0             // 这一趟最高车速
        var tripWh: Int = 0             // 这一趟用电
        var whPerKm: Int = -1           // 这一趟每公里耗电
        var blockNames: [String] = []   // 各块名字 A B C D P
        var blockSocs: [Int] = []       // 各块电量
        var lowIndex: Int = -1          // 电量最低的是第几块
        var left: String = "speed"      // 收起时左边显示什么
        var right: String = "soc"       // 收起时右边显示什么
    }
    var startedAt: Date
}

/// 收起时左右两边可以选的内容
enum IslandItem: String, CaseIterable, Identifiable {
    case speed, soc, power, range, dist, current, temp, wh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .speed: return "车速"
        case .soc: return "电量"
        case .power: return "功率"
        case .range: return "续航"
        case .dist: return "里程"
        case .current: return "电流"
        case .temp: return "温度"
        case .wh: return "每公里耗电"
        }
    }
}
