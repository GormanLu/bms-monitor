import Foundation
import WatchConnectivity

// 手机这边和手表通信：骑行时每秒推一次，平时只在数据变了时更新
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()
    var onCommand: ((String) -> Void)?
    private var lastSent = Date.distantPast
    private var lastContext = Date.distantPast
    private var last: WatchState?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ s: WatchState, live: Bool) {
        guard WCSession.isSupported() else { return }
        let w = WCSession.default
        guard w.activationState == .activated, w.isPaired, w.isWatchAppInstalled else { return }
        let now = Date()
        if w.isReachable {
            guard now.timeIntervalSince(lastSent) >= (live ? 0.9 : 5) else { return }
            lastSent = now
            w.sendMessage(s.dict, replyHandler: nil, errorHandler: nil)
        }
        // 手表 app 没开时，留一份最新的给它打开时看（不要太频繁）
        if now.timeIntervalSince(lastContext) >= 30 || last?.rideOn != s.rideOn || last?.charging != s.charging {
            lastContext = now
            try? w.updateApplicationContext(s.dict)
        }
        last = s
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if session.isPaired { LogStore.shared.log("手表：" + (session.isWatchAppInstalled ? "已装手表 app" : "已配对，还没装手表 app")) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let c = message["cmd"] as? String { DispatchQueue.main.async { self.onCommand?(c) } }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let c = message["cmd"] as? String { DispatchQueue.main.async { self.onCommand?(c) } }
        replyHandler([:])
    }
}
