import SwiftUI
import UIKit

@main
struct BMSMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.ble)
                .environmentObject(model.ride)
                .environmentObject(model.trips)
                .environmentObject(model.nav)
                .environmentObject(model.charges)
                .environmentObject(model.health)
                .environmentObject(model.badges)
                .environmentObject(model.stats)
                .environmentObject(model.snaps)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 系统在后台把 app 唤醒（蓝牙状态恢复）时没有界面，也要把蓝牙管理器建起来接着收数据
        if launchOptions?[.bluetoothCentrals] != nil { LogStore.shared.log("系统在后台唤醒了 app（蓝牙）") }
        _ = AppModel.shared
        return true
    }
}
