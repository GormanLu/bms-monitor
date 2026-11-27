import SwiftUI

// MARK: - 一趟骑行的电池分析：骑的时候每来一帧就记一下，结束时算好存进骑行记录
struct RideAnalysis: Codable {
    var maxDisA: Double           // 电池最大放电电流（A）
    var maxRegenA: Double         // 最大回充电流（A）
    var peakW: Double             // 电池峰值输出功率
    var regenWh: Double           // 回充收回来的电
    var rampS: Double?            // 起步：从不到 5 A 到满电流（最大的 85%）一般要几秒（中位数）
    var fullS: Double             // 满电流一共持续了多少秒
    var longestFullS: Double      // 最长一次满电流持续多少秒
    var loadMinCell: Double?      // 电流 20 A 以上时，最低的一节电压
    var loadMaxGap: Int?          // 电流 20 A 以上时，整组最大压差 mV
    var maxTemp: Int?
    var cruise25A: Double?        // 22～28 km/h 时的平均电流
    var cruise30A: Double?        // 28～34 km/h 时的平均电流
}

final class RideAnalyzer {
    private struct P { let t: Double; let i: Double }
    private var pts: [P] = []
    private var t0 = Date()
    private var lastT: Double?
    private var a = RideAnalysis(maxDisA: 0, maxRegenA: 0, peakW: 0, regenWh: 0, rampS: nil, fullS: 0, longestFullS: 0,
                                 loadMinCell: nil, loadMaxGap: nil, maxTemp: nil, cruise25A: nil, cruise30A: nil)
    private var c25: [Double] = [], c30: [Double] = []

    func reset() {
        pts = []; t0 = Date(); lastT = nil; c25 = []; c30 = []
        a = RideAnalysis(maxDisA: 0, maxRegenA: 0, peakW: 0, regenWh: 0, rampS: nil, fullS: 0, longestFullS: 0,
                         loadMinCell: nil, loadMaxGap: nil, maxTemp: nil, cruise25A: nil, cruise30A: nil)
    }

    /// i：这一帧的电流（放电为负），v：整组电压，cells：各节电压，speed：现在的车速
    func feed(i: Double, v: Double?, cells: [Double], temps: [Int], speed: Double?) {
        let t = Date().timeIntervalSince(t0)
        let dt = lastT.map { min(t - $0, 3) } ?? 0
        lastT = t
        pts.append(P(t: t, i: i))
        a.maxDisA = max(a.maxDisA, -i)
        a.maxRegenA = max(a.maxRegenA, i)
        if let v {
            a.peakW = max(a.peakW, -i * v)
            if i > 0.5 { a.regenWh += i * v * dt / 3600 }
        }
        if -i >= 20, let lo = cells.min(), let hi = cells.max() {
            a.loadMinCell = min(a.loadMinCell ?? 9, lo)
            a.loadMaxGap = max(a.loadMaxGap ?? 0, Int(((hi - lo) * 1000).rounded()))
        }
        if let tm = temps.max() { a.maxTemp = max(a.maxTemp ?? -99, tm) }
        if let s = speed, i < -0.6 {
            if s >= 22 && s < 28 { c25.append(-i) } else if s >= 28 && s < 34 { c30.append(-i) }
        }
    }

    func result() -> RideAnalysis? {
        guard pts.count >= 20 else { return nil }
        var r = a
        let full = a.maxDisA * 0.85
        if a.maxDisA >= 10 {
            var ramps: [Double] = [], start: Double?
            var runStart: Double?, runLast: Double?
            for (k, p) in pts.enumerated() {
                if -p.i < 5 { start = p.t }
                else if -p.i >= full, let s = start { ramps.append(p.t - s); start = nil }
                if -p.i >= full {
                    if k + 1 < pts.count { r.fullS += min(pts[k + 1].t - p.t, 3) }
                    if runStart == nil { runStart = p.t }
                    runLast = p.t
                } else if -p.i < full * 0.7, let rs = runStart, let rl = runLast {
                    r.longestFullS = max(r.longestFullS, rl - rs); runStart = nil
                }
            }
            if let rs = runStart, let rl = runLast { r.longestFullS = max(r.longestFullS, rl - rs) }
            if !ramps.isEmpty { r.rampS = ramps.sorted()[ramps.count / 2] }
        }
        if c25.count >= 10 { r.cruise25A = c25.reduce(0, +) / Double(c25.count) }
        if c30.count >= 10 { r.cruise30A = c30.reduce(0, +) / Double(c30.count) }
        return r
    }
}

