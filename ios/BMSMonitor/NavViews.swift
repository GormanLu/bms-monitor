import SwiftUI
import MapKit

// MARK: 地图：显示路线和自己的位置
struct RouteMap: UIViewRepresentable {
    let route: MKRoute?
    var follow = false          // 导航时跟着自己走、按朝向转

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        m.showsUserLocation = true
        m.showsCompass = false
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        if context.coordinator.shown !== route {
            context.coordinator.shown = route
            m.removeOverlays(m.overlays)
            m.removeAnnotations(m.annotations.filter { !($0 is MKUserLocation) })
            if let r = route {
                m.addOverlay(r.polyline)
                if let last = r.polyline.coordinates.last {
                    let a = MKPointAnnotation(); a.coordinate = last; a.title = "目的地"
                    m.addAnnotation(a)
                }
                if !follow {
                    m.setVisibleMapRect(r.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30), animated: false)
                }
            }
        }
        if follow && m.userTrackingMode != .followWithHeading {
            m.setUserTrackingMode(.followWithHeading, animated: true)
            m.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 300, maxCenterCoordinateDistance: 2500), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var shown: MKRoute?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = UIColor(red: 0.33, green: 0.57, blue: 1.0, alpha: 0.95)
            r.lineWidth = 7
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
            v.markerTintColor = UIColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1)
            v.glyphImage = UIImage(systemName: "flag.checkered")
            return v
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&c, range: NSRange(location: 0, length: pointCount))
        return c
    }
}

