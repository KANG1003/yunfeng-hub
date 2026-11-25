//
//  Models.swift
//  数据模型 + 本地持久化 + 全局 Store
//

import Foundation
import Observation

// MARK: - 任务

struct TaskItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var tag: String = "其他"
    var done: Bool = false
    var createdAt: Date = .now
}

// MARK: - 每日记录

struct DailyEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var tasks: [TaskItem]
    var reportText: String = ""
}

// MARK: - 模板

enum ReportTemplate: String, CaseIterable, Codable, Identifiable {
    case standard = "标准"
    case brief = "简洁"
    case official = "向上汇报"
    var id: String { rawValue }
}

// MARK: - 快捷入口

struct NavItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String = "link"
    var lanURL: String = ""     // 内网地址，可为空
    var wanURL: String = ""     // 外网地址，可为空
    var note: String = ""

    var hasLAN: Bool { !lanURL.isEmpty }
    var hasWAN: Bool { !wanURL.isEmpty }

    /// 按当前网络环境取地址：在内网优先走 lan，缺哪个用另一个兜底
    func url(onLAN: Bool) -> URL? {
        let primary = onLAN ? lanURL : wanURL
        let fallback = onLAN ? wanURL : lanURL
        return URL(string: primary.isEmpty ? fallback : primary)
    }

    /// 卡片上显示的主机名
    func displayHost(onLAN: Bool) -> String {
        let primary = onLAN ? lanURL : wanURL
        let s = primary.isEmpty ? (onLAN ? wanURL : lanURL) : primary
        return s.replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
    }
}

// MARK: - 全局 Store

@MainActor
@Observable
final class AppStore {

    var tasks: [TaskItem] = []
    var entries: [DailyEntry] = []
    var template: ReportTemplate = .standard

    var navItems: [NavItem] = []
    var sunPanelURL: String = "http://sp.kangkang.me"

    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("yunfeng-hub.json")
    }()

    init() {
        load()
        if tasks.isEmpty { tasks = Self.seedTasks }
        if navItems.isEmpty { navItems = Self.seedNav }
    }

    // MARK: 任务操作

    func toggle(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].done.toggle()
        save()
    }

    func addTask(title: String, tag: String = "其他") {
        tasks.append(TaskItem(title: title, tag: tag))
        save()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func archiveToday() {
        let entry = DailyEntry(date: .now, tasks: tasks, reportText: report())
        entries.append(entry)
        save()
    }

    // MARK: 日报

    func report() -> String {
        ReportEngine.render(tasks: tasks, template: template, date: .now)
    }

    // MARK: 导航

    func addNav(name: String, lanURL: String = "", wanURL: String = "",
                symbol: String = "link") {
        navItems.append(NavItem(name: name, symbol: symbol, lanURL: lanURL, wanURL: wanURL))
        save()
    }

    func deleteNav(_ item: NavItem) {
        navItems.removeAll { $0.id == item.id }
        save()
    }

    // MARK: 持久化

    struct Snapshot: Codable {
        var tasks: [TaskItem]
        var entries: [DailyEntry]
        var template: ReportTemplate
        var navItems: [NavItem]
        var sunPanelURL: String
    }

    func save() {
        let snap = Snapshot(tasks: tasks, entries: entries, template: template,
                            navItems: navItems, sunPanelURL: sunPanelURL)
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("保存失败:", error)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        tasks = snap.tasks
        entries = snap.entries
        template = snap.template
        navItems = snap.navItems
        sunPanelURL = snap.sunPanelURL
    }

    // MARK: 首次种子数据

    static let seedTasks: [TaskItem] = [
        TaskItem(title: "巡检 HA 自动化与备份", tag: "运维", done: true),
        TaskItem(title: "备件系统库存同步脚本", tag: "开发"),
        TaskItem(title: "NAS 备份策略调整", tag: "运维"),
    ]

    static let seedNav: [NavItem] = [
        NavItem(name: "导航面板", symbol: "safari.fill",
                lanURL: "http://192.168.10.69:3000", wanURL: "http://sp.kangkang.me"),
        NavItem(name: "备件管理", symbol: "shippingbox",
                lanURL: "", wanURL: "http://bj.kangkang.me/login.php"),
        NavItem(name: "日报神器", symbol: "square.and.pencil",
                lanURL: "", wanURL: "http://rb.kangkang.me/login.php"),
        NavItem(name: "仪电周结", symbol: "calendar",
                lanURL: "", wanURL: "http://we.kangkang.me/index.php"),
        NavItem(name: "在线监控 Kuma", symbol: "waveform.path.ecg",
                lanURL: "http://192.168.10.69:3001", wanURL: "http://kuma.kangkang.me"),
        NavItem(name: "容器日志 Dozzle", symbol: "doc.text.magnifyingglass",
                lanURL: "", wanURL: "http://log.kangkang.me"),
        NavItem(name: "主机资源 Netdata", symbol: "cpu",
                lanURL: "", wanURL: "http://sys.kangkang.me"),
        NavItem(name: "Home Assistant", symbol: "house",
                lanURL: "http://192.168.10.69", wanURL: "https://ha.yunfeng.pro"),
        NavItem(name: "群晖 NAS", symbol: "externaldrive",
                lanURL: "http://192.168.10.252:5000", wanURL: ""),
        NavItem(name: "PVE", symbol: "server.rack",
                lanURL: "https://192.168.10.240:8006", wanURL: ""),
    ]
}
