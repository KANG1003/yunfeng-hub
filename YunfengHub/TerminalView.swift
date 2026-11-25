//
//  TerminalView.swift
//  终端：直连爱快路由，拉取 LAN 在线设备列表
//

import SwiftUI
import UIKit

struct TerminalView: View {
    @State private var svc = IKuaiService()
    @State private var showSettings = false
    @State private var detail: IKuaiTerminal?
    @State private var keyword = ""
    @State private var showLog = false

    private var filtered: [IKuaiTerminal] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return svc.terminals }
        return svc.terminals.filter {
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
                    if !svc.terminals.isEmpty { searchBar }
                    if svc.status == .failed { errorCard }
                    if svc.terminals.isEmpty && svc.status != .loading && svc.status != .failed {
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
            terminalDetail(t)
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
            return "在线 \(svc.terminals.count) 台 · \(time)\(mode)"
        case .failed: return "连接失败"
        case .idle: return "未连接"
        }
    }

    // MARK: 未配置

    private var setupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("接上你的爱快路由器").font(.system(size: 14, weight: .semibold))
                Text("填一次账号密码，就能拿到和爱快 App 一样的终端列表：名称、MAC、上下行、连接数、在线时长。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                PrimaryButton(title: "去设置", systemImage: "gearshape") { showSettings = true }
                    .padding(.top, 2)
            }
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("没拿到设备").font(.system(size: 13.5, weight: .semibold))
                Text("路由器连上了但列表是空的，可能是接口版本不同。点右上角齿轮看看地址是否填对。")
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
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(t.host.isEmpty ? "未知设备" : t.host)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(t.ip)
                            .font(.system(size: 11, design: .monospaced))
                        if !t.online.isEmpty {
                            Text("· \(t.online)").font(.system(size: 10.5))
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
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
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
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
        if s.hasSuffix("K") || s.hasSuffix("M") || s.hasSuffix("B") { return s }
        guard let d = Double(s) else { return s }
        return d >= 1024 ? String(format: "%.1fM", d / 1024) : String(format: "%.0fK", d)
    }

    private func icon(for t: IKuaiTerminal) -> String {
        let h = t.host.lowercased()
        if h.contains("iphone") || h.contains("ipad") { return "iphone" }
        if h.contains("nas") || h.contains("群晖") { return "externaldrive" }
        if h.contains("desktop") || h.contains("pc") || h.contains("mac") { return "desktopcomputer" }
        if h.contains("路由") || h.contains("router") { return "wifi.router" }
        if h.contains("音箱") || h.contains("电视") || h.contains("插座") { return "homekit" }
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
                    Text("路由器后台：系统设置 → 安全设置 → API Token，生成后粘进来。填了它就会优先走 4.x 接口。")
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
                        Text("已连上（\(svc.usedMode)），\(svc.terminals.count) 台在线")
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

    // MARK: 详情

    private func terminalDetail(_ t: IKuaiTerminal) -> some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    kv("名称", t.host.isEmpty ? "—" : t.host)
                    kv("IP", t.ip)
                    kv("MAC", t.mac.isEmpty ? "—" : t.mac)
                    kv("在线时长", t.online.isEmpty ? "—" : t.online)
                    kv("连接数", t.connections.isEmpty ? "—" : t.connections)
                    kv("上行", fmt(t.up) + "/s")
                    kv("下行", fmt(t.down) + "/s")
                }
                Section("路由器返回的全部字段") {
                    ForEach(t.raw.keys.sorted(), id: \.self) { k in
                        kv(k, t.raw[k] ?? "")
                    }
                }
            }
            .navigationTitle(t.ip.isEmpty ? "终端" : t.ip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { detail = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(size: 12.5, design: .monospaced)).lineLimit(1)
        }
    }
}
