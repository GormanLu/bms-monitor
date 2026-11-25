import SwiftUI
import MapKit

// MARK: 坐标换算
// 手机定位给的是国际通用的 WGS-84 坐标；中国大陆的地图底图用的是 GCJ-02（俗称火星坐标），
// 直接画上去会偏几百米。所以在地图上画轨迹前换算一下（存的还是原始坐标，导出 GPX 也用原始坐标）。
// 如果发现轨迹和道路明显错开，可以在设置里关掉"轨迹偏移校正"试试。
enum ChinaCoord {
    static func toGCJ(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        if lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271 { return .init(latitude: lat, longitude: lon) }
        let a = 6378245.0, ee = 0.00669342162296594323
        var dLat = tLat(lon - 105.0, lat - 35.0), dLon = tLon(lon - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return .init(latitude: lat + dLat, longitude: lon + dLon)
    }
    private static func tLat(_ x: Double, _ y: Double) -> Double {
        var r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        r += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        r += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        r += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return r
    }
    private static func tLon(_ x: Double, _ y: Double) -> Double {
        var r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        r += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        r += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        r += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return r
    }
}

/// 车速对应的颜色：慢是蓝，中速绿，快黄，最快红
func speedColor(_ v: Double) -> UIColor {
    let stops: [(Double, UIColor)] = [
        (0, UIColor(red: 0.33, green: 0.57, blue: 1.0, alpha: 1)),
        (15, UIColor(red: 0.36, green: 0.87, blue: 0.55, alpha: 1)),
        (28, UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1)),
        (40, UIColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1)),
    ]
    guard v > stops[0].0 else { return stops[0].1 }
    for i in 1..<stops.count where v <= stops[i].0 {
        let (v0, c0) = stops[i - 1], (v1, c1) = stops[i]
        let f = CGFloat((v - v0) / (v1 - v0))
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0, r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        c0.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        return UIColor(red: r0 + (r1 - r0) * f, green: g0 + (g1 - g0) * f, blue: b0 + (b1 - b0) * f, alpha: 1)
    }
    return stops.last!.1
}

// MARK: 地图上的轨迹（按车速变色，标出发和到达）
struct TrackMap: UIViewRepresentable {
    let track: [TrackPoint]
    var gcj = true

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        m.isRotateEnabled = false
        m.showsCompass = false
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        m.removeOverlays(m.overlays)
        m.removeAnnotations(m.annotations)
        let coords = track.map { gcj ? ChinaCoord.toGCJ($0.lat, $0.lon) : CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard coords.count >= 2 else { return }
        context.coordinator.speeds = track.map(\.v)
        let line = MKPolyline(coordinates: coords, count: coords.count)
        m.addOverlay(line)
        let s = MKPointAnnotation(); s.coordinate = coords[0]; s.title = "出发"
        let e = MKPointAnnotation(); e.coordinate = coords[coords.count - 1]; e.title = "到达"
        m.addAnnotations([s, e])
        m.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 30, right: 30), animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var speeds: [Double] = []
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKGradientPolylineRenderer(polyline: line)
            let n = CGFloat(max(speeds.count - 1, 1))
            r.setColors(speeds.map { speedColor($0) }, locations: speeds.indices.map { CGFloat($0) / n })
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            v.markerTintColor = annotation.title == "出发" ? UIColor(red: 0.36, green: 0.87, blue: 0.55, alpha: 1) : UIColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1)
            v.glyphImage = UIImage(systemName: annotation.title == "出发" ? "flag.fill" : "flag.checkered")
            return v
        }
    }
}

// MARK: 不带地图的小路线图（列表缩略图、仪表盘上用）
struct TrackShape: Shape {
    let track: [TrackPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard track.count >= 2 else { return p }
        let lat0 = track[0].lat * .pi / 180
        let xs = track.map { $0.lon * cos(lat0) }, ys = track.map { $0.lat }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return p }
        let span = max(maxX - minX, maxY - minY, 1e-6)
        let scale = min(rect.width, rect.height) / span
        let ox = rect.midX - (minX + maxX) / 2 * scale, oy = rect.midY + (minY + maxY) / 2 * scale
        for i in track.indices {
            let pt = CGPoint(x: ox + xs[i] * scale, y: oy - ys[i] * scale)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

// MARK: 导出 GPX（通用的轨迹文件，很多地图和运动软件都能打开）
extension Trip {
    func gpxFile() -> URL? {
        guard let track, track.count >= 2 else { return nil }
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="电池监控" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(start.formatted(.dateTime.year().month().day().hour().minute()))</name><trkseg>

        """
        for p in track {
            s += String(format: "<trkpt lat=\"%.7f\" lon=\"%.7f\"><time>%@</time></trkpt>\n", p.lat, p.lon, iso.string(from: start.addingTimeInterval(p.t)))
        }
        s += "</trkseg></trk></gpx>\n"
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("骑行-\(df.string(from: start)).gpx")
        do { try s.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
