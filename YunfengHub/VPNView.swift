//
//  VPNView.swift
//  WireGuard 配置管理：不在本机建隧道，把配置交给官方 WireGuard App
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VPNView: View {
    @Environment(AppStore.self) private var store

    @State private var selectedID: UUID?
    @State private var exportURL: URL?
    @State private var showPasteSheet = false
    @State private var showImporter = false
    @State private var pasteText = ""
    @State private var pasteName = "家 · 内网"
    @State private var toast: String?

    private var profile: WGProfile? {
        store.profiles.first { $0.id == selectedID } ?? store.profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                header

                howToCard

                if store.profiles.isEmpty {
                    GlassCard {
                        Text("还没有配置，点下面「粘贴 .conf」或「从文件导入」加一个。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                } else {
                    profileCard
                    detailCard
                    actionCard
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if selectedID == nil { selectedID = store.profiles.first?.id }
            rebuildExport()
        }
        .onChange(of: selectedID) { _, _ in rebuildExport() }
        .onChange(of: store.profiles) { _, _ in rebuildExport() }
        .sheet(isPresented: $showPasteSheet) { pasteSheet }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "conf") ?? .item]) { result in
            importFile(result)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WireGuard").font(.system(size: 27, weight: .bold))
            Text("配置管理 · 隧道交给官方 App")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var howToCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("两步就能连")
                    .font(.system(size: 13.5, weight: .semibold))
                stepRow("1", "粘贴或导入你的 .conf（含私钥）")
                stepRow("2", "点「分享到 WireGuard」，在分享面板里选 WireGuard 即完成导入")
                Text("iOS 要让第三方 App 自己建隧道，需要付费开发者账号 + NetworkExtension，本 App 不做这部分；官方 WireGuard App 免费且支持按需连接，更稳。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(n)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Color.blue.opacity(0.25), in: Circle())
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: 配置列表

    private var profileCard: some View {
        GlassCard {
            Text("配置").font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.profiles) { p in
                        Chip(title: p.name, selected: p.id == profile?.id) {
                            selectedID = p.id
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let profile, profile.isComplete {
                Text("密钥已就绪，可直接导出")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.green)
                    .padding(.top, 10)
            } else {
                Text("这份只有地址信息，缺密钥，导出会被拦下")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.orange)
                    .padding(.top, 10)
            }
        }
    }

    private var detailCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                infoRow("配置", profile?.name ?? "—")
                Divider().opacity(0.25)
                infoRow("Endpoint", profile?.endpoint ?? "—", mono: true)
                Divider().opacity(0.25)
                infoRow("本机地址", profile?.address ?? "—", mono: true)
                Divider().opacity(0.25)
                infoRow("Allowed IPs", profile?.allowedIPs ?? "—", mono: true)
                Divider().opacity(0.25)
                infoRow("MTU", "\(profile?.mtu ?? 1400)", mono: true)
                Divider().opacity(0.25)
                infoRow("私钥", WGConfig.mask(profile?.privateKey ?? ""), mono: true)
                Divider().opacity(0.25)
                infoRow("对端公钥", WGConfig.mask(profile?.publicKey ?? ""), mono: true)
            }
        }
    }

    // MARK: 操作

    private var actionCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                if let exportURL, profile?.isComplete == true {
                    ShareLink(item: exportURL,
                              preview: SharePreview("\(profile?.name ?? "yunfeng").conf")) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享到 WireGuard")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x4D8DFF), Color(hex: 0x7A6BFF)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                } else {
                    Text("先导入带密钥的 .conf，才能分享")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 8) {
                    GhostButton(title: "粘贴 .conf", systemImage: "doc.on.clipboard") {
                        showPasteSheet = true
                    }
                    GhostButton(title: "从文件导入", systemImage: "folder") {
                        showImporter = true
                    }
                }

                HStack(spacing: 8) {
                    GhostButton(title: "复制文本", systemImage: "doc.on.doc") {
                        copyText()
                    }
                    GhostButton(title: "官方 App", systemImage: "arrow.up.right.square") {
                        openWireGuardOnAppStore()
                    }
                }

                if let profile, store.profiles.count > 1 {
                    Button(role: .destructive) {
                        store.deleteProfile(profile)
                        selectedID = store.profiles.first?.id
                    } label: {
                        Text("删除这份配置")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: 粘贴导入

    private var pasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("配置名称", text: $pasteName)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $pasteText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if pasteText.isEmpty {
                            Text("[Interface]\nPrivateKey = …\nAddress = …\n[Peer]\nPublicKey = …\nEndpoint = …")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxHeight: .infinity)

                Text("整段粘贴 .conf 原文，自动解析出 Endpoint / 密钥 / MTU。")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(18)
            .navigationTitle("粘贴配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPasteSheet = false; pasteText = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        savePasted()
                    }
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: 逻辑

    private func savePasted() {
        let name = pasteName.isEmpty ? "新配置" : pasteName
        guard let p = WGConfig.parse(pasteText, name: name) else {
            toast = "没解析出 Endpoint，检查下内容"
            return
        }
        store.addProfile(p)
        selectedID = p.id
        showPasteSheet = false
        pasteText = ""
        toast = "已保存 \(p.name)"
        hideToastLater()
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            toast = "读取失败"
            hideToastLater()
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let p = WGConfig.parse(text, name: url.deletingPathExtension().lastPathComponent) else {
            toast = "不是有效的 .conf"
            hideToastLater()
            return
        }
        store.addProfile(p)
        selectedID = p.id
        toast = "已导入 \(p.name)"
        hideToastLater()
    }

    private func rebuildExport() {
        guard let profile, profile.isComplete else {
            exportURL = nil
            return
        }
        let name = profile.name.replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).conf")
        do {
            try WGConfig.render(profile).write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func copyText() {
        guard let profile else { return }
        UIPasteboard.general.string = WGConfig.render(profile)
        toast = profile.isComplete ? "已复制，可直接粘到 WireGuard App" : "地址信息已复制（缺密钥）"
        hideToastLater()
    }

    private func openWireGuardOnAppStore() {
        let s = "https://apps.apple.com/cn/app/wireguard/id1441195209"
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }

    private func hideToastLater() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }

    private func infoRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .font(.system(size: mono ? 12 : 13, design: mono ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 8)
    }
}
