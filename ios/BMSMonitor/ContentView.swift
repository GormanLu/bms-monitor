import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("theme") private var theme = "blue"

    var body: some View {
        TabView(selection: $m.tab) {
            HomeView().tabItem { Label("电池", systemImage: "battery.100.bolt") }.tag(0)
            RideView().tabItem { Label("仪表盘", systemImage: "speedometer") }.tag(1)
            TripsView().tabItem { Label("记录", systemImage: "list.bullet.rectangle") }.tag(2)
            FeatureHubView().tabItem { Label("功能", systemImage: "square.grid.2x2.fill") }.tag(3)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }
        .id(theme)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { BadgeToast() }
    }
}

struct BadgeToast: View {
    @EnvironmentObject var badges: BadgeStore
    var body: some View {
        if let b = badges.justUnlocked {
            HStack(spacing: 12) {
                Image(systemName: b.icon).font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Tier.color(b.tier)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("解锁徽章：" + b.title).font(.headline)
                    Text(b.detail).font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.solid))
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation { badges.justUnlocked = nil }
            }
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
    @EnvironmentObject var nav: NavManager
    @State private var token = ""
    @State private var hasToken = Keychain.load() != nil
    @State private var lines: [String] = []
    @AppStorage("notify.low") private var notifyLow = true
    @AppStorage("notify.charge") private var notifyCharge = true
    @AppStorage("notify.temp") private var notifyTemp = true
    @AppStorage("map.gcj") private var mapGcj = true
    @AppStorage("island.left") private var islandLeft = "speed"
    @AppStorage("island.right") private var islandRight = "soc"
    @AppStorage("ride.autoStart") private var autoStart = true
    @AppStorage("ride.autoStop") private var autoStop = true
    @AppStorage("speed.alert") private var speedAlert = true
    @AppStorage("speed.limit") private var speedLimit = 30.0
    @AppStorage("watch.tap") private var watchTap = true
    @AppStorage("goal.week") private var goalWeek = 30.0
    @AppStorage("cost.fuel") private var fuel = 7.5
    @AppStorage("cost.l100") private var l100 = 6.0
    @AppStorage("cost.taxi") private var taxi = 2.5

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
                Section(header: Text("骑行"), footer: Text("自动开始：连着电池时，电机持续出力 6 秒就自动开始记录（手动结束后 3 分钟内不会再自动开始）。app 在后台时自动开始，定位权限要选\"始终\"才有车速和里程，否则要等你打开 app 才补上；锁屏和灵动岛也要打开 app 才会出来（系统不让后台打开）。自动结束：车速和电流都停了 5 分钟。")) {
                    HStack {
                        Text("定位权限")
                        Spacer()
                        Text(m.ride.authText).foregroundStyle(m.ride.isAlways ? Theme.good : Theme.warn)
                    }
                    if !m.ride.isAlways {
                        Button("去系统设置改成\"始终\"") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    }
                    Toggle("骑起来自动开始记录", isOn: $autoStart)
                    Toggle("停车 5 分钟自动结束", isOn: $autoStop)
                    Toggle("超速语音提醒", isOn: $speedAlert)
                    if speedAlert { Stepper("超过 \(Int(speedLimit)) km/h 提醒", value: $speedLimit, in: 15...60, step: 1) }
                    Stepper("每周目标 \(Int(goalWeek)) 公里", value: $goalWeek, in: 5...500, step: 5)
                }
                Section(header: Text("Apple Watch"), footer: Text("骑行时，手表的智能叠放里会显示车速、电量、续航和导航（转一下表冠或在表盘上往上滑）。想抬手就看到：在手表的 设置 → 智能叠放 里打开实时活动的\"自动启动\"。转弯和超速提醒是发一条通知，手机锁屏时会转到手表上震一下手腕。")) {
                    Toggle("转弯和超速时震手表", isOn: $watchTap)
                }
                Section(header: Text("仪表主题")) {
                    NavigationLink { ThemePage() } label: {
                        HStack {
                            Text("主题")
                            Spacer()
                            Text(ThemeKind.current.title).foregroundStyle(Theme.accent)
                        }
                    }
                }
                Section(header: Text("省钱账本怎么算")) {
                    Stepper(String(format: "油价 %.2f 元/升", fuel), value: $fuel, in: 4...12, step: 0.1)
                    Stepper(String(format: "开车百公里 %.1f 升", l100), value: $l100, in: 3...15, step: 0.5)
                    Stepper(String(format: "打车每公里 %.1f 元", taxi), value: $taxi, in: 1...6, step: 0.1)
                }
                Section(header: Text("导航和语音"), footer: Text("在仪表盘右上角点\"导航\"。优先用苹果地图的骑行路线，没有时用步行路线。语音会和音乐、高德的声音一起放，说话时把它们调小。")) {
                    Toggle("语音播报转弯", isOn: $nav.voiceOn)
                    Toggle("每骑 1 公里报一次里程和电量", isOn: $m.voiceKm)
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
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("设置")
            .task { lines = await LogStore.shared.recent() }
        }
    }
}
