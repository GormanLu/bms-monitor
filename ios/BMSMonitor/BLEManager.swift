import Foundation
import CoreBluetooth

struct FoundDevice: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
}

// 蓝牙：只接收保护板自己广播的数据，从不往电池里写任何东西。
// 开了后台蓝牙模式，切到别的应用、锁屏时照样收数据；断了会自动重连（走出范围再回来也会连上）。
// 系统为了省电把 app 关掉时，靠"状态恢复"再把 app 唤醒接着收。
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let advService = CBUUID(string: "726E")
    static let service = CBUUID(string: "00400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let notifyChar = CBUUID(string: "00400003-B5A3-F393-E0A9-E50E24DCCA9E")

    @Published var status = "蓝牙准备中"
    @Published var scanning = false
    @Published var found: [FoundDevice] = []
    @Published var connected = false
    @Published var deviceTail = ""

    var onData: (([UInt8]) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var seen: [UUID: CBPeripheral] = [:]

    private var want: Bool {
        get { UserDefaults.standard.bool(forKey: "ble.want") }
        set { UserDefaults.standard.set(newValue, forKey: "ble.want") }
    }
    var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "ble.device").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "ble.device") }
    }

    override init() {
        super.init()
        deviceTail = UserDefaults.standard.string(forKey: "ble.tail") ?? ""
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "bms-central",
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    // MARK: 用户操作
    func connect() {
        want = true
        if savedID == nil { startScan() } else { reconnect() }
    }

    func disconnect() {
        want = false
        stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        status = "已断开"
        LogStore.shared.log("手动断开")
    }

    func forget() {
        disconnect()
        savedID = nil
        peripheral = nil
        deviceTail = ""
        UserDefaults.standard.removeObject(forKey: "ble.tail")
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        found = []
        scanning = true
        status = "正在搜索电池…"
        central.scanForPeripherals(withServices: [BLEManager.advService])
    }

    func stopScan() {
        if scanning { central.stopScan() }
        scanning = false
    }

    func choose(_ d: FoundDevice) {
        stopScan()
        guard let p = seen[d.id] ?? central.retrievePeripherals(withIdentifiers: [d.id]).first else { return }
        savedID = d.id
        deviceTail = String(d.name.suffix(4))
        UserDefaults.standard.set(deviceTail, forKey: "ble.tail")
        want = true
        use(p)
        LogStore.shared.log("选中设备：名称结尾 " + deviceTail)
        central.connect(p)
        status = "正在连接…"
    }

    private func use(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
    }

    private func reconnect() {
        guard want, central.state == .poweredOn else { return }
        if let p = peripheral {
            if p.state == .connected { subscribe(p) } else { central.connect(p); status = "正在连接…" }
            return
        }
        if let id = savedID, let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            use(p)
            central.connect(p)       // 不会超时：电池一出现在附近就会连上，后台也一样
            status = "正在连接…"
        } else {
            startScan()
        }
    }

    private func subscribe(_ p: CBPeripheral) {
        if let svc = p.services?.first(where: { $0.uuid == BLEManager.service }),
           let ch = svc.characteristics?.first(where: { $0.uuid == BLEManager.notifyChar }) {
            p.setNotifyValue(true, for: ch)
        } else {
            p.discoverServices([BLEManager.service])
        }
    }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            status = connected ? "已连接" : (want ? "正在连接…" : "未连接")
            reconnect()
        case .poweredOff: status = "手机蓝牙关着"
        case .unauthorized: status = "没有蓝牙权限，请到系统设置里允许"
        default: status = "蓝牙不可用"
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            use(p)
            LogStore.shared.log("系统在后台恢复了蓝牙连接")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? "（没有名字）"
        seen[p.identifier] = p
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i].rssi = rssi.intValue }
        else { found.append(FoundDevice(id: p.identifier, name: name, rssi: rssi.intValue)) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connected = true
        status = "已连接"
        LogStore.shared.log("已连接" + (deviceTail.isEmpty ? "" : "（名称结尾 \(deviceTail)）"))
        subscribe(p)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        LogStore.shared.log("连接失败：\(error?.localizedDescription ?? "未知原因")")
        if want { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.reconnect() } }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connected = false
        LogStore.shared.log("连接已断开" + (error.map { "（\($0.localizedDescription)）" } ?? ""))
        if want {
            status = "断开了，正在重连…"
            central.connect(p)
        } else {
            status = "已断开"
        }
    }

    // MARK: CBPeripheralDelegate
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == BLEManager.service }) else {
            LogStore.shared.log("这个设备上没有电池保护板的服务，可能选错了设备")
            status = "选错了设备？"
            return
        }
        p.discoverCharacteristics([BLEManager.notifyChar], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
        guard let ch = svc.characteristics?.first(where: { $0.uuid == BLEManager.notifyChar }) else { return }
        p.setNotifyValue(true, for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.isNotifying { LogStore.shared.log("已订阅通知通道") }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value, !v.isEmpty else { return }
        onData?([UInt8](v))
    }
}
