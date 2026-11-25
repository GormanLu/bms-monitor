import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var ride: RideTracker

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ScrollView {
                    VStack(spacing: 12) {
                        connectionCard
                        socCard
                        if m.live.count >= 2 { blocksCard }
                        numbersCard
                        rideCard
                        uploadCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("电池监控")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("设置") { SettingsView() }
                }
            }
            .sheet(isPresented: $ble.scanning) { DevicePicker() }
        }
    }

    // MARK: 连接
    private var connectionCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ble.status).font(.headline)
                    Text(dataAgeText).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if ble.connected || ble.status.hasPrefix("正在") || ble.status.hasPrefix("断开了") {
                    Button("断开") { ble.disconnect() }.buttonStyle(.bordered)
                } else {
                    Button("连接电池") { ble.connect() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var dataAgeText: String {
        guard let t = m.lastDataAt else { return ble.deviceTail.isEmpty ? "第一次用：点\"连接电池\"，选名称结尾 01 的那一块" : "电池：名称结尾 \(ble.deviceTail)" }
        let s = Int(Date().timeIntervalSince(t))
        return s <= 8 ? "数据时间 " + t.formatted(date: .omitted, time: .standard) : "已经 \(s) 秒没有新数据"
    }

    // MARK: 电量
    private var socCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.lowest.map { String(format: "%.1f%%", $0.soc) } ?? "--")
                        .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                    if let lo = m.lowest, m.live.count > 1 {
                        Text("按最低的一块 · 模块 \(lo.name)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(max((m.lowest?.soc ?? 0) / 100, 0), 1))
                    .tint((m.lowest?.soc ?? 100) <= 15 ? .red : (m.lowest?.soc ?? 100) <= 30 ? .orange : .green)
                if let s = m.summary {
                    Text(String(format: "保护板汇总电量 %.1f%%", s.soc)).font(.footnote).foregroundStyle(.secondary)
                }
                let shut = m.live.filter(\.chargeShut)
                if !shut.isEmpty {
                    Text("模块 " + shut.map(\.name).joined(separator: "、") + " 的保护板把充电关着（充满后的保护），骑掉一点电会自动打开。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: 各块
    private var blocksCard: some View {
        let rows = m.live
        let minSoc = rows.map(\.soc).min()
        return Card {
            Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(rows, id: \.id) { Text($0.name).font(.caption).foregroundStyle(.secondary) }
                }
                GridRow {
                    Text("电量").font(.caption).foregroundStyle(.secondary)
                    ForEach(rows, id: \.id) { b in
                        Text(b.soc.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f%%", b.soc) : String(format: "%.1f%%", b.soc))
                            .foregroundStyle(b.soc == minSoc && rows.count > 1 ? .orange : .primary)
                    }
                }
                GridRow {
                    Text("压差").font(.caption).foregroundStyle(.secondary)
                    ForEach(rows, id: \.id) { Text("\($0.gapMv)") }
                }
                GridRow {
                    Text("温度").font(.caption).foregroundStyle(.secondary)
                    ForEach(rows, id: \.id) { b in
                        Text(b.temps[0] == b.temps[1] ? "\(b.temps[0])°" : "\(min(b.temps[0], b.temps[1]))/\(max(b.temps[0], b.temps[1]))°")
                    }
                }
                if rows.contains(where: { $0.current > 0.5 }) {
                    GridRow {
                        Text("电流").font(.caption).foregroundStyle(.secondary)
                        ForEach(rows, id: \.id) { Text(abs($0.current) < 0.2 ? "0" : String(format: "%.1f", $0.current)) }
                    }
                    GridRow {
                        Text("最高").font(.caption).foregroundStyle(.secondary)
                        ForEach(rows, id: \.id) { Text(String(format: "%.3f", $0.cells.max() ?? 0)) }
                    }
                }
            }
            .font(.subheadline.monospacedDigit())
            Text("压差是每块自己 4 节之间的差（mV）。橙色是电量最低的一块。").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 电流、功率
    private var numbersCard: some View {
        Card {
            HStack {
                Stat(label: (m.power ?? 0) < 0 ? "充电（瓦）" : "功率（瓦）", value: m.power.map { String(format: "%.0f", abs($0)) } ?? "--")
                Stat(label: "电流", value: m.current.map { String(format: "%.1f A", abs($0) < 0.6 ? 0 : abs($0)) } ?? "--")
                Stat(label: "总电压", value: m.totalV.map { String(format: "%.1f V", $0) } ?? "--")
            }
            if let t = m.tempRange {
                Text("温度 \(t.0)～\(t.1) °C").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 骑行
    private var rideCard: some View {
        Card {
            HStack {
                Stat(label: "车速（公里/小时）", value: speedText)
                Stat(label: "里程", value: ride.on || ride.distM > 0 ? String(format: "%.2f km", ride.distM / 1000) : "--")
                Stat(label: "最高", value: ride.vMaxKmh > 0 ? String(format: "%.0f", ride.vMaxKmh) : "--")
            }
            Button(ride.on ? "结束骑行" : "开始骑行") { m.toggleRide() }
                .buttonStyle(.borderedProminent)
                .tint(ride.on ? .red : .blue)
                .frame(maxWidth: .infinity)
            Text(ride.note.isEmpty ? "开始骑行后，切到导航、锁屏都会继续记录车速和里程。位置只留在手机上，不会上传。" : ride.note)
                .font(.caption2).foregroundStyle(ride.note.isEmpty ? Color.secondary : Color.orange)
        }
    }

    private var speedText: String {
        guard ride.on, let v = ride.speedKmh, let t = ride.speedAt, Date().timeIntervalSince(t) < 5 else { return "--" }
        return String(format: "%.0f", v)
    }

    // MARK: 上传
    private var uploadCard: some View {
        Card {
            Button(m.uploading ? "正在上传…" : "上传日志给 Claude") { m.upload() }
                .buttonStyle(.bordered)
                .disabled(m.uploading)
                .frame(maxWidth: .infinity)
            Text(m.storedBytes > 0 ? String(format: "手机上存着 %.1f MB 还没上传的日志，传成功后自动删掉。", Double(m.storedBytes) / 1_000_000) : "手机上没有没上传的日志。")
                .font(.caption2).foregroundStyle(.secondary)
            if !m.uploadMsg.isEmpty { Text(m.uploadMsg).font(.footnote) }
        }
    }
}

// MARK: 选择电池
struct DevicePicker: View {
    @EnvironmentObject var ble: BLEManager
    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("选名称结尾是 01 的那一块，它是主模块，能看到全部 20 节。")) {
                    if ble.found.isEmpty { Text("正在搜索，请在电池旁边…").foregroundStyle(.secondary) }
                    ForEach(ble.found) { d in
                        Button { ble.choose(d) } label: {
                            HStack { Text(d.name); Spacer(); Text("\(d.rssi)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("选择电池")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { ble.stopScan() } } }
        }
    }
}

// MARK: 设置
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ble: BLEManager
    @State private var token = ""
    @State private var hasToken = Keychain.load() != nil
    @State private var lines: [String] = []

    var body: some View {
        Form {
            Section(header: Text("上传密钥"), footer: Text("把 github_pat_ 开头的密钥粘进来保存。它只存在这台手机的钥匙串里，日志只会传到你自己的私有仓库。")) {
                SecureField("在这里粘贴密钥", text: $token)
                Button("保存密钥") {
                    Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                    token = ""
                    hasToken = Keychain.load() != nil
                }
                Text(hasToken ? "密钥已保存。" : "还没有保存密钥。").foregroundStyle(.secondary)
                Toggle("结束骑行后自动上传", isOn: $m.autoUpload)
            }
            Section(header: Text("电池")) {
                Text(ble.deviceTail.isEmpty ? "还没有选电池" : "已选：名称结尾 \(ble.deviceTail)")
                Button("换一块电池（重新选择）", role: .destructive) { ble.forget(); ble.connect() }
            }
            Section(header: Text("最近的日志")) {
                ScrollView {
                    Text(lines.suffix(80).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 240)
            }
            Section { Text("\(Uploader.appVersion)").foregroundStyle(.secondary) }
        }
        .navigationTitle("设置")
        .task { lines = await LogStore.shared.recent() }
    }
}

// MARK: 小组件
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
