import Foundation
import UserNotifications

// 本机提醒：充满了、电量低、温度高。不联网，只在这台手机上弹。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    var lowOn: Bool { UserDefaults.standard.object(forKey: "notify.low") as? Bool ?? true }
    var chargeOn: Bool { UserDefaults.standard.object(forKey: "notify.charge") as? Bool ?? true }
    var tempOn: Bool { UserDefaults.standard.object(forKey: "notify.temp") as? Bool ?? true }

    private var lowFired: Set<Int> = []
    private var chargingSince: Date?
    private var lastTempAt = Date.distantPast
    private var lastCheck = Date.distantPast

    func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // app 在前台时也弹出来
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    var onAlert: ((String) -> Void)?

    func badge(_ b: BadgeUnlock) {
        let c = UNMutableNotificationContent()
        c.title = "解锁徽章：" + b.title
        c.body = b.detail
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func post(_ title: String, _ body: String) {
        onAlert?(title + "。" + body)
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        LogStore.shared.log("提醒：" + title + "。" + body)
    }

    /// 每收到一批数据调用一次（内部 5 秒最多检查一次）
    func check(blocks: [BlockData]) {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= 5, blocks.count >= 2 else { return }
        lastCheck = now

        // 电量低：按最低的一块，20% 和 10% 各提醒一次，回升到 3 个点以上再重新计
        if let low = blocks.min(by: { $0.remainAh < $1.remainAh }) {
            for th in [20, 10] {
                if low.soc <= Double(th) && !lowFired.contains(th) {
                    lowFired.insert(th)
                    if lowOn { post("电量剩 \(Int(low.soc))%", th == 10 ? "最低的一块（模块 \(low.name)）快放空了，别再拧到底，尽快充电。" : "按最低的一块（模块 \(low.name)）算，该找地方充电了。") }
                } else if low.soc > Double(th) + 3 {
                    lowFired.remove(th)
                }
            }
        }

        // 充满：充了 10 分钟以上，然后所有块都不进电了，而且有保护板把充电关掉
        let charging = blocks.contains { $0.current > 0.5 } && !blocks.contains { $0.current < -2 }
        if charging {
            if chargingSince == nil { chargingSince = now }
        } else if let since = chargingSince {
            let allStopped = blocks.allSatisfy { abs($0.current) < 0.3 }
            if allStopped {
                if now.timeIntervalSince(since) > 600 && blocks.contains(where: \.chargeShut) && chargeOn {
                    let socs = blocks.map { "\($0.name) \(Int($0.soc))%" }.joined(separator: "，")
                    post("充好了", "保护板已经停止充电。各块：\(socs)。")
                }
                chargingSince = nil
            }
            if blocks.contains(where: { $0.current < -2 }) { chargingSince = nil }
        }

        // 温度高：任何一个测温点到 50 °C，半小时内只提醒一次
        if let t = blocks.flatMap(\.temps).max(), t >= 50, now.timeIntervalSince(lastTempAt) > 1800 {
            lastTempAt = now
            if tempOn { post("电池温度 \(t) °C", "温度偏高，停下来让电池凉一凉。") }
        }
    }
}