// MARK: - 把数翻译成人话：哪些正常，哪些要留意
func rideHints(_ trip: Trip, others: [Trip]) -> [(String, Color)] {
    guard let a = trip.ana else { return [] }
    var h: [(String, Color)] = []
    if a.maxDisA > 60 {
        h.append((String(format: "电池最大放电 %.0f A，接近保护板的 72 A 上限，控制器限流别再往上调了。", a.maxDisA), Theme.bad))
    } else if a.maxDisA >= 10 {
        h.append((String(format: "电池最大放电 %.0f A，控制器限流大约就在这里（电池这边量到的一般比控制器上设的数高一两安）。", a.maxDisA), Theme.sub))
    }
    if let r = a.rampS { h.append((String(format: "起步大约 %.0f 秒电流就到顶%@。", r, r <= 1.5 ? "，起步很猛" : r >= 5 ? "，起步比较柔" : ""), Theme.sub)) }
    if a.maxRegenA < 3 {
        h.append(("几乎没有回充（最多 \(String(format: "%.1f", a.maxRegenA)) A）：控制器的电子刹车回充是关着的，或者很弱。", Theme.sub))
    } else {
        let pct = trip.energyWh > 1 ? a.regenWh / trip.energyWh * 100 : 0
        h.append((String(format: "回充最大 %.0f A，一共收回 %.0f Wh（约占用电的 %.0f%%）。", a.maxRegenA, a.regenWh, pct), Theme.good))
        if a.maxRegenA > 40 { h.append(("回充电流很大，刹车会很冲，满电时也会让电池吃不消，可以把电子刹车调小。", Theme.warn)) }
    }
    if let c = a.loadMinCell {
        if c < 2.9 { h.append((String(format: "大电流时最低一节掉到 %.2f V，电快没了，少拧到底，尽快充电。", c), Theme.bad)) }
        else if c < 3.0 { h.append((String(format: "大电流时最低一节 %.2f V，偏低，电量低时别猛拧。", c), Theme.warn)) }
        else { h.append((String(format: "大电流时最低一节 %.2f V，正常。", c), Theme.good)) }
    }
    if let g = a.loadMaxGap {
        h.append(g >= 250 ? ("大电流时压差到过 \(g) mV，偏大，留意是不是总是同一块拖后腿。", Theme.warn)
                          : ("大电流时压差最大 \(g) mV。骑车时电流大，压差本来就比停着时大，这个数正常。", Theme.sub))
    }
    if let t = a.maxTemp, t >= 45 { h.append(("电池最高到过 \(t) °C，偏热，停下来歇一歇。", Theme.warn)) }
    if let w = trip.whPerKm {
        let ws = others.filter { $0.id != trip.id }.compactMap(\.whPerKm).sorted()
        if ws.count >= 3 {
            let med = ws[ws.count / 2]
            let d = (w - med) / med * 100
            if abs(d) >= 15 {
                h.append((String(format: "每公里 %.0f Wh，比你平时（%.0f）%@ %.0f%%。短途多停车、开得快、逆风、载人都会让它变高。", w, med, d > 0 ? "多" : "少", abs(d)), d > 0 ? Theme.warn : Theme.good))
            } else {
                h.append((String(format: "每公里 %.0f Wh，和你平时（%.0f）差不多。", w, med), Theme.sub))
            }
        }
    }
    if let e = elevationNote(trip) { h.append(e) }
    return h
}

/// 坡度对耗电的影响：车和人按约 250 kg、电机加控制器效率按 75% 估
/// 净上坡要多花 m·g·h / 效率 的电；净下坡等于白捡这么多（这车回充很弱，下坡省下的是"不用拧电门"的那部分）
let rideMassKg = 250.0
func elevationWh(_ netM: Double) -> Double { rideMassKg * 9.81 * netM / 3600 / 0.75 }