// MARK: 导航时顶上的转弯提示
struct NavBanner: View {
    @EnvironmentObject var nav: NavManager
    @EnvironmentObject var ride: RideTracker
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: nav.nextIcon)
                .font(.system(size: 34, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(nav.nextDist >= 0 ? nav.dist(nav.nextDist) : "--")
                    .font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                Text(nav.nextText).font(.subheadline).lineLimit(2)
                Text(remaining).font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private var remaining: String {
        let v = max(ride.freshSpeed ?? 0, 12) / 3.6       // 停着或很慢时按 12 km/h 估
        let mins = Int((nav.remainingM / v / 60).rounded())
        return "剩 \(nav.km(nav.remainingM)) · 约 \(max(mins, 1)) 分钟 · \(nav.mode)路线"
    }
}

// MARK: 搜索目的地、看路线、查电量够不够
struct NavSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var favs: FavStore
    @EnvironmentObject var nav: NavManager
    @EnvironmentObject var ride: RideTracker
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var picked = false
    @State private var amapMsg = ""

    private let quick = ["充电站", "电动车维修", "超市", "公园", "医院"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if picked, let r = nav.route { preview(r) } else { searchList }
            }
            .navigationTitle(picked ? "路线" : "去哪儿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(picked ? "返回" : "取消") {
                        if picked { picked = false; if !nav.active { nav.route = nil } } else { dismiss() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var searchList: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
                TextField("搜地点：小区、商场、充电站…", text: $q)
                    .submitLabel(.search)
                    .onSubmit { nav.search(q, near: ride.lastLocation) }
                if nav.searching { ProgressView() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(quick, id: \.self) { w in
                        Button(w) { q = w; nav.search(w, near: ride.lastLocation) }
                            .buttonStyle(.bordered).tint(.white)
                    }
                }
            }
            if !favs.places.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(favs.places.enumerated()), id: \.element.id) { i, p in
                            Button { picked = true; nav.plan(to: p.item) } label: { Label(p.name, systemImage: "star.fill") }
                                .buttonStyle(.borderedProminent).tint(Theme.warn.opacity(0.8))
                                .contextMenu { Button("删除这个常去地点", role: .destructive) { favs.delete(at: IndexSet(integer: i)) } }
                        }
                    }
                }
                Text("常去地点：点一下直接规划路线，长按可以删除").font(.caption2).foregroundStyle(Theme.faint)
            }
            if !nav.message.isEmpty { Text(nav.message).font(.caption).foregroundStyle(Theme.warn) }
            List(nav.results, id: \.self) { item in
                Button {
                    picked = true
                    nav.plan(to: item)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Theme.bad)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "未命名").foregroundStyle(.white)
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                        Spacer()
                        if let here = ride.lastLocation, let c = item.placemark.location {
                            Text(nav.km(c.distance(from: here))).font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(16)
    }

    private func preview(_ r: MKRoute) -> some View {
        let km = r.distance / 1000
        let check = batteryCheck(km)
        return ScrollView {
            VStack(spacing: 14) {
                RouteMap(route: r)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                GlassCard(title: nav.destination?.name ?? "目的地", icon: "flag.checkered") {
                    HStack {
                        StatTile(label: "距离", value: String(format: "%.1f", km), unit: "km")
                        StatTile(label: "预计", value: "\(Int(r.distance / (15 / 3.6) / 60))", unit: "分钟")
                        StatTile(label: "路线", value: nav.mode)
                    }
                    Text("预计时间按 15 km/h 算").font(.caption2).foregroundStyle(Theme.faint)
                    if !nav.message.isEmpty { Text(nav.message).font(.caption).foregroundStyle(Theme.warn) }
                }
                if let d = nav.destination {
                    Button { favs.add(d) } label: {
                        Label(favs.has(d) ? "已在常去地点里" : "加到常去地点", systemImage: favs.has(d) ? "star.fill" : "star")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Theme.warn).disabled(favs.has(d))
                }
                GlassCard(title: "电量够不够", icon: "battery.75") {
                    Label(check.0, systemImage: check.2).font(.subheadline.weight(.semibold)).foregroundStyle(check.1)
                    if let range = m.rangeKm {
                        Text(String(format: "续航约 %.0f km（按最低的一块、留一成余量）；单程 %.1f km，往返 %.1f km。", range, km, km * 2))
                            .font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                Button {
                    if !ride.on { m.toggleRide() }
                    nav.start()
                    m.tab = 1
                    dismiss()
                } label: {
                    Label("开始导航", systemImage: "location.north.line.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(Theme.accent)).foregroundStyle(.white)
                }
                Button { openAmap() } label: {
                    Label("用高德地图导航", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().stroke(Color.white.opacity(0.4))).foregroundStyle(.white)
                }
                if !amapMsg.isEmpty { Text(amapMsg).font(.caption).foregroundStyle(Theme.warn) }
                Text("用高德导航时，这边会自动开始骑行记录，锁屏和灵动岛照样显示车速和电量。")
                    .font(.caption2).foregroundStyle(Theme.faint)
            }
            .padding(16)
        }
    }

    /// 跳到高德地图的骑行导航（坐标用地图自己的，dev=0 表示不再换算）
    private func openAmap() {
        guard let d = nav.destination else { return }
        let c = d.placemark.coordinate
        let name = (d.name ?? "目的地").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let s = String(format: "iosamap://path?sourceApplication=bms&dlat=%.6f&dlon=%.6f&dname=%@&dev=0&t=3", c.latitude, c.longitude, name)
        guard let url = URL(string: s) else { return }
        UIApplication.shared.open(url) { ok in
            if ok {
                if !ride.on { m.toggleRide() }
                LogStore.shared.log("跳到高德导航")
                dismiss()
            } else {
                amapMsg = "打不开高德地图，可能没有安装。"
            }
        }
    }

    private func batteryCheck(_ km: Double) -> (String, Color, String) {
        guard let range = m.rangeKm else { return ("还没连上电池，判断不了", Theme.sub, "questionmark.circle") }
        if range >= km * 2 * 1.1 { return ("来回都够", Theme.good, "checkmark.circle.fill") }
        if range >= km * 1.1 { return ("单程够，回程不够，记得在那边充电", Theme.warn, "exclamationmark.triangle.fill") }
        return ("电量可能不够骑到", Theme.bad, "xmark.octagon.fill")
    }
}
