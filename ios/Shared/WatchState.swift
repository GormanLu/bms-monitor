import Foundation

// 手机发给手表的数据（手机和手表 app 共用这个定义）
struct WatchState: Codable, Equatable {
    var t = Date()
    var speed = -1              // km/h，-1 = 没有车速
    var soc = 0.0               // 最低一块的电量
    var range = -1              // 续航 km
    var power = 0               // W，回充为负
    var current = 0.0           // A
    var rideOn = false
    var distKm = 0.0
    var elapsed = 0.0           // 这一趟用了多少秒
    var avg = -1
    var maxKmh = 0
    var tripWh = 0
    var whKm = -1
    var temp = -99
    var gap = 0                 // 整组压差 mV
    var names: [String] = []
    var socs: [Int] = []
    var lowIndex = -1
    var charging = false
    var eta: String?
    var connected = false       // 手机连着电池吗
    var navText = ""
    var navDist = -1            // 离下一个路口多少米
    var navLeft = -1            // 离终点多少米
    var limit = -1              // 超速提醒的车速，-1 = 关
    var climb = 0               // 这一趟爬升 m

    static func decode(_ d: [String: Any]) -> WatchState? {
        guard let data = d["s"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchState.self, from: data)
    }
    var dict: [String: Any] { ["s": (try? JSONEncoder().encode(self)) ?? Data()] }
}
