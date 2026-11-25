import Foundation
import CoreLocation
import UIKit

// 骑行模式：用手机定位算车速和里程，切到导航、锁屏时照样算（屏幕顶上会有定位的蓝色提示）。
// 位置和轨迹只存在手机上（骑行记录里），日志里只记信号好不好、车速和里程这些统计数字，不会上传位置。
// 算法和网页一样：车速用系统直接给的；里程离上一个记录点超过 15 米（或定位误差）才累加，避免把飘动算成路程。
final class RideTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var on = false
    @Published var speedKmh: Double?
    @Published var speedAt: Date?
    @Published var distM: Double = 0
    @Published var vMaxKmh: Double = 0
    @Published var note = ""
    @Published private(set) var startedAt: Date?
    @Published private(set) var movingS: Double = 0
    /// 这一趟的轨迹：离上一个点超过 5 米记一个点（只存在手机里）
    private(set) var track: [TrackPoint] = []

    private let lm = CLLocationManager()
    private var anchor: CLLocation?
    private var prev: CLLocation?
    private var prevSpeed: Double?
    private var firstT: Date?
    private var lastT: Date?

    private struct Stat {
        var t0 = Date(); var n = 0; var bad = 0; var bg = 0
        var accMin = 999.0, accMax = 0.0
        var nat = 0; var natSum = 0.0
        var dist = 0.0; var byNat = 0.0
    }
    private var st = Stat()

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.activityType = .otherNavigation
        lm.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        anchor = nil; prev = nil; prevSpeed = nil; track = []
        distM = 0; vMaxKmh = 0; movingS = 0; firstT = nil; lastT = nil; startedAt = Date()
        speedKmh = nil; speedAt = nil
        st = Stat()
        on = true
        note = ""
        lm.startUpdatingLocation()
        LogStore.shared.log("进入骑行模式")
    }

    func stop() {
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        flush()
        if let a = firstT, let b = lastT, distM >= 100 {
            let total = b.timeIntervalSince(a)
            let avg = total > 0 ? distM / total * 3.6 : 0
            let moveAvg = movingS > 10 ? distM / movingS * 3.6 : 0
            LogStore.shared.log(String(format: "本次骑行：里程 %.2f km，用时 %.0f 分钟，平均车速 %.1f km/h（不算停车 %.1f），最高车速 %.1f km/h",
                                       distM / 1000, total / 60, avg, moveAvg, vMaxKmh))
        }
        LogStore.shared.log("退出骑行模式")
        on = false
        speedKmh = nil
        startedAt = nil
    }

    /// 现在的车速，超过 5 秒没有新定位就当作不知道
    var freshSpeed: Double? {
        guard on, let v = speedKmh, let t = speedAt, Date().timeIntervalSince(t) < 5 else { return nil }
        return v
    }

    private func handle(_ l: CLLocation) {
        let now = Date()
        if l.horizontalAccuracy < 0 || l.horizontalAccuracy > 40 { st.bad += 1; return }   // 太飘的点不要
        if UIApplication.shared.applicationState == .background { st.bg += 1 }
        st.n += 1
        st.accMin = min(st.accMin, l.horizontalAccuracy)
        st.accMax = max(st.accMax, l.horizontalAccuracy)
        let nat: Double? = l.speed >= 0 ? l.speed : nil
        let gap = prev.map { l.timestamp.timeIntervalSince($0.timestamp) } ?? 0
        if let nat {
            st.nat += 1; st.natSum += nat
            if let p = prev, p.speed >= 0, gap > 0, gap <= 3 {
                st.byNat += ((nat < 0.5 ? 0 : nat) + (p.speed < 0.5 ? 0 : p.speed)) / 2 * gap
            }
        }
        if let a = anchor {
            let d = l.distance(from: a), dt = l.timestamp.timeIntervalSince(a.timestamp)
            if d >= max(15, l.horizontalAccuracy) && dt > 0 && d / dt < 30 {
                distM += d; st.dist += d; anchor = l
            }
        } else { anchor = l }
        if let nat {
            let s = nat < 0.5 ? 0 : nat
            speedKmh = s * 3.6
            speedAt = now
            if let ps = prevSpeed { vMaxKmh = max(vMaxKmh, min(s, ps) * 3.6) }   // 连续两次都达到才算最高车速
            if s > 0.56 && gap > 0 && gap <= 3 { movingS += gap }
            prevSpeed = s
        }
        prev = l
        if let s = startedAt, track.last.map({ CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: l) >= 5 }) ?? true {
            track.append(TrackPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                                    t: l.timestamp.timeIntervalSince(s), v: (nat ?? 0) * 3.6))
        }
        if firstT == nil { firstT = l.timestamp }
        lastT = l.timestamp
        if now.timeIntervalSince(st.t0) >= 60 { flush() }
    }

    // 每分钟记一行定位统计（不含位置），格式和网页一样
    private func flush() {
        let secs = Int(Date().timeIntervalSince(st.t0).rounded())
        if st.n + st.bad > 0 {
            var s = "定位：\(secs) 秒内收到 \(st.n + st.bad) 次（其中 app 在后台时 \(st.bg) 次，太飘丢掉 \(st.bad) 次）"
            if st.n > 0 { s += String(format: "，精度 %.0f~%.0f 米", st.accMin, st.accMax) }
            if st.nat > 0 { s += String(format: "，系统直接给车速 %d 次（平均 %.1f km/h）", st.nat, st.natSum / Double(st.nat) * 3.6) }
            s += String(format: "；这段路程：按位置算 %.0f 米，按系统车速算 %.0f 米", st.dist, st.byNat)
            LogStore.shared.log(s)
        } else if on {
            LogStore.shared.log("定位：\(secs) 秒内一次都没收到")
        }
        st = Stat()
    }

    // MARK: CLLocationManagerDelegate
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard on else { return }
        locs.forEach(handle)
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .denied, .restricted:
            note = "没有定位权限，车速和里程显示不了。请到系统设置 → 隐私 → 定位服务里允许。"
            LogStore.shared.log("没有定位权限")
        default: note = ""
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        LogStore.shared.log("定位出错：\(error.localizedDescription)")
    }
}
