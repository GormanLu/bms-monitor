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
    }
    var startedAt: Date
}
