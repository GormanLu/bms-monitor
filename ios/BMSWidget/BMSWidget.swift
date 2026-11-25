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
private func socColor(_ s: Double) -> Color { s <= 15 ? red : s <= 30 ? amber : green }
private func speedText(_ s: RideAttributes.ContentState) -> String { s.speed >= 0 ? "\(s.speed)" : "--" }

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { ctx in
            LockScreenView(state: ctx.state, startedAt: ctx.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(speedText(s)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("公里/小时").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(s.soc))%").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(socColor(s.soc))
                        Text(s.rangeKm >= 0 ? "续航 \(s.rangeKm) km" : "电量").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("\(abs(s.power)) W", systemImage: s.power < 0 ? "arrow.down.circle" : "bolt.fill")
                            .foregroundStyle(s.power < 0 ? green : s.power > 1500 ? red : .white)
                        Spacer()
                        Label(String(format: "%.2f km", s.distKm), systemImage: "road.lanes")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Text(speedText(s)).font(.system(.body, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(blue)
            } compactTrailing: {
                Text("\(Int(s.soc))%").font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(socColor(s.soc))
            } minimal: {
                Text("\(Int(s.soc))").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(socColor(s.soc))
            }
        }
    }
}

struct LockScreenView: View {
    let state: RideAttributes.ContentState
    let startedAt: Date
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(speedText(state)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Text("公里/小时").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("电量 \(Int(state.soc))%").font(.subheadline.weight(.semibold)).foregroundStyle(socColor(state.soc))
                    Spacer()
                    if state.rangeKm >= 0 { Text("续航约 \(state.rangeKm) km").font(.caption).foregroundStyle(.white.opacity(0.7)) }
                }
                ProgressView(value: min(max(state.soc / 100, 0), 1)).tint(socColor(state.soc))
                HStack {
                    Label("\(abs(state.power)) W", systemImage: state.power < 0 ? "arrow.down.circle" : "bolt.fill")
                    Spacer()
                    Label(String(format: "%.2f km", state.distKm), systemImage: "road.lanes")
                    Spacer()
                    Text(startedAt, style: .timer).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(16)
    }
}
