import SwiftUI

// 骑行仪表盘：全黑背景，大车速表盘、功率条、电量和续航、这一趟的数据
struct RideView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ride: RideTracker
    @EnvironmentObject var nav: NavManager
    @State private var showSearch = false
    @State private var showBar = false
    @State private var showPerf = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 16) {
                    top
                    tools
                    if nav.active {
                        NavBanner()
                        ZStack(alignment: .bottomLeading) {
                            RouteMap(route: nav.route, follow: true)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(ride.freshSpeed.map { String(format: "%.0f", $0) } ?? "--")
                                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("km/h").font(.caption).foregroundStyle(Theme.sub)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.7)))
                            .padding(10)
                        }
                        .frame(height: 300)
                    } else {
                        Speedometer(speed: ride.freshSpeed, maxSpeed: 50)
                            .frame(maxWidth: .infinity)
                            .frame(height: 270)
                            .overlay(alignment: .bottom) {
                                if Pref.speedAlertOn, (ride.freshSpeed ?? 0) > Pref.speedLimit {
                                    Text("超速").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(Theme.bad))
                                }
                            }
                    }
                    power
                    tripGrid
                    if ride.track.count >= 2 { route }
                    blocksStrip
                    Spacer(minLength: 0)
                    button
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSearch) { NavSearchView() }
        .sheet(isPresented: $showPerf) { PerfTestView() }
        .fullScreenCover(isPresented: $showBar) { HandlebarView() }
    }

    private var top: some View {
        let soc = m.lowest?.soc
        return HStack(spacing: 12) {
            ZStack {
                Ring(progress: (soc ?? 0) / 100, color: Theme.soc(soc ?? 100), lineWidth: 6)
                Text(soc.map { String(format: "%.0f", $0) } ?? "--").font(.system(.subheadline, design: .rounded).weight(.bold))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("电量 · 按最低的一块").font(.caption2).foregroundStyle(Theme.sub)
                Text(m.rangeKm.map { String(format: "还能跑约 %.0f km", $0) } ?? "续航估算中").font(.subheadline.weight(.semibold))
                if let t = m.tempRange {
                    Text("电池温度 \(t.0)~\(t.1) °C").font(.caption2).foregroundStyle(t.1 >= 50 ? Theme.bad : t.1 >= 45 ? Theme.warn : Theme.sub)
                }
            }
            Spacer()
            Button { if nav.active { nav.stop() } else { showSearch = true } } label: {
                Label(nav.active ? "结束导航" : "导航", systemImage: nav.active ? "xmark" : "location.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(nav.active ? Theme.bad.opacity(0.85) : Theme.accent.opacity(0.85)))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(ride.on ? "已骑" : "未开始").font(.caption2).foregroundStyle(Theme.sub)
                Text((ride.startedAt.map { Date().timeIntervalSince($0) } ?? 0).hms)
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            pill("车把模式", "iphone.gen3", false) { showBar = true }
            pill("加速测试", "stopwatch", false) { showPerf = true }
            pill(m.engineOn ? "声浪 开" : "声浪", "speaker.wave.2.fill", m.engineOn) { m.engineOn.toggle() }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ t: String, _ icon: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label(t, systemImage: icon).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.1)))
                .foregroundStyle(.white)
        }
    }

    private var power: some View {
        let p = m.power ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p < 0 ? "回充" : "功率").font(.caption).foregroundStyle(Theme.sub)
                Spacer()
                Text(String(format: "%.0f W", abs(p))).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(p < 0 ? Theme.good : p > 1500 ? Theme.bad : .white)
                Text(String(format: "%.0f A", abs(m.current ?? 0))).font(.caption).foregroundStyle(Theme.sub).monospacedDigit()
            }
            PowerBar(power: p)
        }
    }

    private var tripGrid: some View {
        let avg = ride.movingS > 10 ? ride.distM / ride.movingS * 3.6 : nil
        return Grid(horizontalSpacing: 10, verticalSpacing: 14) {
            GridRow {
                StatTile(label: "里程", value: String(format: "%.2f", ride.distM / 1000), unit: "km")
                StatTile(label: "平均", value: avg.map { String(format: "%.0f", $0) } ?? "--", unit: "km/h")
                StatTile(label: "最高", value: ride.vMaxKmh > 0 ? String(format: "%.0f", ride.vMaxKmh) : "--", unit: "km/h")
            }
            GridRow {
                StatTile(label: "用电", value: String(format: "%.0f", m.tripWh), unit: "Wh")
                StatTile(label: "每公里", value: m.tripWhPerKm.map { String(format: "%.0f", $0) } ?? "--", unit: "Wh")
                StatTile(label: "压差", value: m.packGapMv.map { "\($0)" } ?? "--", unit: "mV", color: gapColor(m.packGapMv))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    // 骑行时电流一直在变，压差会比停着时大，所以这里放宽：300 mV 以上才标红
    private func gapColor(_ g: Int?) -> Color {
        guard let g else { return .white }
        return g >= 300 ? Theme.bad : g >= 150 ? Theme.warn : .white
    }

    // 这一趟的路线（不带地图，只画形状）
    private var route: some View {
        HStack(spacing: 12) {
            TrackShape(track: ride.track)
                .stroke(LinearGradient(colors: [Theme.accent, Theme.good], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 70, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("路线").font(.caption).foregroundStyle(Theme.sub)
                Text("结束后在记录里看地图").font(.caption2).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    // 五块电池的小电量条
    private var blocksStrip: some View {
        let bs = m.liveBlocks
        let lowId = m.lowest?.id
        return HStack(spacing: 8) {
            ForEach(bs, id: \.id) { b in
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Theme.soc(b.soc)).frame(width: g.size.width * min(max(b.soc / 100, 0), 1))
                        }
                    }
                    .frame(height: 6)
                    Text("\(b.name) \(Int(b.soc))%").font(.system(size: 10, weight: b.id == lowId ? .bold : .regular))
                        .foregroundStyle(b.id == lowId ? Theme.warn : Theme.sub).monospacedDigit()
                    Text("\(b.gapMv) mV").font(.system(size: 9)).foregroundStyle(Theme.faint).monospacedDigit()
                }
            }
        }
    }

    private var button: some View {
        VStack(spacing: 6) {
            Button { m.toggleRide() } label: {
                Text(ride.on ? "结束骑行" : "开始骑行")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(ride.on ? Theme.bad : Theme.accent))
                    .foregroundStyle(.white)
            }
            Text(ride.note.isEmpty ? "骑行时屏幕常亮；切到导航或锁屏，锁屏和灵动岛会继续显示。位置和轨迹只存在手机上，不会上传。" : ride.note)
                .font(.caption2).foregroundStyle(ride.note.isEmpty ? Theme.faint : Theme.warn).multilineTextAlignment(.center)
        }
    }
}
