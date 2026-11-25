import Foundation
import Security

// 上传密钥存在手机的钥匙串里，只有这个 app 能读。密钥由你自己在设置里粘贴。
enum Keychain {
    private static let service = "bms-upload-token"

    static func save(_ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// 上传到自己的 GitHub 私有仓库，格式和网页版一样；一份不超过约 800 KB，多了就分几份。
enum Uploader {
    static let repo = "GormanLu/bms-logs"
    static let appVersion = "App 第 7 版"
    private static let limit = 800_000

    static func upload(tail: String = "") async -> String {
        guard let token = Keychain.load(), !token.isEmpty else { return "还没有保存上传密钥：点右上角\"设置\"，把密钥粘进去。" }
        let files = await LogStore.shared.filesForUpload()
        if files.isEmpty { return "手机上没有要上传的日志。" }

        // 读出全部，按行切成不超过 800 KB 的几份
        var chunks: [String] = []
        var cur = "", size = 0
        for f in files {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            text.enumerateLines { line, _ in
                let n = line.utf8.count + 1
                if size + n > limit && !cur.isEmpty { chunks.append(cur); cur = ""; size = 0 }
                cur += line + "\n"
                size += n
            }
        }
        if !cur.isEmpty { chunks.append(cur) }
        if chunks.isEmpty { await LogStore.shared.remove(files); return "手机上没有要上传的日志。" }

        let now = Date()
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        let base = df.string(from: now) + "_app"
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = df.string(from: now)

        var sent = 0
        for (i, c) in chunks.enumerated() {
            let multi = chunks.count > 1
            let name = base + (multi ? "_\(i + 1)of\(chunks.count)" : "") + ".txt"
            let body = "页面版本：\(appVersion)\n上传时间：\(stamp)\n\n=== 调试日志" + (multi ? "（第 \(i + 1) 份，共 \(chunks.count) 份）" : "") + " ===\n" + c + (i == chunks.count - 1 && !tail.isEmpty ? "\n" + tail + "\n" : "")
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/contents/logs/\(name)")!)
            req.httpMethod = "PUT"
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["message": "上传日志 " + name, "content": Data(body.utf8).base64EncodedString()])
            req.timeoutInterval = 60
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code != 200 && code != 201 {
                    let why = code == 401 ? "密钥不对或者已经过期，请在设置里重新粘贴。"
                        : (code == 403 || code == 404) ? "这个密钥没有日志仓库的写入权限（\(code)）。"
                        : "GitHub 返回了 \(code)。"
                    return "上传失败：" + why + "手机上的日志都还留着，下次会再传。"
                }
                sent += 1
            } catch {
                return "上传失败：连不上 GitHub（\(error.localizedDescription)）。手机上的日志都还留着，下次会再传。"
            }
        }
        await LogStore.shared.remove(files)          // 全部传成功了，才从手机上删掉
        LogStore.shared.log("日志已上传：\(base)（\(sent) 份）")
        return "已上传" + (sent > 1 ? " \(sent) 份" : "") + "：\(base)。跟 Claude 说一声\"传了\"就行。"
    }
}
