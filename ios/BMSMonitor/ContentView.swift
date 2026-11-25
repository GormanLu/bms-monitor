import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        TabView(selection: $m.tab) {
            HomeView().tabItem { Label("电池", systemImage: "battery.100.bolt") }.tag(0)
            RideView().tabItem { Label("仪表盘", systemImage: "speedometer") }.tag(1)
            TripsView().tabItem { Label("记录", systemImage: "list.bullet.rectangle") }.tag(2)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
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
                            HStack {
                                Image(systemName: "battery.100").foregroundStyle(Theme.accent)
                                Text(d.name)
                                Spacer()
                                Text("信号 \(d.rssi)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择电池")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { ble.stopScan() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: 设置
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var trips: TripStore
    @State private var token = ""
    @State private var hasToken = Keychain.load() != nil
    @State private var lines: [String] = []
    @AppStorage("notify.low") private var notifyLow = true
    @AppStorage("notify.charge") private var notifyCharge = true
    @AppStorage("notify.temp") private var notifyTemp = true
    @AppStorage("map.gcj") private var mapGcj = true
    @AppStorage("island.left") private var islandLeft = "speed"
    @AppStorage("island.right") private var islandRight = "soc"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("电池")) {
                    Text(ble.deviceTail.isEmpty ? "还没有选电池" : "已选：名称结尾 \(ble.deviceTail)")
                    Button("换一块电池（重新选择）", role: .destructive) { ble.forget(); ble.connect() }
                }
                Section(header: Text("提醒"), footer: Text("提醒只在这台手机上弹，不联网。")) {
                    Toggle("充满时提醒", isOn: $notifyCharge)
                    Toggle("电量低于 20% 和 10% 时提醒", isOn: $notifyLow)
                    Toggle("电池温度到 50 °C 时提醒", isOn: $notifyTemp)
                }
                Section(header: Text("灵动岛"), footer: Text("灵动岛收起时左右两边各显示一个数，在这里选。长按灵动岛展开、或者看锁屏，能看到全部：车速、电量、续航、功率、电流、里程、用时、平均车速、温度、五块电池的电量。")) {
                    Picker("左边", selection: $islandLeft) {
                        ForEach(IslandItem.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("右边", selection: $islandRight) {
                        ForEach(IslandItem.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section(header: Text("轨迹"), footer: Text("国内地图的坐标和手机定位的坐标不一样，画轨迹前要换算。要是轨迹和道路明显错开几百米，关掉这个试试。轨迹只存在这台手机里，不会上传。")) {
                    Toggle("轨迹偏移校正", isOn: $mapGcj)
                }
                Section(header: Text("电费")) {
                    Stepper(String(format: "电价 %.2f 元/度", trips.price), value: $trips.price, in: 0.1...3, step: 0.05)
                }
                Section(header: Text("上传日志"), footer: Text("把 github_pat_ 开头的密钥粘进来保存。它只存在这台手机的钥匙串里，日志只会传到你自己的私有仓库。")) {
                    SecureField("在这里粘贴密钥", text: $token)
                    Button("保存密钥") {
                        Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""
                        hasToken = Keychain.load() != nil
                    }
                    Text(hasToken ? "密钥已保存。" : "还没有保存密钥。").foregroundStyle(.secondary)
                    Toggle("结束骑行后自动上传", isOn: $m.autoUpload)
                }
                Section(header: Text("最近的日志")) {
                    ScrollView {
                        Text(lines.suffix(80).joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
                Section { Text(Uploader.appVersion).foregroundStyle(.secondary) }
            }
            .navigationTitle("设置")
            .task { lines = await LogStore.shared.recent() }
        }
    }
}
