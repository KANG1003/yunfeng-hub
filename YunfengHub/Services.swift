//
//  Services.swift
//  日报引擎 / 周报引擎 / WireGuard 配置生成 / Sun-Panel
//

import Foundation
import SwiftUI
import Observation
import Darwin

// MARK: - 日报生成

enum ReportEngine {

    static func render(tasks: [TaskItem], template: ReportTemplate, date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let d = df.string(from: date)

        let done = tasks.filter(\.done)
        let todo = tasks.filter { !$0.done }

        switch template {
        case .brief:
            var lines = ["【工作日报】\(d)"]
            lines += done.map { "· \($0.title)" }
            lines.append("待跟进：" + (todo.isEmpty ? "无" : todo.map(\.title).joined(separator: "、")))
            return lines.joined(separator: "\n")

        case .official:
            var s = "\(d) 工作汇报\n\n一、今日完成\n"
            if done.isEmpty { s += "暂无\n" }
            for (i, t) in done.enumerated() { s += "\(i + 1). \(t.title)（\(t.tag)）\n" }
            s += "\n二、存在问题\n暂无阻塞\n\n三、明日计划\n"
            if todo.isEmpty { s += "按计划推进\n" }
            for (i, t) in todo.enumerated() { s += "\(i + 1). \(t.title)\n" }
            return s

        case .standard:
            var lines = ["【日报】\(d)", "完成 \(done.count) 项 / 待办 \(todo.count) 项", ""]
            lines += done.map { "✅ \($0.title)" }
            lines += todo.map { "⏳ \($0.title)" }
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - 周报生成

struct DayStat: Identifiable, Hashable {
    var id: String { label }
    var label: String        // 一 二 三 …
    var date: Int            // 几号
    var rate: Double         // 0...1
}

enum WeeklyEngine {

    static func stats(base: Date = .now) -> [DayStat] {
        // 演示数据：接入真实数据时，用 entries 按日期聚合即可
        let cal = Calendar.current
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let start = cal.dateInterval(of: .weekOfYear, for: base)?.start ?? base
        let rates: [Double] = [0.72, 0.86, 0.64, 0.48, 0, 0, 0]

        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: start) ?? start
            let num = cal.component(.day, from: day)
            return DayStat(label: labels[i], date: num, rate: rates[i])
        }
    }

    static func completionRate(_ stats: [DayStat]) -> Double {
        let planned = stats.reduce(0) { $0 + ($1.rate > 0 ? 1 : 0) }
        guard planned > 0 else { return 0 }
        return stats.reduce(0) { $0 + $1.rate } / Double(planned)
    }

    static func weeklyReport(stats: [DayStat], entries: [DailyEntry]) -> String {
        let pct = Int(completionRate(stats) * 100)
        var s = "本周周报\n\n一、本周完成\n"
        if entries.isEmpty {
            s += "1. HA 自动化重构：回家 / 离家 / 门廊 / 双向联动全部上线\n"
            s += "2. 备件系统查询优化与库存同步\n"
            s += "3. NAS 备份策略与 WireGuard 排查\n"
        } else {
            for (i, e) in entries.enumerated() {
                s += "\(i + 1). \(e.reportText.prefix(60))\n"
            }
        }
        s += "\n二、数据\n完成率 \(pct)%\n"
        s += "\n三、下周计划\n1. 智能开关模块本地化改造\n2. 备件系统报表导出\n3. 服务器巡查规范化"
        return s
    }
}

// MARK: - WireGuard 配置
//
// 本 App 不做隧道（iOS 建隧道必须 NetworkExtension + 付费开发者账号）。
// 这里只负责：解析 .conf → 生成标准 .conf → 交给官方 WireGuard App 导入。

enum WGConfig {

    /// 生成可直接导入官方 WireGuard 的配置文件内容
    static func render(_ p: WGProfile, keepalive: Int = 25) -> String {
        var s = "[Interface]\n"
        s += "PrivateKey = \(p.privateKey)\n"
        s += "Address = \(p.address)\n"
        if p.mtu > 0 { s += "MTU = \(p.mtu)\n" }
        s += "\n[Peer]\n"
        s += "PublicKey = \(p.publicKey)\n"
        s += "Endpoint = \(p.endpoint)\n"
        s += "AllowedIPs = \(p.allowedIPs)\n"
        s += "PersistentKeepalive = \(keepalive)\n"
        return s
    }

    /// 解析 .conf 文本
    static func parse(_ text: String, name: String) -> WGProfile? {
        var p = WGProfile(name: name, endpoint: "", address: "", allowedIPs: "")
        var inInterface = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inInterface = line.lowercased().contains("interface")
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased(), val = parts[1]
            switch key {
            case "address" where inInterface: p.address = val
            case "privatekey": p.privateKey = val
            case "mtu": p.mtu = Int(val) ?? 1400
            case "endpoint": p.endpoint = val
            case "publickey": p.publicKey = val
            case "allowedips": p.allowedIPs = val
            default: break
            }
        }
        return p.endpoint.isEmpty ? nil : p
    }

    /// 密钥脱敏显示
    static func mask(_ key: String) -> String {
        guard key.count > 12 else { return key.isEmpty ? "未配置" : key }
        return String(key.prefix(6)) + "…" + String(key.suffix(4))
    }
}

// MARK: - Sun-Panel

@MainActor
@Observable
final class SunPanelService {
    var urlString: String = "http://sp.kangkang.me"
    var isReachable: Bool = true

    var url: URL? { URL(string: urlString) }
}

// MARK: - 网络环境（内网 / 外网自动判定）

enum NetMode: String, CaseIterable, Identifiable {
    case auto, lan, wan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自动"
        case .lan:  return "内网"
        case .wan:  return "外网"
        }
    }
}

@MainActor
@Observable
final class NetworkEnv {

    var mode: NetMode = .auto {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "net.mode") }
    }
    var localIPs: [String] = []
    var onHomeLAN: Bool = false

    /// 当前是否按内网地址访问
    var activeOnLAN: Bool {
        switch mode {
        case .lan: return true
        case .wan: return false
        case .auto: return onHomeLAN
        }
    }

    var statusText: String {
        if mode == .auto {
            return onHomeLAN ? "自动 · 内网" : "自动 · 外网"
        }
        return mode.title
    }

    init() {
        if let s = UserDefaults.standard.string(forKey: "net.mode"),
           let m = NetMode(rawValue: s) { mode = m }
        refresh()
    }

    func refresh() {
        localIPs = Self.ipv4Addresses()
        // 家里网段 192.168.10.x 判为内网
        onHomeLAN = localIPs.contains { $0.hasPrefix("192.168.10.") }
    }

    func cycleMode() {
        switch mode {
        case .auto: mode = .lan
        case .lan:  mode = .wan
        case .wan:  mode = .auto
        }
        refresh()
    }

    static func ipv4Addresses() -> [String] {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return [] }
        defer { freeifaddrs(ptr) }

        var out: [String] = []
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let a = p.pointee
            if let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    out.append(String(cString: buf))
                }
            }
            cur = a.ifa_next
        }
        return out
    }
}
