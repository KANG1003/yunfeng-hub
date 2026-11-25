//
//  NavigationHomeView.swift
//  导航页：内外网合并卡片，按网络环境自动切换地址
//

import SwiftUI
import UIKit
import WebKit

struct NavigationHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(NetworkEnv.self) private var net

    @State private var opened: NavItem?
    @State private var showAdd = false
    @State private var showBackground = false
    @State private var showVPN = false
    @State private var newName = ""
    @State private var newLAN = ""
    @State private var newWAN = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                topBar

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.navItems) { item in
                        card(item)
                    }
                    addTile
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showBackground = true } label: {
                    Image(systemName: "paintpalette")
                }
            }
        }
        .sheet(item: $opened) { item in
            NavigationStack {
                WebPanelView(title: item.name,
                             subtitle: item.displayHost(onLAN: net.activeOnLAN),
                             urlString: item.url(onLAN: net.activeOnLAN)?.absoluteString ?? "",
                             dismissible: true)
            }
        }
        .sheet(isPresented: $showBackground) {
            NavigationStack {
                BackgroundSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showBackground = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(isPresented: $showVPN) {
            NavigationStack {
                VPNView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { showVPN = false }
                        }
                    }
            }
        }
    }

    // MARK: 顶栏：网络模式 + 数量

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { net.cycleMode() }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(net.activeOnLAN ? Color.green : Color.blue)
                        .frame(width: 7, height: 7)
                    Text(net.statusText)
                        .font(.system(size: 12.5, weight: .medium))
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(store.navItems.count) 个入口")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Button { showVPN = true } label: {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12.5))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    // MARK: 卡片

    private func card(_ item: NavItem) -> some View {
        let onLAN = net.activeOnLAN
        let usingLAN = onLAN && item.hasLAN

        return Button {
            opened = item
        } label: {
            GlassCard(padding: 13) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Spacer()
                        Text(usingLAN ? "内网" : "外网")
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((usingLAN ? Color.green : Color.blue).opacity(0.18), in: Capsule())
                            .foregroundStyle(usingLAN ? Color.green : Color(hex: 0xA8C6FF))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        Text(item.displayHost(onLAN: onLAN))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if let url = item.url(onLAN: onLAN) { UIApplication.shared.open(url) }
            } label: {
                Label("用 Safari 打开", systemImage: "safari")
            }
            Button(role: .destructive) {
                store.deleteNav(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var addTile: some View {
        Button { showAdd = true } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                Text("添加入口").font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: 新增

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如 备件管理", text: $newName)
                }
                Section {
                    TextField("http://192.168.10.x:端口", text: $newLAN)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("内网地址（可留空）")
                }
                Section {
                    TextField("http://xxx.kangkang.me", text: $newWAN)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("外网地址（可留空）")
                }
                Section {
                    Text("两个都填：在家自动走内网，出门自动走外网。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新增入口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { resetForm() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addNav(name: newName.trimmed.isEmpty ? "新入口" : newName.trimmed,
                                     lanURL: newLAN.trimmed, wanURL: newWAN.trimmed)
                        resetForm()
                    }
                    .disabled(newLAN.trimmed.isEmpty && newWAN.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func resetForm() {
        newName = ""; newLAN = ""; newWAN = ""
        showAdd = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
