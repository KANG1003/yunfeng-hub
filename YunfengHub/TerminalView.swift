//
//  TerminalView.swift
//  终端：直连爱快路由，拉取在线/离线设备、路由状态、单台设备实时流量
//

import SwiftUI
import UIKit

struct TerminalView: View {
    @State private var svc = IKuaiService()
    @State private var showSettings = false
    @State private var detail: IKuaiTerminal?
    @State private var keyword = ""
    @State private var showLog = false
    @State private var showOffline = false

    private var source: [IKuaiTerminal] {
        showOffline ? svc.offlineTerminals : svc.terminals
    }

    private var filtered: [IKuaiTerminal] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return source }
        return source.filter {
            $0.ip.contains(k) || $0.mac.lowercased().contains(k.lowercased())
                || $0.host.lowercased().contains(k.lowercased())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if !svc.isConfigured {
                    setupCard
                } else {
                    if let sys = svc.sys { statusBar(sys) }
                    if !svc.terminals.isEmpty || !svc.offlineTerminals.isEmpty {
                        switcher
                        searchBar
                    }
                    if svc.status == .failed { errorCard }
                    if source.isEmpty && svc.status != .loading && svc.status != .failed {
                        emptyCard
                    }
                    ForEach(filtered) { t in
                        row(t)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .refreshable { await svc.refresh() }
        .task { if svc.isConfigured { await svc.refresh() } }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(item: $detail) { t in
            TerminalDetailView(svc: svc, terminal: t)
        }
        .sheet(isPresented: $showLog) {
            logSheet
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("终端").font(.system(size: 22, weight: .bold))
                Text(statusLine).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                Task { await svc.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    private var statusLine: String {
        switch svc.status {
        case .loading: return "正在从路由器拉取…"
        case .ok:
            let time = svc.lastUpdate?.formatted(date: .omitted, time: .shortened) ?? ""
            let mode = svc.usedMode.isEmpty ? "" : " · \(svc.usedMode)"
            return "在线 \(svc.terminals.count) · 离线 \(svc.offlineTerminals.count) · \(time)\(mode)"
        case .failed: return "连接失败"
        case .idle: return "未连接"
        }
    }

    // MARK: 路由状态条

    private func statusBar(_ sys: IKuaiSystem) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    statCell(icon: "arrow.down", tint: Color.green,
                             title: "下行", value: IKuaiService.kb(sys.wanDown), unit: "/s")
                    divider
                    statCell(icon: "arrow.up", tint: Color.orange,
                             title: "上行", value: IKuaiService.kb(sys.wanUp), unit: "/s")
                    divider
                    statCell(icon: "wifi.router", tint: Color.white.opacity(0.85),
                             title: "在线终端", value: "\(sys.onlineCount)", unit: "台")
                }

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                HStack(spacing: 14) {
                    if sys.cpuPercent > 0 {
                        miniStat("CPU", String(format: "%.0f%%", sys.cpuPercent))
                    }
                    if !sys.memPercent.isEmpty {
                        miniStat("内存", sys.memPercent)
                    }
                    if sys.cpuTemp > 0 {
                        miniStat("温度", String(format: "%.0f°", sys.cpuTemp))
                    }
                    if sys.connNum > 0 {
                        miniStat("连接", "\(sys.connNum)")
                    }
                    Spacer(minLength: 0)
                    if !sys.uptime.isEmpty {
                        miniStat("已运行", sys.uptime)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 34)
    }

    private func statCell(icon: String, tint: Color, title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9.5)).foregroundStyle(tint)
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ k: String, _ v: String) -> some View {
        HStack(spacing: 3) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 10.5, weight: .medium, design: .monospaced))
        }
    }

    // MARK: 在线 / 离线 切换

    private var switcher: some View {
        HStack(spacing: 6) {
            tabTap("在线 \(svc.terminals.count)", active: !showOffline) { showOffline = false }
            tabTap("离线 \(svc.offlineTerminals.count)", active: showOffline) { showOffline = true }
            Spacer()
        }
    }

    private func tabTap(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(active ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(active ? 0.22 : 0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 未配置

    private var setupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("接上你的爱快路由器").font(.system(size: 14, weight: .semibold))
                Text("填一次 API Token，就能拿到和爱快 App 一样的终端列表：名称、MAC、上下行、连接数、在线时长。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                PrimaryButton(title: "去设置", systemImage: "gearshape") { showSettings = true }
                    .padding(.top, 2)
            }
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(showOffline ? "没有离线设备" : "没拿到设备").font(.system(size: 13.5, weight: .semibold))
                Text(showOffline ? "路由器里没有历史设备记录。" : "路由器连上了但列表是空的，可能是接口版本不同。点右上角齿轮看看地址是否填对。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var errorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("连不上").font(.system(size: 13.5, weight: .semibold))
                }
                Text(svc.message).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    GhostButton(title: "重试", systemImage: "arrow.clockwise") {
                        Task { await svc.refresh() }
                    }
                    GhostButton(title: "改设置", systemImage: "gearshape") { showSettings = true }
                    GhostButton(title: "诊断", systemImage: "stethoscope") {
                        Task {
                            await svc.diagnose()
                            showLog = true
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("IP / MAC / 名称", text: $keyword)
                .font(.system(size: 13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: 行

    private func row(_ t: IKuaiTerminal) -> some View {
        Button { detail = t } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: t))
                    .font(.system(size: 15))
                    .foregroundStyle(t.isOnline ? Color.primary : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(t.isOnline ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(t.host.isEmpty ? "未知设备" : t.host)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(t.isOnline ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(t.ip)
                            .font(.system(size: 11, design: .monospaced))
                        if t.isOnline {
                            if !t.online.isEmpty { Text("· \(t.online)").font(.system(size: 10.5)) }
                        } else if !t.lastSeen.isEmpty {
                            Text("· \(t.lastSeen)").font(.system(size: 10.5))
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if t.isOnline {
                        HStack(spacing: 6) {
                            Label(fmt(t.up), systemImage: "arrow.up")
                            Label(fmt(t.down), systemImage: "arrow.down")
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        if !t.connections.isEmpty {
                            Text("\(t.connections) 连接")
                                .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.8))
                        }
                    } else {
                        Text("已离线")
                            .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.85))
                        Text("累计 \(IKuaiService.bytes(t.totalDown))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(t.isOnline ? 0.12 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = t.ip
            } label: { Label("复制 IP", systemImage: "doc.on.doc") }
            Button {
                if let url = URL(string: "http://\(t.ip)") { UIApplication.shared.open(url) }
            } label: { Label("用 Safari 打开", systemImage: "safari") }
        }
    }

    /// 已带单位的直接显示，纯数字按 KB 处理
    private func fmt(_ s: String) -> String {
        if s.isEmpty { return "0" }
        if s.hasSuffix("K") || s.hasSuffix("M") || s.hasSuffix("B") || s == "—" { return s }
        guard let d = Double(s) else { return s }
        return d >= 1024 ? String(format: "%.1fM", d / 1024) : String(format: "%.0fK", d)
    }

    private func icon(for t: IKuaiTerminal) -> String {
        let h = t.host.lowercased()
        if h.contains("iphone") || h.contains("ipad") { return "iphone" }
        if h.contains("nas") || h.contains("群晖") { return "externaldrive" }
        if h.contains("desktop") || h.contains("pc") || h.contains("mac") { return "desktopcomputer" }
        if h.contains("路由") || h.contains("router") { return "wifi.router" }
        if h.contains("音箱") || h.contains("电视") || h.contains("插座") || h.contains("家居") { return "homekit" }
        return "questionmark.square.dashed"
    }

    // MARK: 设置

    private var settingsSheet: some View {
        @Bindable var svc = svc

        return NavigationStack {
            Form {
                Section {
                    TextField("https://192.168.10.250:8443", text: $svc.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("路由器地址")
                } footer: {
                    Text("必须能直连到这个地址：在家直连，出门走回家的 WireGuard。")
                }

                Section("账号（3.x 固件用）") {
                    TextField("admin", text: $svc.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $svc.password)
                }

                Section {
                    TextField("32 位 API Token", text: $svc.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                } header: {
                    Text("API Token（4.x 固件用，可留空）")
                } footer: {
                    Text("路由器后台：系统管理 → 登录管理 → 个人API令牌 → 添加令牌，生成后粘进来。填了它就会优先走 4.x 接口。")
                }

                Section {
                    PrimaryButton(title: "测试并刷新") {
                        Task {
                            await svc.refresh()
                            if svc.status == .ok { showSettings = false }
                        }
                    }
                    Button {
                        Task {
                            await svc.diagnose()
                            showLog = true
                        }
                    } label: {
                        Label("接口诊断", systemImage: "stethoscope")
                    }
                    if svc.status == .failed && !svc.message.isEmpty {
                        Text(svc.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.orange)
                    }
                    if svc.status == .ok {
                        Text("已连上（\(svc.usedMode)），在线 \(svc.terminals.count) 台 / 离线 \(svc.offlineTerminals.count) 台")
                            .font(.system(size: 12)).foregroundStyle(Color.green)
                    }
                } footer: {
                    Text("账号密码和 Token 只存在这台手机的本地存储里。")
                }
            }
            .navigationTitle("爱快路由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: 诊断日志

    private var logSheet: some View {
        NavigationStack {
            ScrollView {
                Text(svc.log.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.black.opacity(0.94))
            .foregroundStyle(Color.green.opacity(0.9))
            .navigationTitle("接口诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showLog = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = svc.log.joined(separator: "\n")
                    } label: { Image(systemName: "doc.on.doc") }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 单台设备详情（含 5 分钟实时流量曲线）

struct TerminalDetailView: View {
    let svc: IKuaiService
    let terminal: IKuaiTerminal

    @Environment(\.dismiss) private var dismiss
    @State private var points: [IKuaiTrafficPoint] = []
    @State private var protos: [IKuaiProtoItem] = []
    @State private var loading = true
    @State private var failed: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    if terminal.isOnline {
                        trafficCard
                    }
                    if !protos.isEmpty { protocolCard }
                    infoCard
                    rawCard
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(terminal.host.isEmpty ? "终端" : terminal.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await startPolling() }
        .task { await loadProtocols() }
    }

    // MARK: 头部

    private var identityCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(terminal.isOnline ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(terminal.ip).font(.system(size: 15, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text(terminal.isOnline ? "在线" : "离线")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((terminal.isOnline ? Color.green : Color.gray).opacity(0.16),
                                    in: Capsule())
                }
                Text(terminal.mac).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if terminal.isOnline, !terminal.online.isEmpty {
                        chip("在线 \(terminal.online)")
                    }
                    if !terminal.isOnline, !terminal.lastSeen.isEmpty {
                        chip("最后在线 \(terminal.lastSeen)")
                    }
                    if !terminal.connections.isEmpty, terminal.isOnline {
                        chip("\(terminal.connections) 连接")
                    }
                    if terminal.isOnline {
                        chip("↓ \(terminal.down)/s")
                        chip("↑ \(terminal.up)/s")
                    }
                }
            }
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 10.5, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: 5 分钟实时曲线

    private var trafficCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("近 5 分钟流量").font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    if let last = points.last {
                        Text("↓ \(IKuaiService.kb(last.down))/s · ↑ \(IKuaiService.kb(last.up))/s")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = failed {
                    Text(err).font(.system(size: 11.5)).foregroundStyle(.orange)
                } else if points.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(loading ? "正在拉取采样…" : "路由器还没有这个设备的采样数据")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    .frame(height: 110)
                } else {
                    TrafficChart(points: points)
                        .frame(height: 110)

                    HStack(spacing: 12) {
                        legend(color: Color.green, title: "下行", value: peak(\.down))
                        legend(color: Color.orange, title: "上行", value: peak(\.up))
                        Spacer()
                        Text("5 秒一个点").font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }
        }
    }

    private func peak(_ key: KeyPath<IKuaiTrafficPoint, Double>) -> String {
        let m = points.map { $0[keyPath: key] }.max() ?? 0
        return IKuaiService.kb(m) + "/s"
    }

    private func legend(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10.5, design: .monospaced))
        }
    }

    // MARK: 应用协议

    private var protocolCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("应用协议（累计）").font(.system(size: 13.5, weight: .semibold))
                ForEach(protos.prefix(5)) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.name).font(.system(size: 11.5))
                            Spacer()
                            Text(IKuaiService.bytes(p.total))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { g in
                            let ratio = maxTotal > 0 ? CGFloat(p.total / maxTotal) : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(Color.white.opacity(0.35))
                                    .frame(width: max(2, g.size.width * ratio))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    private var maxTotal: Double {
        protos.map(\.total).max() ?? 0
    }

    // MARK: 信息

    private var infoCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("基本信息").font(.system(size: 13.5, weight: .semibold))
                kv("名称", terminal.host.isEmpty ? "—" : terminal.host)
                kv("型号", terminal.raw["client_model"] ?? "—")
                kv("厂商", terminal.raw["client_vendor"] ?? "—")
                kv("接入接口", terminal.raw["interface"] ?? "—")
                kv("累计上行", IKuaiService.bytes(terminal.totalUp))
                kv("累计下行", IKuaiService.bytes(terminal.totalDown))
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(size: 12, design: .monospaced)).lineLimit(1)
        }
    }

    private var rawCard: some View {
        GlassCard(padding: 14) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(terminal.raw.keys.sorted(), id: \.self) { k in
                        HStack {
                            Text(k).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            Spacer()
                            Text(terminal.raw[k] ?? "").font(.system(size: 10.5, design: .monospaced)).lineLimit(1)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("路由器返回的全部字段").font(.system(size: 12.5, weight: .medium))
            }
        }
    }

    // MARK: 拉数据

    private func startPolling() async {
        guard terminal.isOnline else { return }
        await loadTraffic()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { break }
            await loadTraffic()
        }
    }

    private func loadTraffic() async {
        do {
            let list = try await svc.fetchTraffic(ip: terminal.ip, mac: terminal.mac)
            points = list
            failed = nil
        } catch {
            failed = "拉采样失败：\(error.localizedDescription)"
        }
        loading = false
    }

    private func loadProtocols() async {
        protos = (try? await svc.fetchProtocols(ip: terminal.ip, mac: terminal.mac)) ?? []
    }
}

// MARK: - 面积折线图

struct TrafficChart: View {
    let points: [IKuaiTrafficPoint]

    private var maxValue: Double {
        max(points.map { max($0.down, $0.up) }.max() ?? 0, 1024)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height

            ZStack(alignment: .topLeading) {
                // 网格
                Path { p in
                    for i in 1...3 {
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)

                // 下行填充
                Path { p in
                    guard points.count > 1 else { return }
                    let step = w / CGFloat(points.count - 1)
                    p.move(to: CGPoint(x: 0, y: h))
                    for (i, pt) in points.enumerated() {
                        let x = CGFloat(i) * step
                        let y = yPos(pt.down, h)
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.green.opacity(0.28), Color.green.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                // 下行线
                line(\.down, color: Color.green, w: w, h: h)
                // 上行线
                line(\.up, color: Color.orange, w: w, h: h)
            }
        }
    }

    private func line(_ key: KeyPath<IKuaiTrafficPoint, Double>, color: Color, w: CGFloat, h: CGFloat) -> some View {
        Path { p in
            guard points.count > 1 else { return }
            let step = w / CGFloat(points.count - 1)
            for (i, pt) in points.enumerated() {
                let point = CGPoint(x: CGFloat(i) * step, y: yPos(pt[keyPath: key], h))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        .stroke(color.opacity(0.9), lineWidth: 1.6)
    }

    private func yPos(_ v: Double, _ h: CGFloat) -> CGFloat {
        let ratio = min(1, v / maxValue)
        return h - CGFloat(ratio) * (h - 6) - 3
    }
}
