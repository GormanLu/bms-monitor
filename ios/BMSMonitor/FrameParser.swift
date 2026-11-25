import Foundation

// 保护板自己不停广播的厂家格式（和网页里的 handleVendor 一样）：
// [长度 N][01][N 个字节内容][CRC16-MODBUS 高字节在前]，校验从第 2 个字节算到内容结束。
// 内容第 3 个字节是类型：01 = 一块电池（4 节），02 = 整组汇总。只接收，不发送任何指令。

struct BlockData {
    let id: UInt8
    let cells: [Double]        // 4 节电压，伏
    let current: Double        // 安，放电为负
    let soc: Double            // 这一块保护板自己数的电量 %
    let temps: [Int]           // 两个测温点，°C
    let nominalAh: Double
    let remainAh: Double
    let term: Double           // 这一块两端的电压，伏
    let status: UInt16         // 状态字（字节 14-15），第 2 位 = 充电开关开着
    let balance: UInt8         // 均衡位（字节 38 低 4 位）
    var raw25: UInt8 = 0       // 字节 25：一直是 200，推测是健康度 ×2（没法验证）
    var raw22: UInt8 = 0       // 字节 22：A～D 一直是 3、P 是 0；小程序显示的循环次数 0 和 P 的这个字节一致，推测是保护板的循环计数（但用了一轮也没涨）
    let at: Date

    var name: String {
        if id == 0x40 { return "直连" }
        if id >= 0x41 && id <= 0x5A { return String(UnicodeScalar(id)) }
        return String(format: "%02X", id)
    }
    var gapMv: Int {
        guard let hi = cells.max(), let lo = cells.min() else { return 0 }
        return Int(((hi - lo) * 1000).rounded())
    }
    var chargeShut: Bool { (status & 0x04) == 0 }
}

struct SummaryData {
    let soc: Double
    let totalV: Double         // 整组端口电压
    let cellsV: Double         // 各节电压之和
    let flags: UInt8
    let current: Double
}

enum Frame {
    case block(BlockData)
    case summary(SummaryData)
}

final class FrameParser {
    private var buf: [UInt8] = []
    private var lastAt = Date.distantPast

    static func crc(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var c: UInt16 = 0xFFFF
        for b in bytes {
            c ^= UInt16(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1 }
        }
        return c
    }

    func feed(_ data: [UInt8]) -> [Frame] {
        let now = Date()
        if now.timeIntervalSince(lastAt) > 1.5 { buf.removeAll() }   // 隔了很久的半截数据不要了
        lastAt = now
        buf.append(contentsOf: data)
        var out: [Frame] = []
        while buf.count >= 4 {
            let total = Int(buf[0]) + 4
            if buf[1] != 0x01 || buf[0] < 6 || total > 150 { buf.removeFirst(); continue }
            if buf.count < total { break }
            let want = UInt16(buf[total - 2]) << 8 | UInt16(buf[total - 1])
            if FrameParser.crc(buf[1..<(total - 2)]) != want { buf.removeFirst(); continue }
            let f = Array(buf[0..<total])
            buf.removeFirst(total)
            if let fr = FrameParser.decode(f, at: now) { out.append(fr) }
        }
        return out
    }

    static func decode(_ f: [UInt8], at: Date) -> Frame? {
        func u(_ i: Int) -> Int { Int(f[i]) << 8 | Int(f[i + 1]) }
        if f[4] == 0x01 && f.count >= 47 {
            let cells = [26, 28, 30, 32].map { Double(u($0)) / 1000 }
            return .block(BlockData(
                id: f[6], cells: cells,
                current: Double(u(11) - 30000) / 100,
                soc: Double(f[13]) / 2,
                temps: [Int(f[17]) - 40, Int(f[18]) - 40],
                nominalAh: Double(u(39)) / 100,
                remainAh: Double(u(41)) / 100,
                term: Double(u(9)) / 1000,
                status: UInt16(u(14)),
                balance: f[38] & 0x0F,
                raw25: f[25],
                raw22: f[22],
                at: at))
        }
        if f[4] == 0x02 && f.count >= 30 {
            return .summary(SummaryData(
                soc: Double(f[21]) / 2,
                totalV: Double(u(22)) / 10,
                cellsV: Double(u(28)) / 10,
                flags: f[20],
                current: Double(u(24) - 30000) / 100))
        }
        return nil
    }
}
