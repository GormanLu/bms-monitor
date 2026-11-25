import Foundation
import UIKit

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let ble = BLEManager()
    let ride = RideTracker()
    private let parser = FrameParser()
    private var lastRx: Date?

    @Published var blocks: [UInt8: BlockData] = [:]
    @Published var summary: SummaryData?
    @Published var lastDataAt: Date?
    @Published var uploading = false
    @Published var uploadMsg = ""
    @Published var storedBytes = 0
    @Published var autoUpload: Bool = UserDefaults.standard.object(forKey: "autoUpload") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoUpload, forKey: "autoUpload") }
    }

    private init() {
        LogStore.shared.log("App 启动（\(Uploader.appVersion)）")
        ble.onData = { [weak self] bytes in self?.onBytes(bytes) }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            LogStore.shared.log("App 切到后台")
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            LogStore.shared.log("App 回到前台")
            self?.refreshStored()
        }
        refreshStored()
    }

    private func onBytes(_ bytes: [UInt8]) {
        let now = Date()
        if let l = lastRx, now.timeIntervalSince(l) > 15 {
            LogStore.shared.log("中间有 \(Int(now.timeIntervalSince(l))) 秒没有收到电池数据")
        }
        lastRx = now
        LogStore.shared.log("收 " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        for fr in parser.feed(bytes) {
            switch fr {
            case .block(let b): blocks[b.id] = b
            case .summary(let s): summary = s
            }
            lastDataAt = now
        }
    }

    // MARK: 给界面用的数
    var live: [BlockData] {
        blocks.values.filter { Date().timeIntervalSince($0.at) < 30 }.sorted { $0.id < $1.id }
    }
    /// 剩余容量最低的一块：五块串联，哪一块先放空，整车就断电
    var lowest: BlockData? { live.min { $0.remainAh < $1.remainAh } }
    var current: Double? { live.isEmpty ? nil : live.map(\.current).reduce(0, +) / Double(live.count) }
    var cells: [Double] { live.flatMap(\.cells) }
    var totalV: Double? { cells.isEmpty ? nil : cells.reduce(0, +) }
    var power: Double? {
        guard let i = current, let v = totalV else { return nil }
        return abs(i) < 0.6 ? 0 : -i * v
    }
    var tempRange: (Int, Int)? {
        let t = live.flatMap(\.temps)
        guard let lo = t.min(), let hi = t.max() else { return nil }
        return (lo, hi)
    }

    // MARK: 骑行和上传
    func toggleRide() {
        if ride.on {
            ride.stop()
            if autoUpload && Keychain.load() != nil { upload() }   // 骑完自动传一次
        } else {
            ride.start()
        }
    }

    func upload() {
        guard !uploading else { return }
        uploading = true
        uploadMsg = "正在上传…"
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "upload") { UIApplication.shared.endBackgroundTask(bg) }
        Task {
            let msg = await Uploader.upload()
            let size = await LogStore.shared.storedBytes()
            await MainActor.run {
                self.uploadMsg = msg
                self.uploading = false
                self.storedBytes = size
                UIApplication.shared.endBackgroundTask(bg)
            }
        }
    }

    func refreshStored() {
        Task {
            let size = await LogStore.shared.storedBytes()
            await MainActor.run { self.storedBytes = size }
        }
    }
}
