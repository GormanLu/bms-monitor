import SwiftUI
import Charts
import MapKit

// MARK: - 车把模式：手机装在车把上，只留最大的几个数
struct HandlebarView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var ride: RideTracker
    @EnvironmentObject var nav: NavManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let v = ride.freshSpeed
                let over = Pref.speedAlertOn && (v ?? 0) > Pref.speedLimit
                VStack(spacing: 10) {
                    if nav.active {
                        HStack(spacing: 10) {
                            Image(systemName: navIcon(for: nav.nextText)).font(.system(size: 44, weight: .bold))
                            VStack(alignment: .leading) {
                                Text(nav.nextDist >= 1000 ? String(format: "%.1f 公里", nav.nextDist / 1000) : "\(Int(nav.nextDist)) 米")
                                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                                Text(nav.nextText).font(.title3).lineLimit(1).foregroundStyle(Theme.sub)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.accent.opacity(0.3)))
                    }
                    Spacer()
                    Text(v.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: 190, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(over ? Theme.bad : .white)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("km/h").font(.title2).foregroundStyle(Theme.sub)
                    Spacer()
                    HStack {
                        big(m.lowest.map { "\(Int($0.soc))" } ?? "--", "%", "电量", Theme.soc(m.lowest?.soc ?? 100))
                        big(m.rangeKm.map { "\(Int($0))" } ?? "--", "km", "续航", .white)
                        big(String(format: "%.0f", abs(m.power ?? 0)), "W", (m.power ?? 0) < 0 ? "回充" : "功率", (m.power ?? 0) > 1500 ? Theme.bad : .white)
                    }
                    HStack {
                        big(String(format: "%.1f", ride.distM / 1000), "km", "里程", .white)
                        big((ride.startedAt.map { Date().timeIntervalSince($0) } ?? 0).hms, "", "用时", .white)
                        big(m.tempRange.map { "\($0.1)" } ?? "--", "°", "温度", (m.tempRange?.1 ?? 0) >= 50 ? Theme.bad : .white)
                    }
                }
                .padding(18)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(12).background(Circle().fill(Color.white.opacity(0.12)))
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = ride.on }
    }

    private func big(_ v: String, _ unit: String, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(unit).font(.caption).foregroundStyle(Theme.sub)
            }
            Text(label).font(.caption).foregroundStyle(Theme.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - 摔车提醒：30 秒倒计时，没点"我没事"就提示打电话（要你自己点，app 不会自动打）
struct CrashAlertView: View {
    @EnvironmentObject var m: AppModel
    @State private var left = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.bad.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 70))
                Text("检测到剧烈撞击").font(.largeTitle.weight(.bold))
                Text("你还好吗？").font(.title2)
                if left > 0 {
                    Text("\(left)").font(.system(size: 80, weight: .heavy, design: .rounded)).monospacedDigit()
                } else {
                    Text("没有回应").font(.title3.weight(.semibold))
                }
                Button { m.crashAlert = false; LogStore.shared.log("摔车提醒：点了我没事") } label: {
                    Text("我没事").font(.title2.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Capsule().fill(.white)).foregroundStyle(Theme.bad)
                }
                let phone = Pref.sosPhone.filter { $0.isNumber || $0 == "+" }
                if !phone.isEmpty, let url = URL(string: "tel://" + phone) {
                    Link(destination: url) {
                        Label("打电话给紧急联系人", systemImage: "phone.fill").font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Capsule().stroke(.white, lineWidth: 2))
                    }
                }
                if let url = URL(string: "tel://120") {
                    Link(destination: url) { Label("打 120", systemImage: "cross.case.fill").font(.headline) }
                }
            }
            .foregroundStyle(.white)
            .padding(30)
        }
        .onReceive(timer) { _ in
            guard left > 0 else { return }
            left -= 1
            if left == 0 {
                Speaker.shared.say("没有回应。需要帮助的话，点屏幕上的按钮打电话。")
                Notifier.shared.postNow("检测到摔车", "30 秒没有回应。需要帮助就打开 app 打电话。")
            }
        }
    }
}

