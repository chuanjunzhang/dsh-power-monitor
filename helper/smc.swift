import Foundation
import IOKit

struct SMCKeyData_t {
    var key: UInt32 = 0
    var vMajor: UInt8 = 0, vMinor: UInt8 = 0, vBuild: UInt8 = 0, vReserved: UInt8 = 0
    var vRelease: UInt16 = 0
    var pad1: UInt16 = 0
    var plVersion: UInt16 = 0, plLength: UInt16 = 0
    var plCpu: UInt32 = 0, plGpu: UInt32 = 0, plMem: UInt32 = 0
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var pad2: UInt8 = 0, pad3: UInt8 = 0, pad4: UInt8 = 0
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
    var pad5: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard svc != 0 else { exit(2) }
var conn: io_connect_t = 0
guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { exit(3) }
defer { IOServiceClose(conn) }

func call(_ i: inout SMCKeyData_t, _ o: inout SMCKeyData_t) -> kern_return_t {
    var n = MemoryLayout<SMCKeyData_t>.size
    return IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<SMCKeyData_t>.size, &o, &n)
}
func fourCC(_ s: String) -> UInt32 { var v: UInt32 = 0; for c in Array(s.utf8) { v = (v << 8) | UInt32(c) }; return v }
func str4(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    return String(bytes: b, encoding: .ascii) ?? ""
}
func bytesOf(_ o: SMCKeyData_t, _ n: Int) -> [UInt8] {
    let a: [UInt8] = [o.bytes.0,o.bytes.1,o.bytes.2,o.bytes.3,o.bytes.4,o.bytes.5,o.bytes.6,o.bytes.7,
                      o.bytes.8,o.bytes.9,o.bytes.10,o.bytes.11,o.bytes.12,o.bytes.13,o.bytes.14,o.bytes.15,
                      o.bytes.16,o.bytes.17,o.bytes.18,o.bytes.19,o.bytes.20,o.bytes.21,o.bytes.22,o.bytes.23,
                      o.bytes.24,o.bytes.25,o.bytes.26,o.bytes.27,o.bytes.28,o.bytes.29,o.bytes.30,o.bytes.31]
    return Array(a.prefix(max(0, min(n, 32))))
}
func readKey(_ key: String) -> (String, [UInt8])? {
    var i = SMCKeyData_t(); var o = SMCKeyData_t()
    i.key = fourCC(key); i.data8 = 9
    guard call(&i, &o) == KERN_SUCCESS, o.dataSize > 0 else { return nil }
    let size = Int(o.dataSize); let type = str4(o.dataType)
    var i2 = SMCKeyData_t(); var o2 = SMCKeyData_t()
    i2.key = fourCC(key); i2.data8 = 5; i2.dataSize = UInt32(size)
    guard call(&i2, &o2) == KERN_SUCCESS else { return nil }
    return (type, bytesOf(o2, size))
}
func num(_ b: [UInt8], _ type: String) -> Double? {
    guard b.count >= 2 else { return nil }
    switch type {
    case "flt ":
        guard b.count >= 4 else { return nil }
        let bits = UInt32(b[3])<<24 | UInt32(b[2])<<16 | UInt32(b[1])<<8 | UInt32(b[0])
        let v = Float(bitPattern: bits); return v.isFinite ? Double(v) : nil
    case "sp78": return Double(UInt16(b[0])<<8 | UInt16(b[1])) / 256.0
    case "fpe2": return Double(UInt16(b[0])<<8 | UInt16(b[1])) / 4.0
    case "ui16": return Double(UInt16(b[0])<<8 | UInt16(b[1]))
    default: return nil
    }
}

var fan: Double? = nil
// 注意：风扇在空闲时会停转（0 RPM），0 是有效值，不能当成“读取失败”
for k in ["F0Ac", "F1Ac"] {
    if let (t, b) = readKey(k), let v = num(b, t), v >= 0, v < 20000 { fan = v; break }
}

func group(_ prefix: String, _ count: Int) -> Double? {
    var vals: [Double] = []
    // 键名形如 Tp00..Tp0g，逐个探测常见编码
    let suffixes = ["00","04","08","0C","0G","0K","0O","0R","0X","0g","1M","1c","12","3d","0R","1k"]
    for s in suffixes.prefix(count) {
        if let (t,b) = readKey(prefix + s), let v = num(b,t), v > 5, v < 120 { vals.append(v) }
    }
    return vals.isEmpty ? nil : vals.max()
}
let cpu = group("Tp", 10)
let gpu = group("Tg", 10)

// ---- CPU 占用：Mach host_statistics 两次采样 ----
var cpuPercent: Double? = nil
do {
    var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    var info = host_cpu_load_info_data_t()
    func ticks() -> (UInt32, UInt32, UInt32, UInt32)? {
        var s2 = size
        var i2 = host_cpu_load_info_data_t()
        let r = withUnsafeMutablePointer(to: &i2) { p -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(s2)) { q in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, q, &s2)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        return (i2.cpu_ticks.0, i2.cpu_ticks.1, i2.cpu_ticks.2, i2.cpu_ticks.3)
    }
    if let a = ticks() {
        usleep(400_000)
        if let b = ticks() {
            // 索引: 0=user 1=system 2=idle 3=nice
            let du = Double(b.0 &- a.0)
            let ds = Double(b.1 &- a.1)
            let di = Double(b.2 &- a.2)
            let dn = Double(b.3 &- a.3)
            let total = du + dn + ds + di
            if total > 0 { cpuPercent = (total - di) / total * 100.0 }
        }
    }
    _ = (size, info)
}

let out: [String: Any] = [
    "fan": fan ?? NSNull(),
    "cpuTemp": cpu ?? NSNull(),
    "gpuTemp": gpu ?? NSNull(),
    "cpu": cpuPercent ?? NSNull(),
]
FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: out))
