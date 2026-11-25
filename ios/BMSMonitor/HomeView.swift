import SwiftUI

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var ride: RideTracker
    @EnvironmentObject var stats: BatteryStats
    @EnvironmentObject var snaps: SnapStore
    @EnvironmentObject var health: HealthStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ScrollView {
                        VStack(spacing: 14) {
                            connection
                            hero
                            checkIn
                            if m.liveBlocks.count >= 2 { pack }
                            life
                            if m.isCharging { charging }
                            live
                            rideShortcut
                            upload
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("电池监控")
            .sheet(isPresented: $ble.scanning) { DevicePicker() }
        }
    }

    // MARK: 连接状态
    private var connection: some View {
        HStack(spacing: 10) {
            Circle().fill(ble.connected && fresh ? Theme.good : ble.connected ? Theme.warn : Theme.faint).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(ble.status).font(.subheadline.weight(.semibold))
                Text(ageText).font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer()
            if ble.connected || ble.status.hasPrefix("正在") || ble.status.hasPrefix("断开了") {
                Button("断开") { ble.disconnect() }.buttonStyle(.bordered).tint(.white)
            } else {
                Button { ble.connect() } label: { Label("连接电池", systemImage: "antenna.radiowaves.left.and.right") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var fresh: Bool { m.lastDataAt.map { Date().timeIntervalSince($0) <= 8 } ?? false }

    private var ageText: String {
        guard let t = m.lastDataAt else {
            return ble.deviceTail.isEmpty ? "第一次用：点\"连接电池\"，选名称结尾 01 的那一块" : "电池：名称结尾 \(ble.deviceTail)"
        }
        let s = Int(Date().timeIntervalSince(t))
        return s <= 8 ? "实时 · " + t.formatted(date: .omitted, time: .standard) : "已经 \(s) 秒没有新数据"
    }

    // MARK: 大电量圆环
    private var hero: some View {
        let soc = m.lowest?.soc
        return GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    Ring(progress: (soc ?? 0) / 100, color: Theme.soc(soc ?? 100), lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(soc.map { String(format: "%.0f", $0) } ?? "--")
                            .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("%").font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 10) {
                    if let lo = m.lowest, m.liveBlocks.count > 1 {
                        Label("按最低的一块 · 模块 \(lo.name)", systemImage: "battery.25")
                            .font(.caption).foregroundStyle(Theme.sub)
                    }
                    StatTile(label: "估算续航", value: m.rangeKm.map { String(format: "%.0f", $0) } ?? "--", unit: "km", icon: "road.lanes")
                    StatTile(label: "剩余", value: m.lowest.map { String(format: "%.1f", $0.remainAh) } ?? "--", unit: "Ah", icon: "bolt.batteryblock")
                    if let s = m.summary {
                        Text(String(format: "保护板汇总 %.1f%% · 每公里 %.0f Wh", s.soc, m.whPerKm)).font(.caption2).foregroundStyle(Theme.faint)
                    }
                }
            }
            let shut = m.liveBlocks.filter(\.chargeShut)
            if !shut.isEmpty {
                Label("模块 " + shut.map(\.name).joined(separator: "、") + " 充满后关了充电，骑一小段会自动打开", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(Theme.warn)
            }
        }
    }

    // MARK: 五块电池
    private var pack: some View {
        let blocks = m.liveBlocks
        let lowId = m.lowest?.id
        return GlassCard(title: "五块电池", icon: "square.stack.3d.up.fill") {
            HStack(alignment: .top, spacing: 8) {
                ForEach(blocks, id: \.id) { b in
                    BatteryCell(block: b, isLowest: b.id == lowId && blocks.count > 1, showCharge: m.isCharging)
                }
            }
            Text("每块下面依次是电量、块内压差、温度。橙色边框是电量最低的一块。")
                .font(.caption2).foregroundStyle(Theme.faint)
        }
    }

    // MARK: 一键打卡
    private var checkIn: some View {
        GlassCard(title: "每日打卡", icon: "checkmark.seal.fill") {
            HStack {
                Picker("状态", selection: $snaps.note) {
                    ForEach(SnapStore.notes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                Spacer()
                Button { m.checkIn() } label: {
                    Label(m.checkingIn ? "打卡中…" : "一键打卡", systemImage: "hand.tap.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(m.checkingIn)
            }
            Text(m.checkInMsg.isEmpty ? "选好电池现在的状态再点：自动连接、等数据收齐、记一条快照并上传。" : m.checkInMsg)
                .font(.caption).foregroundStyle(m.checkInMsg.isEmpty ? Theme.faint : Theme.sub)
            if !snaps.snaps.isEmpty {
                ForEach(snaps.snaps.prefix(3)) { s in
                    HStack {
                        Text(s.t.formatted(.dateTime.month().day().hour().minute()) + " · " + s.note).font(.caption)
                        Spacer()
                        Text("压差 \(s.gapMv) mV · \(s.lowName) 低 \(s.lowMv)").font(.caption).foregroundStyle(Theme.sub).monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: 循环次数和健康度
    private var life: some View {
        NavigationLink { BatteryLifeView() } label: {
            GlassCard(title: "电池寿命", icon: "heart.text.square.fill") {
                HStack {
                    StatTile(label: "循环次数", value: String(format: "%.1f", stats.cycles), unit: "次")
                    StatTile(label: "健康度（估算）", value: String(format: "%.1f", stats.cycleHealth), unit: "%", color: Theme.good)
                    StatTile(label: "P 比别的低", value: health.records.first.map { "\($0.pLowMv)" } ?? "--", unit: "mV")
                }
                HStack {
                    Text("点开看怎么算的").font(.caption2).foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 充电
    private var charging: some View {
        GlassCard(title: "正在充电", icon: "bolt.fill") {
            HStack {
                StatTile(label: "充电功率", value: m.power.map { String(format: "%.0f", abs($0)) } ?? "--", unit: "W", color: Theme.good)
                StatTile(label: "电流", value: m.current.map { String(format: "%.1f", $0) } ?? "--", unit: "A")
                StatTile(label: "充满还要", value: m.chargeHours.map { h in h >= 1 ? String(format: "%.0f:%02.0f", floor(h), (h - floor(h)) * 60) : String(format: "%.0f分", h * 60) } ?? "--")
            }
            let stopped = m.liveBlocks.filter { abs($0.current) < 0.2 }
            if !stopped.isEmpty && stopped.count < m.liveBlocks.count {
                Text("模块 " + stopped.map(\.name).joined(separator: "、") + " 已经不进电，其余的还在充").font(.caption).foregroundStyle(Theme.sub)
            }
            if m.liveBlocks.contains(where: { $0.balance != 0 }) {
                Label("正在均衡：" + m.liveBlocks.filter { $0.balance != 0 }.map(\.name).joined(separator: "、"), systemImage: "waveform.path")
                    .font(.caption).foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: 实时数据
    private var live: some View {
        GlassCard(title: "实时", icon: "waveform.path.ecg") {
            HStack {
                StatTile(label: (m.power ?? 0) < 0 ? "充电" : "功率", value: m.power.map { String(format: "%.0f", abs($0)) } ?? "--", unit: "W", icon: "bolt")
                StatTile(label: "电流", value: m.current.map { String(format: "%.1f", abs($0) < 0.6 ? 0 : abs($0)) } ?? "--", unit: "A", icon: "arrow.left.arrow.right")
            }
            HStack {
                StatTile(label: "总电压", value: m.totalV.map { String(format: "%.1f", $0) } ?? "--", unit: "V", icon: "minus.plus.batteryblock")
                StatTile(label: "温度", value: m.tempRange.map { "\($0.0)~\($0.1)" } ?? "--", unit: "°C", icon: "thermometer.medium")
            }
            if let g = m.packGapMv {
                Text("整组最高和最低一节差 \(g) mV（电流在变时这个数不准）").font(.caption2).foregroundStyle(Theme.faint)
            }
        }
    }

    // MARK: 骑行入口
    private var rideShortcut: some View {
        Button {
            if ride.on { m.tab = 1 } else { m.toggleRide() }
        } label: {
            HStack {
                Image(systemName: ride.on ? "speedometer" : "figure.outdoor.cycle").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.on ? "正在骑行 · 打开仪表盘" : "开始骑行").font(.headline)
                    Text(ride.on ? String(format: "已骑 %.2f km", ride.distM / 1000) : "记录车速、里程和耗电，锁屏和灵动岛也会显示")
                        .font(.caption).opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.2, green: 0.32, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }

    // MARK: 上传
    private var upload: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("日志").font(.subheadline.weight(.semibold))
                    Text(m.storedBytes > 0 ? String(format: "手机上存着 %.1f MB 没上传", Double(m.storedBytes) / 1_000_000) : "没有要上传的")
                        .font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button(m.uploading ? "上传中…" : "上传给 Claude") { m.upload() }
                    .buttonStyle(.bordered).tint(.white).disabled(m.uploading)
            }
            if !m.uploadMsg.isEmpty { Text(m.uploadMsg).font(.caption).foregroundStyle(Theme.sub) }
        }
    }
}

struct BatteryLifeView: View {
    @EnvironmentObject var stats: BatteryStats
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var charges: ChargeStore
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard(title: "循环次数", icon: "arrow.triangle.2.circlepath") {
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%.1f", stats.cycles)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("次（等效满充满放）").foregroundStyle(Theme.sub)
                        }
                        HStack {
                            StatTile(label: "app 记到放出", value: String(format: "%.0f", stats.dischargedAh), unit: "Ah")
                            StatTile(label: "app 记到充进", value: String(format: "%.0f", stats.chargedAh), unit: "Ah")
                            StatTile(label: "约", value: String(format: "%.1f", stats.dischargedAh * 64 / 1000), unit: "度电")
                        }
                        Text("保护板里没有能确认的循环次数，所以由 app 自己数：五块平均剩余容量每少 60 Ah，算一次满充满放。没连着 app 时用掉的电，只要中间没充电，下次连上也能补算；如果中间又充了电，那段会漏算一点。")
                            .font(.caption2).foregroundStyle(Theme.faint)
                        Stepper(String(format: "开始统计前已有：%.0f 次", stats.baselineCycles), value: $stats.baselineCycles, in: 0...3000, step: 1)
                            .font(.subheadline)
                        if !stats.bmsCycles.isEmpty {
                            Text("保护板自己记的：" + stats.bmsCycles.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.sub)
                            Text("小程序显示的循环次数就是主模块 P 的这个数（一直是 0），另外四块一直是 3。11 月 19 日以来实际已经放出约一整轮的电，这几个数都没变，所以不准，只供参考。")
                                .font(.caption2).foregroundStyle(Theme.faint)
                        }
                        Text("app 是 11 月 25 日开始数的。默认补了 1 次（19 日到 25 日的日志里已经放出约 58 Ah）；在那之前用的两周，可以按大概充满过几次再往上加。")
                            .font(.caption2).foregroundStyle(Theme.faint)
                    }
                    GlassCard(title: "健康度", icon: "heart.fill") {
                        HStack {
                            StatTile(label: "按循环估算", value: String(format: "%.1f", stats.cycleHealth), unit: "%", color: Theme.good)
                            StatTile(label: "保护板报的", value: stats.bmsHealth.map { "\($0)" } ?? "--", unit: "%")
                        }
                        Text("按循环估算：磷酸铁锂一般按用 2000 次后剩 80% 容量来算，这是平均水平的估计，不是测出来的。")
                            .font(.caption2).foregroundStyle(Theme.faint)
                        Text("保护板报的：保护板数据里有一个字节一直是 200，按它\"电量 ×2\"的习惯推测是健康度 100%。新电池本来就是 100%，所以还没法确认它会不会随老化变化。")
                            .font(.caption2).foregroundStyle(Theme.faint)
                    }
                    GlassCard(title: "一致性（P 这一块）", icon: "square.stack.3d.up") {
                        if let r = health.records.first {
                            Text("最近一次：电量 \(Int(r.soc))% 时，P 平均每节比其他块低 \(r.pLowMv) mV").font(.subheadline)
                        } else {
                            Text("还没有电池健康记录。").font(.subheadline)
                        }
                        Text("真正反映电池变老的是一致性：如果 P 在同样的电量下比别的块低得越来越多，说明它在变差。曲线在\"记录 → 电池健康\"里。")
                            .font(.caption2).foregroundStyle(Theme.faint)
                        Text("完整充电 \(charges.sessions.filter(\.complete).count) 次 · 健康记录 \(health.records.count) 天").font(.caption2).foregroundStyle(Theme.sub)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("电池寿命")
        .navigationBarTitleDisplayMode(.inline)
    }
}
