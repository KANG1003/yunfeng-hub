//
//  NavigationHomeView.swift
//  Sun-Panel 导航页（内嵌 WebView + 快捷卡片）
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url {
            web.load(URLRequest(url: url))
        }
    }
}

struct NavigationHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showPanel = false
    @State private var showAdd = false
    @State private var showBackground = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newURL = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("导航").font(.system(size: 27, weight: .bold))
                    Text("Sun-Panel 快捷入口 · 内网设备").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 17))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sun-Panel 主页").font(.system(size: 14, weight: .semibold))
                            Text(store.sunPanelURL).font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PrimaryButton(title: "打开") { showPanel = true }
                            .frame(width: 88)
                    }
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.navItems) { item in
                        Button {
                            open(item)
                        } label: {
                            GlassCard(padding: 14) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 17))
                                            .frame(width: 38, height: 38)
                                            .background(Color.white.opacity(0.12),
                                                        in: RoundedRectangle(cornerRadius: 12))
                                        Spacer()
                                        StatusDot(on: item.isOnline)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.system(size: 14, weight: .semibold))
                                        Text(item.host).font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                GlassCard {
                    SectionTitle(text: "服务状态")
                    VStack(spacing: 0) {
                        ForEach(store.navItems) { item in
                            HStack {
                                Text(item.name).font(.system(size: 13))
                                Spacer()
                                StatusDot(on: item.isOnline, warn: !item.isOnline)
                            }
                            .padding(.vertical, 8)
                            Divider().opacity(0.3)
                        }
                    }
                }

                GhostButton(title: "添加导航项", systemImage: "plus") { showAdd = true }
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
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
        .sheet(isPresented: $showPanel) {
            NavigationStack {
                Group {
                    if let url = URL(string: store.sunPanelURL) {
                        WebView(url: url).ignoresSafeArea()
                    } else {
                        Text("地址无效").foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Sun-Panel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { showPanel = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("名称", text: $newName)
                    TextField("显示地址", text: $newHost)
                    TextField("URL", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                .navigationTitle("新增导航")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.addNav(name: newName.isEmpty ? "新入口" : newName,
                                         host: newHost, url: newURL)
                            newName = ""; newHost = ""; newURL = ""
                            showAdd = false
                        }
                        .disabled(newURL.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func open(_ item: NavItem) {
        guard let url = URL(string: item.url) else { return }
        UIApplication.shared.open(url)
    }
}
