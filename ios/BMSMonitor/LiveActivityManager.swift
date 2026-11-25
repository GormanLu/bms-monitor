import Foundation
import ActivityKit

// 锁屏和灵动岛：骑行开始时打开，每 2 秒有变化就更新一次，结束骑行时关掉
final class LiveActivityManager {
    private var activity: Activity<RideAttributes>?
    private var lastState: RideAttributes.ContentState?
    private var lastPush = Date.distantPast

    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ state: RideAttributes.ContentState) {
        guard enabled, activity == nil else { return }
        do {
            activity = try Activity.request(attributes: RideAttributes(startedAt: Date()),
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
            lastState = state
            LogStore.shared.log("锁屏和灵动岛已打开")
        } catch {
            LogStore.shared.log("锁屏和灵动岛打不开：\(error.localizedDescription)")
        }
    }

    func update(_ state: RideAttributes.ContentState) {
        guard let a = activity else { return }
        let now = Date()
        guard state != lastState, now.timeIntervalSince(lastPush) >= 2 else { return }
        lastState = state
        lastPush = now
        Task { await a.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(60))) }
    }

    func end(_ state: RideAttributes.ContentState?) {
        guard let a = activity else { return }
        activity = nil
        lastState = nil
        Task {
            await a.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: .after(Date().addingTimeInterval(300)))
        }
    }
}
