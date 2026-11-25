//
//  Services.swift
//  日报引擎 / 周报引擎 / WireGuard / Sun-Panel
//

import Foundation
import SwiftUI
import NetworkExtension
import Observation

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

// MARK: - WireGuard 服务
//
// 注意：iOS 上真正建立 WireGuard 隧道必须是三方协作：
//   1. 引入 WireGuardKit（SPM：https://github.com/WireGuard/wireguard-apple）
//   2. 新建 Packet Tunnel Extension target（NEPacketTunnelProvider 子类）
//   3. 主 App 与 Extension 共享 App Group（group.com.yunfeng.hub）
//   4. 开发者后台为两个 Bundle ID 同时开启 Network Extension (VPN) 能力
//
// 本文件把「配置解析 / 状态管理 / 上层 UI 接口」写好，
// 真拨号只需把 connect() 里标注 TODO 的两处接上即可。

@MainActor
@Observable
final class WireGuardService {

    enum Status: String {
        case disconnected = "未连接"
        case connecting = "连接中"
        case connected = "已连接"
        case failed = "连接失败"
    }

    var status: Status = .disconnected
    var startedAt: Date?
    var downlink: Double = 0
    var uplink: Double = 0

    private var timer: Timer?
    private var manager: NEVPNManager?

    var isOn: Bool { status == .connected }

    var uptimeText: String {
        guard let startedAt else { return "00:00" }
        let sec = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    func toggle(profile: WGProfile?) {
        if isOn { disconnect() } else { connect(profile: profile) }
    }

    func connect(profile: WGProfile?) {
        guard let profile else { return }
        status = .connecting

        // TODO: ① 用 WireGuardKit 生成 TunnelConfiguration 并写入 App Group
        // TODO: ② 通过 NETunnelProviderManager 启动 PacketTunnelProvider

        // 演示态：300ms 后置为已连接，真实工程请删掉这段
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.status = .connected
            self.startedAt = .now
            self.startMetering()
        }
        _ = profile
    }

    func disconnect() {
        timer?.invalidate(); timer = nil
        status = .disconnected
        startedAt = nil
        downlink = 0; uplink = 0
        // TODO: manager?.connection.stopVPNTunnel()
    }

    private func startMetering() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.downlink = 85 + Double.random(in: 0...20)
                self.uplink = 18 + Double.random(in: 0...8)
            }
        }
    }

    // MARK: 解析 .conf

    static func parse(conf text: String, name: String) -> WGProfile? {
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
}

// MARK: - Sun-Panel

@MainActor
@Observable
final class SunPanelService {
    var urlString: String = "http://192.168.10.69:3000"
    var isReachable: Bool = true

    var url: URL? { URL(string: urlString) }
}
