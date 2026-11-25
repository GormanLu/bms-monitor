import SwiftUI

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var ride: RideTracker

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ScrollView {
                        VStack(spacing: 14) {
                            connection
                            hero
                            if m.liveBlocks.count >= 2 { pack }
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
