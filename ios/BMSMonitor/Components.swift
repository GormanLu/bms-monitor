import SwiftUI

// MARK: 配色和卡片
// 颜色、圆角、数字字体都跟着当前主题走（换主题时 ContentView 用 .id(theme) 整个重画）
enum Theme {
    static var kind: ThemeKind { ThemeKind.current }
    static var bgTop: Color { kind.bgTop }
    static var bgBottom: Color { kind.bgBottom }
    static var card: Color { kind.card }
    static var stroke: Color { kind.stroke }
    static var accent: Color { kind.accent }
    static var accent2: Color { kind.accent2 }
    static var radius: CGFloat { kind.radius }
    static var font: Font.Design { kind.font }
    /// 实心的卡片底色（弹窗、海报这种不透明的地方用）
    static var solid: Color { kind.solid }
    static let good = Color(red: 0.36, green: 0.87, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.75, blue: 0.30)
    static let bad = Color(red: 1.0, green: 0.40, blue: 0.38)
    static let sub = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.35)
    static func soc(_ s: Double) -> Color { s <= 15 ? bad : s <= 30 ? warn : good }
}

/// 整组压差怎么看：停着时（电流很小）30 mV 以内正常；骑车带载时各块压降不一样，会被拉大，150 mV 以内都正常
func gapStyle(_ g: Int?, loaded: Bool) -> (color: Color, note: String) {
    guard let g else { return (.white, "等数据") }
    if loaded {
        return g >= 300 ? (Theme.bad, "带载偏大") : g >= 150 ? (Theme.warn, "带载略大") : (.white, "带载，正常")
    }
    return g >= 60 ? (Theme.bad, "静置偏大") : g >= 30 ? (Theme.warn, "静置略大") : (Theme.good, "静置，很齐")
}

struct AppBackground: View {
    var kind: ThemeKind = .current
    var body: some View {
        ZStack {
            LinearGradient(colors: [kind.bgTop, kind.bgBottom], startPoint: .top, endPoint: .bottom)
            ThemeDecor(kind: kind)
        }
        .ignoresSafeArea()
    }
}

/// 每个主题自己的背景纹理：都是静态图形，不做动画，不费电
struct ThemeDecor: View {
    let kind: ThemeKind
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            switch kind {
            case .blue:
                // 深夜蓝：顶上一团淡淡的蓝光
                RadialGradient(colors: [kind.accent.opacity(0.22), .clear], center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: w * 0.9)
            case .green:
                // 极光：两条斜着的绿、青色光带
                ZStack {
                    Ellipse().fill(kind.accent.opacity(0.28)).frame(width: w * 1.3, height: h * 0.16)
                        .rotationEffect(.degrees(-18)).offset(x: -w * 0.1, y: -h * 0.36).blur(radius: 50)
                    Ellipse().fill(kind.accent2.opacity(0.22)).frame(width: w * 1.1, height: h * 0.12)
                        .rotationEffect(.degrees(-8)).offset(x: w * 0.2, y: -h * 0.27).blur(radius: 55)
                    Ellipse().fill(Color(red: 0.55, green: 0.35, blue: 1.0).opacity(0.10)).frame(width: w * 0.8, height: h * 0.10)
                        .offset(x: w * 0.3, y: -h * 0.42).blur(radius: 50)
                }
                .frame(width: w, height: h)
            case .orange:
                // 落日：顶上半个太阳，下半截切成横条
                ZStack {
                    RadialGradient(colors: [kind.accent.opacity(0.30), kind.accent2.opacity(0.10), .clear], center: .init(x: 0.5, y: 0.08), startRadius: 0, endRadius: w)
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.82, blue: 0.35), kind.accent, kind.accent2], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.5, height: w * 0.5)
                        .mask(VStack(spacing: 0) {
                            Rectangle().frame(height: w * 0.25)
                            ForEach(0..<7, id: \.self) { i in
                                Rectangle().frame(height: CGFloat(10 - i))
                                Color.clear.frame(height: CGFloat(3 + i))
                            }
                            Spacer(minLength: 0)
                        })
                        .opacity(0.45)
                        .position(x: w * 0.8, y: h * 0.11)
                        .blur(radius: 1)
                }
            case .purple:
                // 赛博：霓虹网格 + 两角的品红、青色光
                ZStack {
                    Path { p in
                        let s: CGFloat = 28
                        var x: CGFloat = 0
                        while x <= w { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: h)); x += s }
                        var y: CGFloat = 0
                        while y <= h { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: w, y: y)); y += s }
                    }
                    .stroke(kind.accent.opacity(0.07), lineWidth: 0.6)
                    RadialGradient(colors: [kind.accent.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: w * 0.9)
                    RadialGradient(colors: [kind.accent2.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 0, endRadius: w * 0.9)
                }
            case .gold:
                // 黑金：很细的斜纹 + 顶上一点暖光
                ZStack {
                    Path { p in
                        var x: CGFloat = -h
                        while x <= w { p.move(to: .init(x: x, y: h)); p.addLine(to: .init(x: x + h, y: 0)); x += 9 }
                    }
                    .stroke(kind.accent.opacity(0.035), lineWidth: 0.5)
                    RadialGradient(colors: [kind.accent.opacity(0.14), .clear], center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: w * 0.8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon) }
                    Text(title)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.sub)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.stroke, lineWidth: Theme.kind.strokeWidth))
        .shadow(color: Theme.kind.glow, radius: Theme.kind == .purple ? 10 : 0)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var icon: String? = nil
    var color: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(label).font(.caption)
            }
            .foregroundStyle(Theme.sub)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title3, design: Theme.font).weight(.semibold)).monospacedDigit().foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.sub) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: 圆环
