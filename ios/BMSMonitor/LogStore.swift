import Foundation

// 日志：每一行都马上追加写进手机里的文件（Documents/logs/pending.log），切到后台、被系统关掉都不会丢。
// 上传时先把 pending.log 改名成 upload-时间.log，新的日志写进新的 pending.log；
// 上传全部成功才删掉 upload-*.log，失败就留着，下次一起再传。
final class LogStore {
    static let shared = LogStore()

    private let queue = DispatchQueue(label: "bms.log")
    private let dir: URL
    private var pendingURL: URL { dir.appendingPathComponent("pending.log") }
    private var handle: FileHandle?
    private var lastDay = ""
    private var lineCount = 0
    private var recentLines: [String] = []
    private let dayFmt = DateFormatter()
    private let timeFmt = DateFormatter()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in [dayFmt, timeFmt] { f.locale = Locale(identifier: "en_US_POSIX") }
        dayFmt.dateFormat = "yyyy-MM-dd"
        timeFmt.dateFormat = "HH:mm:ss"
        lastDay = UserDefaults.standard.string(forKey: "log.lastDay") ?? ""
    }

    func log(_ msg: String) {
        let now = Date()
        queue.async {
            var text = ""
            let day = self.dayFmt.string(from: now)
            if day != self.lastDay {                       // 跨天的地方插一行日期
                text += "—— \(day) ——\n"
                self.lastDay = day
                UserDefaults.standard.set(day, forKey: "log.lastDay")
            }
            let line = self.timeFmt.string(from: now) + " " + msg
            text += line + "\n"
            self.append(text)
            self.recentLines.append(line)
            if self.recentLines.count > 300 { self.recentLines.removeFirst(self.recentLines.count - 300) }
            self.lineCount += 1
            if self.lineCount % 2000 == 0 { self.trimIfHuge() }
        }
    }

    private func append(_ s: String) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: pendingURL.path) {
                FileManager.default.createFile(atPath: pendingURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: pendingURL)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: Data(s.utf8))
    }

    private func fileSize(_ u: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func uploadFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("upload-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // pending.log 太大就先切出去；总共超过 150 MB（大约 180 小时的数据）就删最早的
    private func trimIfHuge() {
        if fileSize(pendingURL) > 40_000_000 { rotate() }
        var files = uploadFiles()
        var total = files.reduce(0) { $0 + fileSize($1) } + fileSize(pendingURL)
        while total > 150_000_000, let f = files.first {
            total -= fileSize(f)
            try? FileManager.default.removeItem(at: f)
            files.removeFirst()
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        if fileSize(pendingURL) > 0 {
            let name = "upload-\(Int(Date().timeIntervalSince1970 * 1000)).log"
            try? FileManager.default.moveItem(at: pendingURL, to: dir.appendingPathComponent(name))
            lastDay = ""                                  // 新文件开头再写一次日期
            UserDefaults.standard.set("", forKey: "log.lastDay")
        }
    }

    /// 把现在的日志切出来，返回所有等着上传的文件
    func filesForUpload() async -> [URL] {
        await withCheckedContinuation { c in
            queue.async {
                self.rotate()
                c.resume(returning: self.uploadFiles())
            }
        }
    }

    func remove(_ files: [URL]) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                files.forEach { try? FileManager.default.removeItem(at: $0) }
                c.resume()
            }
        }
    }

    /// 手机上存着多少字节还没上传
    func storedBytes() async -> Int {
        await withCheckedContinuation { c in
            queue.async { c.resume(returning: self.uploadFiles().reduce(0) { $0 + self.fileSize($1) } + self.fileSize(self.pendingURL)) }
        }
    }

    func recent() async -> [String] {
        await withCheckedContinuation { c in queue.async { c.resume(returning: self.recentLines) } }
    }
}