/// 按平路折算的每公里耗电：把净高差那部分电加回去或扣掉
func flatWhPerKm(_ trip: Trip) -> Double? {
    guard let up = trip.climbM, let down = trip.descentM, trip.km >= 0.5, trip.energyWh > 1 else { return nil }
    return max(0, trip.energyWh - elevationWh(up - down)) / trip.km
}

func elevationNote(_ trip: Trip) -> (String, Color)? {
    guard let up = trip.climbM, let down = trip.descentM else { return nil }
    let net = up - down
    var s = String(format: "爬升 %.0f m、下坡 %.0f m，", up, down)
    if abs(net) < 3 {
        s += "起点终点差不多一样高，坡度对耗电基本没影响。"
    } else {
        s += String(format: "净%@ %.0f m，大约%@ %.0f Wh", net > 0 ? "上坡" : "下坡", abs(net), net > 0 ? "多用" : "少用", abs(elevationWh(net)))
        if let f = flatWhPerKm(trip), let w = trip.whPerKm {
            s += String(format: "；按平路折算每公里约 %.0f Wh（实际 %.0f）", f, w)
        }
        s += "。车和人按 250 kg 估；同一条路一去一回，坡度的影响会抵消。"
    }
    return (s, Theme.sub)
}

// MARK: - 骑行详情里的分析卡片
struct RideAnalysisCard: View {
    let trip: Trip
    @EnvironmentObject var trips: TripStore
    @State private var editing = false
    @State private var tagText = ""

    var body: some View {
        // 写了参数以后要显示新的，所以从记录里重新取这一趟
        let trip = trips.trips.first { $0.id == self.trip.id } ?? self.trip
        GlassCard(title: "电池分析", icon: "waveform.path.ecg.rectangle") {
            if let a = trip.ana {
                Grid(horizontalSpacing: 10, verticalSpacing: 12) {
                    GridRow {
                        StatTile(label: "最大放电", value: String(format: "%.0f", a.maxDisA), unit: "A")
                        StatTile(label: "峰值功率", value: String(format: "%.0f", a.peakW), unit: "W")
                        StatTile(label: "起步到满电流", value: a.rampS.map { String(format: "%.0f", $0) } ?? "--", unit: "秒")
                    }
                    GridRow {
                        StatTile(label: "最大回充", value: String(format: "%.1f", a.maxRegenA), unit: "A")
                        StatTile(label: "带载最低一节", value: a.loadMinCell.map { String(format: "%.2f", $0) } ?? "--", unit: "V")
                        StatTile(label: "带载压差", value: a.loadMaxGap.map { "\($0)" } ?? "--", unit: "mV")
                    }
                    GridRow {
                        StatTile(label: "25 km/h 电流", value: a.cruise25A.map { String(format: "%.1f", $0) } ?? "--", unit: "A")
                        StatTile(label: "30 km/h 电流", value: a.cruise30A.map { String(format: "%.1f", $0) } ?? "--", unit: "A")
                        StatTile(label: "满电流共", value: String(format: "%.0f", a.fullS), unit: "秒")
                    }
                }
                ForEach(Array(rideHints(trip, others: trips.trips).enumerated()), id: \.offset) { _, x in
                    Label { Text(x.0).font(.caption) } icon: { Circle().fill(x.1).frame(width: 7, height: 7) }
                        .foregroundStyle(x.1 == Theme.sub ? .white : x.1)
                }
            } else {
                Text("这一趟是第 11 版以前记的，没有这些数。").font(.caption).foregroundStyle(Theme.sub)
            }
            Button { tagText = trip.tag ?? ""; editing = true } label: {
                Label(trip.tag.map { "参数：" + $0 } ?? "记一下这趟用的控制器参数", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered).tint(Theme.accent)
        }
        .alert("这趟用的什么参数", isPresented: $editing) {
            TextField("比如：限流 30A 三档 120%", text: $tagText)
            Button("保存") { trips.setTag(trip.id, tagText) }
            Button("取消", role: .cancel) {}
        } message: { Text("写一样的文字，就会在\"骑行分析\"里归成一组，方便比较。") }
    }
}

// MARK: - 骑行分析页：按参数分组比较
struct RideCompareView: View {
    @EnvironmentObject var trips: TripStore
    @State private var editing: Trip?
    @State private var tagText = ""