struct Ring: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(progress, 1)))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.6), value: progress)
    }
}

// MARK: 车速表盘：270° 的弧，0～maxSpeed
struct Speedometer: View {
    var speed: Double?
    var maxSpeed: Double = 50
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ratio = min(max((speed ?? 0) / maxSpeed, 0), 1)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * ratio)
                    .stroke(AngularGradient(colors: Theme.kind.gauge, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.5), value: ratio)
                // 刻度：每 5 km/h 一格，每 10 km/h 写数字
                ForEach(0...Int(maxSpeed / 5), id: \.self) { i in
                    let major = i % 2 == 0
                    Capsule()
                        .fill(Color.white.opacity(major ? 0.6 : 0.25))
                        .frame(width: major ? 3 : 2, height: major ? size * 0.05 : size * 0.03)
                        .offset(y: -size * 0.36)
                        .rotationEffect(.degrees(-135 + Double(i) * 270 / (maxSpeed / 5)))
                    if major {
                        Text("\(i * 5)")
                            .font(.system(size: size * 0.05, weight: .medium, design: Theme.font))
                            .foregroundStyle(Theme.faint)
                            .rotationEffect(.degrees(135 - Double(i) * 270 / (maxSpeed / 5)))
                            .offset(y: -size * 0.29)
                            .rotationEffect(.degrees(-135 + Double(i) * 270 / (maxSpeed / 5)))
                    }
                }
                VStack(spacing: 0) {
                    Text(speed.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: size * 0.26, weight: .bold, design: Theme.font))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("公里/小时").font(.system(size: size * 0.045)).foregroundStyle(Theme.sub)
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: 功率条：右边是耗电（橙），左边是回充（绿）
struct PowerBar: View {
    var power: Double
    var maxW: Double = 2500
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, mid = w * 0.2
            let pos = min(max(power, 0) / maxW, 1), neg = min(max(-power, 0) / 500, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.warn, Theme.bad], startPoint: .leading, endPoint: .trailing))
                    .frame(width: (w - mid) * pos)
                    .offset(x: mid)
                Capsule()
                    .fill(Theme.good)
                    .frame(width: mid * neg)
                    .offset(x: mid - mid * neg)
                Rectangle().fill(Color.white.opacity(0.4)).frame(width: 2).offset(x: mid - 1)
            }
            .animation(.easeOut(duration: 0.4), value: power)
        }
        .frame(height: 10)
    }
}

// MARK: 一块电池：竖着的电池形状，里面的高度就是电量
struct BatteryCell: View {
    let block: BlockData
    var isLowest = false
    var showCharge = false
    var balancing = false
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isLowest ? Theme.warn : Color.white.opacity(0.35), lineWidth: isLowest ? 2 : 1.5)
                GeometryReader { g in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.soc(block.soc), Theme.soc(block.soc).opacity(0.6)], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(4, (g.size.height) * min(max(block.soc / 100, 0), 1)))
                    }
                }
                .padding(4)
                if showCharge && block.current > 0.5 {
                    Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.white).padding(.bottom, 6)
                } else if block.chargeShut {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 6)
                }
            }
            .overlay(alignment: .top) {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 14, height: 4).offset(y: -6)
            }
            .frame(height: 92)
            Text(block.name).font(.caption.weight(.bold)).foregroundStyle(isLowest ? Theme.warn : .white)
            Text(block.soc.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f%%", block.soc) : String(format: "%.1f%%", block.soc))
                .font(.caption2.weight(.semibold)).monospacedDigit()
            Text("\(block.gapMv)mV").font(.system(size: 10)).foregroundStyle(Theme.sub).monospacedDigit()
            Text("\(block.temps.max() ?? 0)°").font(.system(size: 10)).foregroundStyle(Theme.sub).monospacedDigit()
            if showCharge {
                Text(abs(block.current) < 0.2 ? "0A" : String(format: "%.1fA", block.current))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(block.current > 0.5 ? Theme.good : Theme.faint)
                if balancing {
                    Image(systemName: "waveform.path").font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension TimeInterval {
    var hms: String {
        let s = Int(self)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