// MARK: - 保养
struct MaintCard: View {
    @EnvironmentObject var maint: MaintStore
    @EnvironmentObject var trips: TripStore
    var body: some View {
        let odo = maint.odo(trips.trips)
        let sorted = maint.items.map { ($0, maint.status($0, odo: odo)) }.sorted { $0.1.2 > $1.1.2 }
        NavigationLink { MaintView() } label: {
            GlassCard(title: String(format: "保养 · 总里程 %.0f km", odo), icon: "wrench.and.screwdriver.fill") {
                ForEach(sorted.prefix(2), id: \.0.id) { it, s in
                    HStack {
                        Image(systemName: it.icon).foregroundStyle(s.0 ? Theme.bad : Theme.sub).frame(width: 22)
                        Text(it.name).font(.subheadline)
                        Spacer()
                        Text(s.1).font(.caption).foregroundStyle(s.0 ? Theme.bad : Theme.sub)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MaintView: View {
    @EnvironmentObject var maint: MaintStore
    @EnvironmentObject var trips: TripStore
    @State private var adding = false
    @State private var newName = ""
    @State private var newKm = ""
    @State private var newDays = ""

    var body: some View {
        let odo = maint.odo(trips.trips)
        ZStack {
            AppBackground()
            List {
                Section(footer: Text("总里程 = 下面填的起始里程 + app 记录到的骑行里程。买车到装 app 之间骑的，看仪表上的总里程填进去。")) {
                    HStack {
                        Text("装 app 之前已经骑了")
                        Spacer()
                        TextField("0", value: $maint.odoBase, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("km")
                    }
                }
                .listRowBackground(Theme.card)
                Section(header: Text("项目（做完了点\"做了\"）").foregroundStyle(Theme.sub)) {
                    ForEach(maint.items) { it in
                        let s = maint.status(it, odo: odo)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: it.icon).foregroundStyle(s.0 ? Theme.bad : Theme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name).font(.subheadline.weight(.semibold))
                                    Text(rule(it) + " · 上次 " + it.lastDate.formatted(.dateTime.month().day())).font(.caption2).foregroundStyle(Theme.faint)
                                }
                                Spacer()
                                Button("做了") { maint.done(it.id, odo: odo) }.buttonStyle(.bordered).tint(s.0 ? Theme.bad : .white)
                            }
                            ProgressView(value: s.2).tint(s.0 ? Theme.bad : s.2 > 0.8 ? Theme.warn : Theme.good)
                            Text(s.1).font(.caption).foregroundStyle(s.0 ? Theme.bad : Theme.sub)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { maint.items.remove(atOffsets: $0); maint.save() }
                }
                .listRowBackground(Theme.card)
                Section {
                    if adding {
                        TextField("名称，比如：检查链条", text: $newName)
                        TextField("每多少公里（可空）", text: $newKm).keyboardType(.numberPad)
                        TextField("每多少天（可空）", text: $newDays).keyboardType(.numberPad)
                        Button("添加") {
                            let k = Double(newKm), d = Double(newDays)
                            guard !newName.isEmpty, k != nil || d != nil else { return }
                            maint.items.append(MaintItem(name: newName, icon: "wrench.fill", everyKm: k, everyDays: d, lastKm: odo, lastDate: Date()))
                            maint.save(); adding = false; newName = ""; newKm = ""; newDays = ""
                        }
                    } else {
                        Button { adding = true } label: { Label("添加保养项目", systemImage: "plus") }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("保养提醒")
    }

    private func rule(_ i: MaintItem) -> String {
        [i.everyKm.map { String(format: "每 %.0f 公里", $0) }, i.everyDays.map { String(format: "每 %.0f 天", $0) }].compactMap { $0 }.joined(separator: "或")
    }
}

// MARK: - 本周目标 + 今日挑战
struct GoalCard: View {
    @EnvironmentObject var trips: TripStore
    @ObservedObject var ch = ChallengeStore.shared
    @AppStorage("goal.week") private var goal = 30.0

    var body: some View {
        let ws = weekStart()
        let km = trips.trips.filter { $0.start >= ws }.reduce(0) { $0 + $1.km }
        let todayKm = trips.trips.filter { Calendar.current.isDateInToday($0.start) }.reduce(0) { $0 + $1.km }
        GlassCard(title: "本周目标 · 今日挑战", icon: "target") {
            HStack(spacing: 16) {
                ZStack {
                    Ring(progress: km / max(goal, 1), color: km >= goal ? Theme.good : Theme.accent, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", km)).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                        Text(String(format: "/%.0f km", goal)).font(.system(size: 9)).foregroundStyle(Theme.sub)
                    }
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: ch.doneToday ? "checkmark.circle.fill" : ch.today.icon)
                            .foregroundStyle(ch.doneToday ? Theme.good : Theme.warn)
                        Text(ch.today.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(ch.doneToday ? "今天的挑战完成了，+\(ChallengeStore.pointsEach) 分" : String(format: "今天骑了 %.1f km · 完成得 %d 分", todayKm, ChallengeStore.pointsEach))
                        .font(.caption).foregroundStyle(Theme.sub)
                    Text(km >= goal ? "本周目标达成！" : String(format: "本周还差 %.1f km", goal - km))
                        .font(.caption).foregroundStyle(km >= goal ? Theme.good : Theme.sub)
                    if ch.streak > 1 { Text("挑战连续完成 \(ch.streak) 天").font(.caption2).foregroundStyle(Theme.warn) }
                }
            }
        }
    }
}

// MARK: - 省钱账本 + 减碳
struct SavingsCard: View {
    @EnvironmentObject var trips: TripStore
    var body: some View {
        let s = savings(trips.trips, price: trips.price)
        GlassCard(title: "省钱账本 · 减碳", icon: "yensign.circle.fill") {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f", max(0, s.fuel - s.elec))).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.good)
                Text("元").foregroundStyle(Theme.sub)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("比开车省下的油钱").font(.caption).foregroundStyle(Theme.sub)
                    Text(String(format: "电费一共 %.2f 元", s.elec)).font(.caption2).foregroundStyle(Theme.faint)
                }
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    StatTile(label: "开车要花", value: String(format: "%.0f", s.fuel), unit: "元")
                    StatTile(label: "打车要花", value: String(format: "%.0f", s.taxi), unit: "元")
                    StatTile(label: "少排二氧化碳", value: String(format: "%.1f", s.co2), unit: "kg", color: Theme.good)
                }
            }
            Text(String(format: "相当于 %.2f 棵树一年吸收的量。开车按百公里 %.1f 升油、油价 %.2f 元，打车按每公里 %.1f 元算，可以在设置里改。", s.trees, Pref.fuelPer100, Pref.fuelPrice, Pref.taxiPerKm))
                .font(.caption2).foregroundStyle(Theme.faint)
        }
    }
}

// MARK: - 驾驶评分卡片
struct ScoreCard: View {
    let s: DriveScore
    var body: some View {
        GlassCard(title: "驾驶评分", icon: "star.circle.fill") {
            HStack(spacing: 16) {
                ZStack {
                    Ring(progress: Double(s.total) / 100, color: color(s.total), lineWidth: 9)
                    Text("\(s.total)").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                }
                .frame(width: 80, height: 80)
                VStack(spacing: 6) {
                    bar("起步", s.start); bar("刹车", s.brake); bar("车速", s.speed); bar("省电", s.eco)
                }
            }
            ForEach(s.tips, id: \.self) { Label($0, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(Theme.sub) }
        }
    }
    private func color(_ v: Int) -> Color { v >= 85 ? Theme.good : v >= 70 ? Theme.warn : Theme.bad }
    private func bar(_ n: String, _ v: Int) -> some View {
        HStack(spacing: 6) {
            Text(n).font(.caption2).foregroundStyle(Theme.sub).frame(width: 28, alignment: .leading)
            ProgressView(value: Double(v), total: 100).tint(color(v))
            Text("\(v)").font(.caption2).monospacedDigit().frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - 同一条路对比：起点和终点都在 200 米以内的算同一条路
func sameRoute(_ t: Trip, in all: [Trip]) -> [Trip] {
    guard let a = t.track?.first, let b = t.track?.last else { return [] }
    func near(_ p: TrackPoint?, _ q: TrackPoint) -> Bool {
        guard let p else { return false }
        return CLLocation(latitude: p.lat, longitude: p.lon).distance(from: CLLocation(latitude: q.lat, longitude: q.lon)) < 200
    }
    return all.filter { o in
        o.id != t.id && near(o.track?.first, a) && near(o.track?.last, b) && abs(o.km - t.km) / max(t.km, 0.1) < 0.3
    }
}

struct SameRouteCard: View {
    let trip: Trip
    let others: [Trip]
    var body: some View {
        let all = ([trip] + others).sorted { $0.duration < $1.duration }
        GlassCard(title: "同一条路骑了 \(all.count) 次", icon: "arrow.triangle.swap") {
            ForEach(all.prefix(8)) { t in
                HStack {
                    if t.id == all.first?.id { Image(systemName: "trophy.fill").foregroundStyle(Theme.warn) }
                    Text(t.start.formatted(.dateTime.month().day().hour().minute())).font(.caption.weight(t.id == trip.id ? .bold : .regular))
                        .foregroundStyle(t.id == trip.id ? Theme.accent : .white)
                    Spacer()
                    Text(t.duration.hms + (t.avgMovingKmh.map { String(format: " · %.0f km/h", $0) } ?? "") + (t.whPerKm.map { String(format: " · %.0f Wh/km", $0) } ?? ""))
                        .font(.caption).monospacedDigit().foregroundStyle(Theme.sub)
                }
            }
            if let best = all.first, best.id != trip.id {
                Text("这次比最快的那次慢了 " + (trip.duration - best.duration).hms).font(.caption2).foregroundStyle(Theme.faint)
            } else {
                Text("这次是最快的一次").font(.caption2).foregroundStyle(Theme.good)
            }
        }
    }
}

// MARK: - 一趟的高度、坡度、五块电压
struct TripExtraCharts: View {
    let trip: Trip
    var body: some View {
        let alt = trip.samples.filter { $0.a != nil }
        if alt.count > 3 {
            GlassCard(title: "高度变化（米）", icon: "mountain.2.fill") {
                HStack {
                    StatTile(label: "累计爬升", value: String(format: "%.0f", trip.climbM ?? 0), unit: "m")
                    StatTile(label: "累计下坡", value: String(format: "%.0f", trip.descentM ?? 0), unit: "m")
                    StatTile(label: "最陡一段", value: maxGrade(alt).map { String(format: "%.0f", $0) } ?? "--", unit: "%")
                }
                Chart(alt.indices, id: \.self) { i in
                    AreaMark(x: .value("分钟", alt[i].t / 60), y: .value("高度", alt[i].a ?? 0))
                        .foregroundStyle(LinearGradient(colors: [Theme.good.opacity(0.35), Theme.good.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("分钟", alt[i].t / 60), y: .value("高度", alt[i].a ?? 0)).foregroundStyle(Theme.good)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
                .frame(height: 130)
                Text("用手机气压计测的相对高度，以出发点为 0。最陡一段按 60 米以上的路段算，有几个百分点的误差。").font(.caption2).foregroundStyle(Theme.faint)
            }
        }
        let bv = trip.samples.filter { ($0.bv?.count ?? 0) >= 2 }
        if bv.count > 3, let names = trip.blockNames {
            let pts: [(t: Double, v: Double, n: String)] = bv.flatMap { s in
                (s.bv ?? []).enumerated().compactMap { i, v in i < names.count ? (s.t / 60, v, names[i]) : nil }
            }
            GlassCard(title: "五块电池的平均每节电压（V）", icon: "chart.xyaxis.line") {
                Chart(pts.indices, id: \.self) { i in
                    LineMark(x: .value("分钟", pts[i].t), y: .value("电压", pts[i].v))
                        .foregroundStyle(by: .value("模块", pts[i].n))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartForegroundStyleScale(range: [Theme.accent, Theme.good, Theme.warn, Color.purple, Theme.bad])
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(Theme.faint) } }
                .frame(height: 170)
                Text("哪条线在大电流时掉得最多，就是内阻最大、最弱的那块。").font(.caption2).foregroundStyle(Theme.faint)
            }
        }
    }

    private func maxGrade(_ s: [TripSample]) -> Double? {
        var best: Double?
        var j = 0, dist = 0.0
        var d: [Double] = [0]                         // 每个点距出发多少米（按车速积分）
        for i in 1..<s.count { dist += (s[i].v / 3.6) * (s[i].t - s[i - 1].t); d.append(dist) }
        for i in 0..<s.count {
            while j < s.count && d[j] - d[i] < 60 { j += 1 }
            guard j < s.count, d[j] - d[i] < 200, let a = s[i].a, let b = s[j].a else { continue }
            let g = (b - a) / (d[j] - d[i]) * 100
            if g > (best ?? 0) { best = g }
        }
        return best
    }
}

// MARK: - 骑行海报：地图截图 + 轨迹 + 数据
struct PosterView: View {
    let trip: Trip
    @EnvironmentObject var trips: TripStore
    @AppStorage("map.gcj") private var gcj = true
    @State private var mapImg: UIImage?
    @State private var poster: Image?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    content.frame(width: 340)
                    if let poster {
                        ShareLink(item: poster, preview: SharePreview("骑行海报", image: poster)) {
                            Label("分享海报", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    } else { ProgressView("正在生成…") }
                    Text("海报里的地图只在这台手机上生成；分享出去别人能看到你的路线，介意的话别发到公开的地方。")
                        .font(.caption2).foregroundStyle(Theme.faint)
                }
                .padding(16)
            }
        }
        .navigationTitle("骑行海报")
        .task { await snapshot() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let mapImg {
                Image(uiImage: mapImg).resizable().scaledToFill().frame(height: 260).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(Theme.card).frame(height: 260)
                    .overlay(TrackShape(track: trip.track ?? []).stroke(Theme.accent, lineWidth: 3).padding(30))
            }
            Text(trip.start.formatted(.dateTime.year().month().day().hour().minute())).font(.caption).foregroundStyle(Theme.sub)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", trip.km)).font(.system(size: 54, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("公里").foregroundStyle(Theme.sub)
                Spacer()
                if let s = trip.score {
                    VStack(spacing: 0) {
                        Text("\(s.total)").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(Theme.warn)
                        Text("评分").font(.caption2).foregroundStyle(Theme.sub)
                    }
                }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    StatTile(label: "用时", value: trip.duration.hms)
                    StatTile(label: "平均", value: trip.avgMovingKmh.map { String(format: "%.0f", $0) } ?? "--", unit: "km/h")
                    StatTile(label: "最高", value: String(format: "%.0f", trip.maxKmh), unit: "km/h")
                }
                GridRow {
                    StatTile(label: "用电", value: String(format: "%.0f", trip.energyWh), unit: "Wh")
                    StatTile(label: "电费", value: String(format: "%.2f", trip.energyWh / 1000 / 0.85 * trips.price), unit: "元")
                    StatTile(label: "爬升", value: trip.climbM.map { String(format: "%.0f", $0) } ?? "--", unit: "m")
                }
            }
            HStack {
                Image(systemName: "bolt.car.fill").foregroundStyle(Theme.accent)
                Text("三轮车电池监控").font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "比开车省 %.1f 元", max(0, trip.km / 100 * Pref.fuelPer100 * Pref.fuelPrice - trip.energyWh / 1000 / 0.85 * trips.price)))
                    .font(.caption).foregroundStyle(Theme.good)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.14, blue: 0.30), Color(red: 0.04, green: 0.05, blue: 0.10)], startPoint: .top, endPoint: .bottom)))
        .foregroundStyle(.white)
    }

    @MainActor private func snapshot() async {
        if let tr = trip.track, tr.count >= 2 {
            let cs = tr.map { gcj ? ChinaCoord.toGCJ($0.lat, $0.lon) : CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let rect = MKPolyline(coordinates: cs, count: cs.count).boundingMapRect
            let o = MKMapSnapshotter.Options()
            o.mapRect = rect.insetBy(dx: -rect.size.width * 0.2 - 300, dy: -rect.size.height * 0.2 - 300)
            o.size = CGSize(width: 340, height: 260)
            o.scale = 3
            o.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            o.pointOfInterestFilter = .excludingAll
            if let snap = try? await MKMapSnapshotter(options: o).start() {
                let img = UIGraphicsImageRenderer(size: o.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }()).image { ctx in
                    snap.image.draw(at: .zero)
                    let g = ctx.cgContext
                    g.setLineWidth(4); g.setLineCap(.round); g.setLineJoin(.round)
                    for i in 1..<cs.count {
                        let a = snap.point(for: cs[i - 1]), b = snap.point(for: cs[i])
                        g.setStrokeColor(speedColor(tr[i].v).cgColor)
                        g.move(to: a); g.addLine(to: b); g.strokePath()
                    }
                    for (c, col) in [(cs.first!, UIColor.systemGreen), (cs.last!, UIColor.systemRed)] {
                        let p = snap.point(for: c)
                        g.setFillColor(col.cgColor); g.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                        g.setStrokeColor(UIColor.white.cgColor); g.setLineWidth(2); g.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                    }
                }
                mapImg = img
            }
        }
        let r = ImageRenderer(content: content.frame(width: 340).padding(10).background(Color.black).environment(\.colorScheme, .dark))
        r.scale = 3
        poster = r.uiImage.map { Image(uiImage: $0) }
    }
}

// MARK: - 电池体检报告（生成 PDF）
struct BatteryReportView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var stats: BatteryStats
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var charges: ChargeStore
    @State private var pdf: URL?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    BatteryReportPage(blocks: blocks, stats: stats, health: health.records, charges: charges.sessions, at: Date())
                        .frame(width: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if let pdf {
                        ShareLink(item: pdf) { Label("分享 PDF（可发给卖家或修车师傅）", systemImage: "doc.richtext") .frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    if blocks.count < 5 {
                        Text("现在没收齐五块的数据，报告里的单块数据是最后一次收到的。连上电池再打开这页会更准。").font(.caption).foregroundStyle(Theme.warn)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("电池体检报告")
        .task { pdf = makePDF() }
    }

    private var blocks: [BlockData] { m.blocks.values.sorted { $0.id < $1.id } }

    @MainActor private func makePDF() -> URL? {
        let page = BatteryReportPage(blocks: blocks, stats: stats, health: health.records, charges: charges.sessions, at: Date())
            .frame(width: 595).environment(\.colorScheme, .light)
        let r = ImageRenderer(content: page)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("电池体检报告-\(f.string(from: Date())).pdf")
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
        }
        return url
    }
}

struct BatteryReportPage: View {
    let blocks: [BlockData]
    let stats: BatteryStats
    let health: [HealthRecord]
    let charges: [ChargeSession]
    let at: Date

    private let ink = Color(red: 0.1, green: 0.12, blue: 0.18)
    private let gray = Color(red: 0.45, green: 0.48, blue: 0.55)

    var body: some View {
        let cells = blocks.flatMap(\.cells)
        let gap = (cells.max() ?? 0) - (cells.min() ?? 0)
        let means = blocks.map { ($0.name, $0.cells.reduce(0, +) / Double(max($0.cells.count, 1))) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("电池体检报告").font(.title.weight(.bold))
                    Text("60V 60Ah 磷酸铁锂 · 5 块 × 4 串").font(.caption).foregroundStyle(gray)
                }
                Spacer()
                Text(at.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(gray)
            }
            Divider()
            HStack {
                kv("等效循环", String(format: "%.1f 次", stats.cycles))
                kv("估算健康度", String(format: "%.0f%%", stats.cycleHealth))
                kv("整组压差", cells.isEmpty ? "--" : String(format: "%.0f mV", gap * 1000))
                kv("温度", blocks.flatMap(\.temps).isEmpty ? "--" : "\(blocks.flatMap(\.temps).min()!)~\(blocks.flatMap(\.temps).max()!) °C")
            }
            Text("各块").font(.headline)
            VStack(spacing: 0) {
                row(["模块", "电量", "平均每节", "块内压差", "剩余/标称 Ah", "温度"], header: true)
                ForEach(blocks, id: \.id) { b in
                    row([b.name, String(format: "%.0f%%", b.soc), String(format: "%.3f V", b.cells.reduce(0, +) / Double(max(b.cells.count, 1))),
                         "\(b.gapMv) mV", String(format: "%.1f / %.0f", b.remainAh, b.nominalAh), "\(b.temps.max() ?? 0) °C"])
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(gray.opacity(0.4)))
            if let lo = means.min(by: { $0.1 < $1.1 }), means.count >= 2 {
                let others = means.filter { $0.0 != lo.0 }.map(\.1)
                let diff = (others.reduce(0, +) / Double(others.count) - lo.1) * 1000
                Text(String(format: "平均电压最低的是模块 %@，每节比其他块平均低 %.0f mV。", lo.0, diff)).font(.callout)
            }
            if !health.isEmpty {
                Text("最近的静置检查（放着不用时记的，最能看出电池一致性）").font(.headline)
                VStack(spacing: 0) {
                    row(["日期", "电量", "整组压差", "最低的一块", "低多少"], header: true)
                    ForEach(health.prefix(10)) { h in
                        row([h.date.formatted(.dateTime.month().day()), String(format: "%.0f%%", h.soc), "\(h.packGapMv) mV", h.lowName, "\(h.lowMv) mV"])
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(gray.opacity(0.4)))
            }
            if !charges.isEmpty {
                let full = charges.filter(\.complete)
                Text("充电").font(.headline)
                Text(String(format: "记录到 %d 次充电，其中 %d 次充到保护板自己停止。累计充入约 %.1f 度（电池这边量的）。", charges.count, full.count, charges.reduce(0) { $0 + $1.wh } / 1000))
                    .font(.callout)
                if let last = full.first, !last.stops.isEmpty {
                    Text("最近一次充满，各块停止进电的先后：" + last.stops.joined(separator: " → ")).font(.callout)
                }
            }
            Text("说明").font(.headline)
            Text("循环次数和健康度由 app 根据保护板报告的剩余容量自己累计：放出的电 ÷ 60 Ah = 等效满充满放次数，健康度按磷酸铁锂 2000 次剩 80% 估算，不是实测容量。保护板自己的循环计数（字节 22）目前读到 \(stats.bmsCycles.isEmpty ? "--" : stats.bmsCycles.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "、"))；卖家客服说一般五六次循环后才开始有数。")
                .font(.caption).foregroundStyle(gray)
        }
        .padding(28)
        .foregroundStyle(ink)
        .background(Color.white)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(gray)
            Text(v).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ cols: [String], header: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(cols.indices, id: \.self) { i in
                Text(cols[i]).font(header ? .caption.weight(.semibold) : .caption).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).padding(.horizontal, 6)
            }
        }
        .background(header ? gray.opacity(0.12) : Color.clear)
    }
}

// MARK: - 主题选择
struct ThemePicker: View {
    @EnvironmentObject var badges: BadgeStore
    @AppStorage("theme") private var theme = "blue"
    var body: some View {
        ForEach(ThemeKind.allCases) { k in
            let locked = badges.level.index < k.unlockLevel
            Button { if !locked { theme = k.rawValue } } label: {
                HStack {
                    Circle().fill(k.accent).frame(width: 18, height: 18)
                    Text(k.title).foregroundStyle(locked ? .secondary : .primary)
                    Spacer()
                    if locked { Label("Lv.\(k.unlockLevel) 解锁", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    else if theme == k.rawValue { Image(systemName: "checkmark").foregroundStyle(k.accent) }
                }
            }
            .disabled(locked)
        }
    }
}
