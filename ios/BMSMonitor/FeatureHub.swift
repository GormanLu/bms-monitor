import SwiftUI

// MARK: - 功能页：所有功能都摆在这里，每个都有一句话说明，点开就能用
struct FeatureHubView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var trips: TripStore
    @EnvironmentObject var badges: BadgeStore
    @EnvironmentObject var nav: NavManager
    @EnvironmentObject var parking: ParkingStore
    @EnvironmentObject var maint: MaintStore
    @State private var showSearch = false
    @State private var showBar = false
    @State private var showPerf = false

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("骑车时用") {
                            Button { if nav.active { m.tab = 1 } else { showSearch = true } } label: {
                                FeatureTile(icon: "location.magnifyingglass", color: Theme.accent, title: "导航",
                                            detail: nav.active ? "正在导航，点这里回仪表盘" : "搜地点，转弯前语音提醒，锁屏和灵动岛上也有箭头",
                                            badge: nav.active ? "导航中" : nil)
                            }
                            Button { showBar = true } label: {
                                FeatureTile(icon: "iphone.gen3", color: .blue, title: "车把模式",
                                            detail: "手机装在车把上用：超大车速，加电量、续航、压差")
                            }
                            Button { showPerf = true } label: {
                                FeatureTile(icon: "stopwatch", color: .orange, title: "加速测试",
                                            detail: "测 0 到 30 km/h 要几秒，和以前的成绩比",
                                            badge: m.perf.best30.map { String(format: "最好 %.1f 秒", $0) })
                            }
                            NavigationLink { RideCompareView() } label: {
                                FeatureTile(icon: "slider.horizontal.below.square.and.square.filled", color: .mint, title: "骑行分析 · 参数对比",
                                            detail: "每趟的电流、功率、起步、回充、耗电，按控制器参数分组比较")
                            }
                            Button { m.engineOn.toggle() } label: {
                                FeatureTile(icon: "speaker.wave.2.fill", color: .purple, title: "声浪",
                                            detail: "骑行时按车速和功率放模拟发动机声，点一下开关",
                                            badge: m.engineOn ? "已打开" : nil)
                            }
                            NavigationLink { ParkPage() } label: {
                                FeatureTile(icon: "parkingsign.circle.fill", color: Theme.good, title: "找车",
                                            detail: "结束骑行时自动记下停在哪，一键步行导航回去",
                                            badge: parking.spot.map { $0.t.formatted(.relative(presentation: .named)) })
                            }
                        }

                        section("电池") {
                            NavigationLink { BatteryReportView() } label: {
                                FeatureTile(icon: "doc.richtext.fill", color: Theme.accent, title: "电池体检报告",
                                            detail: "生成一份 PDF，可以发给卖家或售后看")
                            }
                            NavigationLink { BatteryLifeView() } label: {
                                FeatureTile(icon: "heart.text.square.fill", color: Theme.bad, title: "电池寿命",
                                            detail: "循环次数、健康度，怎么算的都写着")
                            }
                            NavigationLink { wrap("充电记录") { ChargeListView() } } label: {
                                FeatureTile(icon: "bolt.batteryblock.fill", color: Theme.good, title: "充电记录",
                                            detail: "每次充了多久、充进多少、哪块先停")
                            }
                            NavigationLink { wrap("电池健康曲线") { HealthView() } } label: {
                                FeatureTile(icon: "chart.xyaxis.line", color: .teal, title: "电池健康曲线",
                                            detail: "P 块比其他块低多少，看它是不是在变差")
                            }
                            NavigationLink { MaintView() } label: {
                                let due = maint.items.filter { maint.status($0, odo: maint.odo(trips.trips)).0 }.count
                                FeatureTile(icon: "wrench.and.screwdriver.fill", color: .gray, title: "保养提醒",
                                            detail: "胎压、刹车、齿轮油、接线柱，到时间或里程就提醒",
                                            badge: due > 0 ? "\(due) 项到期" : nil)
                            }
                        }

                        section("记录和成就") {
                            NavigationLink { ReportView() } label: {
                                FeatureTile(icon: "chart.bar.doc.horizontal.fill", color: Theme.accent, title: "月报 · 年报",
                                            detail: "这个月骑了多少、花了多少电费，能存成图片")
                            }
                            NavigationLink { BadgesView() } label: {
                                FeatureTile(icon: "medal.fill", color: Theme.warn, title: "徽章和等级",
                                            detail: "骑得越多解锁越多，升级还能换仪表颜色",
                                            badge: "Lv.\(badges.level.index)")
                            }
                            NavigationLink { scrollWrap("周目标 · 每日挑战") { GoalCard() } } label: {
                                FeatureTile(icon: "target", color: .pink, title: "周目标 · 每日挑战",
                                            detail: "每周骑多少公里，每天一个小挑战")
                            }
                            NavigationLink { scrollWrap("省钱账本") { SavingsCard() } } label: {
                                FeatureTile(icon: "yensign.circle.fill", color: Theme.good, title: "省钱账本",
                                            detail: "和开车、打车比省了多少钱、少排多少碳")
                            }
                            NavigationLink { HeatmapView() } label: {
                                FeatureTile(icon: "flame.fill", color: Theme.bad, title: "路线热力图",
                                            detail: "所有骑过的路叠在一张地图上")
                            }
                            if let t = trips.trips.first {
                                NavigationLink { PosterView(trip: t) } label: {
                                    FeatureTile(icon: "photo.artframe", color: .indigo, title: "骑行海报",
                                                detail: "把最近一趟做成带地图的图片。别的趟在\"记录\"里点开")
                                }
                            }
                            if let t = trips.trips.first(where: { ($0.track?.count ?? 0) >= 2 }) {
                                NavigationLink { ReplayView(trip: t) } label: {
                                    FeatureTile(icon: "play.circle.fill", color: .cyan, title: "骑行回放",
                                                detail: "在地图上重放最近一趟，看哪里快哪里慢")
                                }
                            }
                        }

                        section("个性化") {
                            NavigationLink { ThemePage() } label: {
                                FeatureTile(icon: "paintpalette.fill", color: Theme.accent, title: "仪表主题",
                                            detail: "换 app 的主色，升级解锁更多颜色")
                            }
                            Button { m.tab = 4 } label: {
                                FeatureTile(icon: "applewatch", color: .gray, title: "灵动岛 · 手表 · 提醒",
                                            detail: "灵动岛显示什么、手表震动、超速和自动记录，都在设置里")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("功能")
        }
        .sheet(isPresented: $showSearch) { NavSearchView() }
        .sheet(isPresented: $showPerf) { PerfTestView() }
        .fullScreenCover(isPresented: $showBar) { HandlebarView() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.sub)
            LazyVGrid(columns: cols, spacing: 12) { content() }
        }
    }

    private func wrap<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        ZStack { AppBackground(); content() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    private func scrollWrap<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        ZStack {
            AppBackground()
            ScrollView { content().padding(16) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 一个功能格子：图标、名字、一句话说明，右上角可以挂个小标签
struct FeatureTile: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.gradient))
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .foregroundStyle(.white)
                }
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.caption2).foregroundStyle(Theme.sub).multilineTextAlignment(.leading)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ParkPage: View {
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView { ParkCard().padding(16) }
        }
        .navigationTitle("找车")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemePage: View {
    var body: some View {
        Form {
            Section(footer: Text("在\"徽章和等级\"里升级，解锁更多颜色。")) { ThemePicker() }
        }
        .navigationTitle("仪表主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}
