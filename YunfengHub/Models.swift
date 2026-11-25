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
    var host: String
    var url: String
    var symbol: String
    var isOnline: Bool = true
}

// MARK: - WireGuard 配置

struct WGProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var endpoint: String
    var address: String
    var allowedIPs: String
    var mtu: Int = 1400
    var privateKey: String = ""
    var publicKey: String = ""
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

    var profiles: [WGProfile] = []
    var activeProfileID: UUID?

    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("yunfeng-hub.json")
    }()

    init() {
        load()
        if tasks.isEmpty { tasks = Self.seedTasks }
        if navItems.isEmpty { navItems = Self.seedNav }
        if profiles.isEmpty { profiles = Self.seedProfiles }
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

    func addNav(name: String, host: String, url: String, symbol: String = "link") {
        navItems.append(NavItem(name: name, host: host, url: url, symbol: symbol))
        save()
    }

    // MARK: 持久化

    struct Snapshot: Codable {
        var tasks: [TaskItem]
        var entries: [DailyEntry]
        var template: ReportTemplate
        var navItems: [NavItem]
        var sunPanelURL: String
        var profiles: [WGProfile]
    }

    func save() {
        let snap = Snapshot(tasks: tasks, entries: entries, template: template,
                            navItems: navItems, sunPanelURL: sunPanelURL, profiles: profiles)
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
        profiles = snap.profiles
    }

    // MARK: 首次种子数据

    static let seedTasks: [TaskItem] = [
        TaskItem(title: "巡检 HA 自动化与备份", tag: "运维", done: true),
        TaskItem(title: "备件系统库存同步脚本", tag: "开发"),
        TaskItem(title: "NAS 备份策略调整", tag: "运维"),
    ]

    static let seedNav: [NavItem] = [
        NavItem(name: "导航面板", host: "sp.kangkang.me", url: "http://sp.kangkang.me", symbol: "safari.fill"),
        NavItem(name: "备件管理", host: "bj.kangkang.me", url: "http://bj.kangkang.me/login.php", symbol: "shippingbox"),
        NavItem(name: "日报神器", host: "rb.kangkang.me", url: "http://rb.kangkang.me/login.php", symbol: "square.and.pencil"),
        NavItem(name: "仪电周结", host: "we.kangkang.me", url: "http://we.kangkang.me/index.php", symbol: "calendar"),
        NavItem(name: "在线监控 Kuma", host: "kuma.kangkang.me", url: "http://kuma.kangkang.me", symbol: "waveform.path.ecg"),
        NavItem(name: "容器日志 Dozzle", host: "log.kangkang.me", url: "http://log.kangkang.me", symbol: "doc.text.magnifyingglass"),
        NavItem(name: "主机资源 Netdata", host: "sys.kangkang.me", url: "http://sys.kangkang.me", symbol: "cpu"),
    ]

    static let seedProfiles: [WGProfile] = [
        WGProfile(name: "家 · 内网", endpoint: "wg.yunfeng.pro:51820",
                  address: "10.8.0.2/32", allowedIPs: "192.168.10.0/24,10.8.0.0/24", mtu: 1400),
        WGProfile(name: "公司 · 跳板", endpoint: "wg2.yunfeng.pro:51820",
                  address: "10.9.0.2/32", allowedIPs: "10.9.0.0/24", mtu: 1380),
    ]
}
