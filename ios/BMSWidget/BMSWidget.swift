import WidgetKit
import SwiftUI
import ActivityKit

@main
struct BMSWidgetBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

private let blue = Color(red: 0.33, green: 0.57, blue: 1.0)
private let green = Color(red: 0.36, green: 0.87, blue: 0.55)
private let amber = Color(red: 1.0, green: 0.75, blue: 0.30)
private let red = Color(red: 1.0, green: 0.40, blue: 0.38)
private let sub = Color.white.opacity(0.6)
private func socColor(_ s: Double) -> Color { s <= 15 ? red : s <= 30 ? amber : green }
private func powerColor(_ p: Int) -> Color { p < 0 ? green : p > 1500 ? red : .white }

private extension RideAttributes.ContentState {
    var speedText: String { speed >= 0 ? "\(speed)" : "--" }
    var rangeText: String { rangeKm >= 0 ? "\(rangeKm)" : "--" }
    var tempText: String { tempMax > -99 ? "\(tempMax)°" : "--" }
    var avgText: String { avgKmh >= 0 ? "\(avgKmh)" : "--" }
    var whText: String { whPerKm >= 0 ? "\(whPerKm)" : "--" }

    /// 收起时某一边显示的文字和颜色
    func compact(_ key: String) -> (String, Color) {
        switch IslandItem(rawValue: key) ?? .speed {
        case .speed: return (speedText, blue)
        case .soc: return ("\(Int(soc))%", socColor(soc))
        case .power: return ("\(abs(power))W", powerColor(power))
        case .range: return (rangeText + "km", .white)
        case .dist: return (String(format: "%.1fkm", distKm), .white)
        case .current: return (String(format: "%.0fA", abs(current)), .white)
        case .temp: return (tempText, tempMax >= 50 ? red : .white)
        case .wh: return (whText, .white)
        }
    }
}

// 一个小数据：上面数值，下面名字
private struct Mini: View {
    let value: String
    let label: String
    var color: Color = .white
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9)).foregroundStyle(sub)
        }
        .frame(maxWidth: .infinity)
    }
}

// 五块电池的小电量条
private struct BlockBars: View {
    let s: RideAttributes.ContentState
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(zip(s.blockNames, s.blockSocs).enumerated()), id: \.offset) { i, item in
                VStack(spacing: 2) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(socColor(Double(item.1))).frame(width: g.size.width * min(max(Double(item.1) / 100, 0), 1))
                        }
                    }
                    .frame(height: 5)
                    Text("\(item.0) \(item.1)").font(.system(size: 9, weight: i == s.lowIndex ? .bold : .regular)).monospacedDigit()
                        .foregroundStyle(i == s.lowIndex ? amber : sub)
                }
            }
        }
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { ctx in
            LockScreenView(s: ctx.state, startedAt: ctx.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let start = ctx.attributes.startedAt
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.speedText).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(blue)
                        Text("km/h · 最高 \(s.maxKmh)").font(.system(size: 10)).foregroundStyle(sub)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(s.soc))%").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(socColor(s.soc))
                        Text("续航 \(s.rangeText) km").font(.system(size: 10)).foregroundStyle(sub)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Image(systemName: s.power < 0 ? "arrow.down.circle.fill" : "bolt.fill").font(.system(size: 11))
                        Text("\(abs(s.power)) W").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(powerColor(s.power))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if s.navDist >= 0 { NavLine(s: s) }
                        HStack(spacing: 0) {
                            Mini(value: String(format: "%.2f", s.distKm), label: "里程 km")
                            Mini(value: s.avgText, label: "平均 km/h")
                            VStack(spacing: 1) {
                                Text(start, style: .timer).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .multilineTextAlignment(.center)
                                Text("用时").font(.system(size: 9)).foregroundStyle(sub)
                            }
                            .frame(maxWidth: .infinity)
                            Mini(value: String(format: "%.0f", abs(s.current)), label: "电流 A")
                            Mini(value: s.tempText, label: "温度", color: s.tempMax >= 50 ? red : .white)
                        }
                        if !s.blockSocs.isEmpty { BlockBars(s: s) }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                if s.navDist >= 0 {
                    HStack(spacing: 2) {
                        Image(systemName: navIcon(for: s.navText)).font(.system(size: 12, weight: .bold))
                        Text(s.navDist >= 1000 ? String(format: "%.1fk", Double(s.navDist) / 1000) : "\(s.navDist)m")
                            .font(.system(.caption, design: .rounded).weight(.bold)).monospacedDigit()
                    }
                    .foregroundStyle(blue)
                } else {
                    let c = s.compact(s.left)
                    Text(c.0).font(.system(.body, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(c.1)
                }
            } compactTrailing: {
                let c = s.compact(s.right)
                Text(c.0).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(c.1)
            } minimal: {
                Text("\(Int(s.soc))").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(socColor(s.soc))
            }
        }
    }
}

// 导航提示一行：箭头、距离、动作
private struct NavLine: View {
    let s: RideAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: navIcon(for: s.navText)).font(.system(size: 18, weight: .bold))
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(blue))
            Text(s.navDist >= 1000 ? String(format: "%.1f 公里", Double(s.navDist) / 1000) : "\(s.navDist) 米")
                .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
            Text(s.navText).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 0)
            Text(String(format: "剩 %.1f km", Double(s.navLeftM) / 1000)).font(.system(size: 10)).foregroundStyle(sub)
        }
        .foregroundStyle(.white)
    }
}

struct LockScreenView: View {
    let s: RideAttributes.ContentState
    let startedAt: Date
    var body: some View {
        VStack(spacing: 10) {
            if s.navDist >= 0 { NavLine(s: s) }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.speedText).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    Text("km/h · 最高 \(s.maxKmh)").font(.system(size: 10)).foregroundStyle(sub)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("电量 \(Int(s.soc))%").font(.subheadline.weight(.bold)).foregroundStyle(socColor(s.soc))
                        Spacer()
                        Text("续航 \(s.rangeText) km").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                    ProgressView(value: min(max(s.soc / 100, 0), 1)).tint(socColor(s.soc))
                    HStack(spacing: 4) {
                        Image(systemName: s.power < 0 ? "arrow.down.circle.fill" : "bolt.fill").font(.system(size: 11))
                        Text("\(abs(s.power)) W").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(String(format: "· %.0f A · %.1f V", abs(s.current), s.voltage)).font(.caption2).foregroundStyle(sub).monospacedDigit()
                    }
                    .foregroundStyle(powerColor(s.power))
                }
            }
            HStack(spacing: 0) {
                Mini(value: String(format: "%.2f", s.distKm), label: "里程 km")
                VStack(spacing: 1) {
                    Text(startedAt, style: .timer).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("用时").font(.system(size: 9)).foregroundStyle(sub)
                }
                .frame(maxWidth: .infinity)
                Mini(value: s.avgText, label: "平均 km/h")
                Mini(value: "\(s.tripWh)", label: "用电 Wh")
                Mini(value: s.whText, label: "Wh/km")
                Mini(value: s.tempText, label: "温度", color: s.tempMax >= 50 ? red : .white)
            }
            if !s.blockSocs.isEmpty { BlockBars(s: s) }
        }
        .padding(14)
    }
}
