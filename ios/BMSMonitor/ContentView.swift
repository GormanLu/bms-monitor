import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("theme") private var theme = "blue"

    var body: some View {
        TabView(selection: $m.tab) {
            HomeView().tabItem { Label("电池", systemImage: "battery.100.bolt") }.tag(0)
            RideView().tabItem { Label("仪表盘", systemImage: "speedometer") }.tag(1)
            TripsView().tabItem { Label("记录", systemImage: "list.bullet.rectangle") }.tag(2)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        .id(theme)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { BadgeToast() }
        .fullScreenCover(isPresented: $m.crashAlert) { CrashAlertView() }
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
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.12, green: 0.14, blue: 0.22)))
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
    @AppStorage("crash.on") private var crashOn = false
    @AppStorage("crash.phone") private var crashPhone = ""
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
                Section(header: Text("骑行"), footer: Text("自动开始：连着电池时，电机持续出力 6 秒就自动开始记录（手动结束后 3 分钟内不会再自动开始）。app 在后台时自动开始，可能拿不到定位，车速和里程会缺。自动结束：车速和电流都停了 5 分钟。")) {
                    Toggle("骑起来自动开始记录", isOn: $autoStart)
                    Toggle("停车 5 分钟自动结束", isOn: $autoStop)
                    Toggle("超速语音提醒", isOn: $speedAlert)
                    if speedAlert { Stepper("超过 \(Int(speedLimit)) km/h 提醒", value: $speedLimit, in: 15...60, step: 1) }
                    Stepper("每周目标 \(Int(goalWeek)) 公里", value: $goalWeek, in: 5...500, step: 5)
                }
                Section(header: Text("摔车检测"), footer: Text("骑行中手机感到剧烈撞击时，全屏提醒并倒计时 30 秒；没点\"我没事\"会语音提示和弹通知。app 不会自动打电话，要你自己点屏幕上的按钮。电话只存在这台手机里。手机掉地上也可能触发。")) {
                    Toggle("打开摔车检测", isOn: $crashOn)
                    if crashOn { TextField("紧急联系人电话（可不填）", text: $crashPhone).keyboardType(.phonePad) }
                }
                Section(header: Text("仪表主题"), footer: Text("在徽章页升级解锁更多颜色。")) { ThemePicker() }
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
            .navigationTitle("设置")
            .task { lines = await LogStore.shared.recent() }
        }
    }
}