    private var analysed: [Trip] { trips.trips.filter { $0.ana != nil } }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section(footer: Text("每趟骑完，app 会自动算出电池这边看到的数。在下面点一趟，写上当时控制器的参数（比如\"限流 30A 三档 120%\"），写一样的文字就会归成一组，上面的表会按组算平均值。电流、功率都是电池这边量的，比控制器上设的数略高。")) {
                    if analysed.isEmpty {
                        Text("还没有分析过的骑行。装上第 10 版后骑一趟，这里就有了。").font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                if !analysed.isEmpty {
                    Section(header: Text("按参数比较")) {
                        ForEach(groups, id: \.0) { g in groupRow(g.0, g.1) }
                    }
                    .listRowBackground(Theme.card)
                    Section(header: Text("每一趟（点一下写参数）")) {
                        ForEach(analysed) { t in
                            Button { tagText = t.tag ?? ""; editing = t } label: { tripRow(t) }
                                .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("骑行分析")
        .navigationBarTitleDisplayMode(.inline)
        .alert("这趟用的什么参数", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("比如：限流 30A 三档 120%", text: $tagText)
            Button("保存") { if let t = editing { trips.setTag(t.id, tagText) }; editing = nil }
            Button("取消", role: .cancel) { editing = nil }
        }
    }

    private var groups: [(String, [Trip])] {
        var d: [String: [Trip]] = [:]
        for t in analysed { d[t.tag ?? "没写参数", default: []].append(t) }
        return d.sorted { ($0.value.first?.start ?? .distantPast) > ($1.value.first?.start ?? .distantPast) }
    }

    private func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
    private func f(_ x: Double?, _ fmt: String) -> String { x.map { String(format: fmt, $0) } ?? "--" }

    private func groupRow(_ name: String, _ ts: [Trip]) -> some View {
        let km = ts.reduce(0) { $0 + $1.km }, wh = ts.reduce(0) { $0 + $1.energyWh }
        let an = ts.compactMap(\.ana)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%d 趟 · %.1f km", ts.count, km)).font(.caption).foregroundStyle(Theme.sub)
            }
            HStack {
                StatTile(label: "每公里", value: km >= 0.5 ? String(format: "%.0f", wh / km) : "--", unit: "Wh")
                StatTile(label: "最大放电", value: f(avg(an.map(\.maxDisA)), "%.0f"), unit: "A")
                StatTile(label: "峰值功率", value: f(avg(an.map(\.peakW)), "%.0f"), unit: "W")
            }
            HStack {
                StatTile(label: "起步", value: f(avg(an.compactMap(\.rampS)), "%.1f"), unit: "秒")
                StatTile(label: "回充", value: f(avg(an.map(\.maxRegenA)), "%.1f"), unit: "A")
                StatTile(label: "25 km/h", value: f(avg(an.compactMap(\.cruise25A)), "%.1f"), unit: "A")
            }
        }
        .padding(.vertical, 4)
    }

    private func tripRow(_ t: Trip) -> some View {
        let a = t.ana!
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(t.start.formatted(.dateTime.month().day().hour().minute())).font(.subheadline.weight(.semibold))
                Spacer()
                Text(t.tag ?? "点这里写参数").font(.caption).foregroundStyle(t.tag == nil ? Theme.accent : Theme.sub)
            }
            Text(String(format: "%.1f km · %@ Wh/km · 最大 %.0f A · %.0f W · 起步 %@ 秒 · 回充 %.1f A", t.km,
                        t.whPerKm.map { String(format: "%.0f", $0) } ?? "--", a.maxDisA, a.peakW,
                        a.rampS.map { String(format: "%.0f", $0) } ?? "--", a.maxRegenA))
                .font(.caption).foregroundStyle(Theme.sub).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
