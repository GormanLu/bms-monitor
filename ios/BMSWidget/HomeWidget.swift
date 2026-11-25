import WidgetKit
import SwiftUI

// 主屏幕和锁屏的小组件：显示 app 最后一次收到的电池数据
struct SnapEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnap?
}

struct SnapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry {
        SnapEntry(date: Date(), snap: WidgetSnap(t: Date(), soc: 76, range: 38, charging: false, eta: nil, weekKm: 18, goalKm: 30, todayKm: 4.2,
                                                 gapMv: 12, tempMax: 21, names: ["A", "B", "C", "D", "P"], socs: [78, 77, 78, 76, 76], parkedAt: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapEntry(date: Date(), snap: WidgetShare.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let s = WidgetShare.load()
        // 每 15 分钟刷新一次"多久以前"，数据本身由 app 收到新数据时通知刷新
        let entries = (0..<8).map { SnapEntry(date: Date().addingTimeInterval(Double($0) * 900), snap: s) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private let wGreen = Color(red: 0.36, green: 0.87, blue: 0.55)
private let wAmber = Color(red: 1.0, green: 0.75, blue: 0.30)
private let wRed = Color(red: 1.0, green: 0.40, blue: 0.38)
private let wBlue = Color(red: 0.33, green: 0.57, blue: 1.0)
private func wSoc(_ s: Double) -> Color { s <= 15 ? wRed : s <= 30 ? wAmber : wGreen }

private func ago(_ t: Date, now: Date) -> String {
    let m = Int(now.timeIntervalSince(t) / 60)
    if m < 1 { return "刚刚" }
    if m < 60 { return "\(m) 分钟前" }
    if m < 60 * 24 { return "\(m / 60) 小时前" }
    return "\(m / 1440) 天前"
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapEntry

    var body: some View {
        if let s = entry.snap {
            switch family {
            case .accessoryCircular: circular(s)
            case .accessoryRectangular: rect(s)
            case .accessoryInline: Text("电量 \(Int(s.soc))% · 续航 \(s.range >= 0 ? "\(s.range)" : "--") km")
            case .systemMedium: medium(s).widgetBG()
            default: small(s).widgetBG()
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "battery.100.bolt")
                Text("打开 app 连一次电池").font(.caption2)
            }
            .widgetBG()
        }
    }

    private func ring(_ s: WidgetSnap, _ w: CGFloat) -> some View {
        ZStack {
            Circle().stroke(wSoc(s.soc).opacity(0.2), lineWidth: w)
            Circle().trim(from: 0, to: max(0.01, s.soc / 100)).stroke(wSoc(s.soc), style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int(s.soc))").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                Text(s.charging ? "充电中" : "%").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private func small(_ s: WidgetSnap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ring(s, 7).frame(width: 66, height: 66)
                Spacer()
                if s.charging { Image(systemName: "bolt.fill").foregroundStyle(wGreen) }
            }
            Text(s.charging ? (s.eta.map { "预计 \($0) 充满" } ?? "正在充电") : "续航约 \(s.range >= 0 ? "\(s.range)" : "--") km")
                .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(ago(s.t, now: entry.date) + "更新").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnap) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ring(s, 8).frame(width: 76, height: 76)
                Text(ago(s.t, now: entry.date) + "更新").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(s.charging ? (s.eta.map { "充电中 · 预计 \($0) 充满" } ?? "充电中") : "续航约 \(s.range >= 0 ? "\(s.range)" : "--") km")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    ForEach(0..<min(s.names.count, s.socs.count), id: \.self) { i in
                        let n = s.names[i], v = s.socs[i]
                        VStack(spacing: 2) {
                            GeometryReader { g in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 3).fill(wSoc(Double(v))).frame(height: g.size.height * CGFloat(min(max(v, 0), 100)) / 100)
                                }
                            }
                            .frame(height: 30)
                            Text(n).font(.system(size: 9, weight: .semibold))
                        }
                    }
                }
                HStack {
                    Label(String(format: "本周 %.0f/%.0f km", s.weekKm, s.goalKm), systemImage: "target")
                    Spacer()
                    Text("压差 \(s.gapMv)mV · \(s.tempMax)°")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func circular(_ s: WidgetSnap) -> some View {
        Gauge(value: min(max(s.soc, 0), 100), in: 0...100) {
            Image(systemName: s.charging ? "bolt.fill" : "bolt.car")
        } currentValueLabel: {
            Text("\(Int(s.soc))")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetBG()
    }

    private func rect(_ s: WidgetSnap) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: s.charging ? "bolt.fill" : "bolt.car.fill")
                Text("电量 \(Int(s.soc))%").font(.headline)
            }
            Text(s.charging ? (s.eta.map { "预计 \($0) 充满" } ?? "充电中") : "续航约 \(s.range >= 0 ? "\(s.range)" : "--") km")
            Text(ago(s.t, now: entry.date) + "更新").font(.caption2).foregroundStyle(.secondary)
        }
        .widgetBG()
    }
}

private extension View {
    @ViewBuilder func widgetBG() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { Color(red: 0.06, green: 0.08, blue: 0.14) }
        } else {
            self.padding().background(Color(red: 0.06, green: 0.08, blue: 0.14))
        }
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BMSHome", provider: SnapProvider()) { e in
            HomeWidgetView(entry: e).environment(\.colorScheme, .dark)
        }
        .configurationDisplayName("电池电量")
        .description("最低一块的电量、续航和五块的电量。数据来自 app 最后一次连上电池。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
