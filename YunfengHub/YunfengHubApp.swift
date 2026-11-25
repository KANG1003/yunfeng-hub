//
//  YunfengHubApp.swift
//  YUNFENG
//
//  入口 + 根视图（底部 5 个 Tab）
//

import SwiftUI

@main
struct YunfengHubApp: App {
    @State private var store = AppStore()
    @State private var bg = BackgroundManager()
    @State private var net = NetworkEnv()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(bg)
                .environment(net)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(BackgroundManager.self) private var bg
    @Environment(NetworkEnv.self) private var net
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            bg.wallpaper
                .ignoresSafeArea()

            TabView {
                NavigationStack {
                    NavigationHomeView()
                }
                .tabItem { Label("导航", systemImage: "safari") }

                NavigationStack {
                    TerminalView()
                }
                .tabItem { Label("终端", systemImage: "wifi.router") }

                NavigationStack {
                    WebPanelView(title: "备件系统",
                                 subtitle: "bj.kangkang.me",
                                 urlString: "http://bj.kangkang.me/login.php")
                }
                .tabItem { Label("备件", systemImage: "shippingbox") }

                NavigationStack {
                    WebPanelView(title: "写日报",
                                 subtitle: "rb.kangkang.me",
                                 urlString: "http://rb.kangkang.me/login.php")
                }
                .tabItem { Label("日报", systemImage: "square.and.pencil") }

                NavigationStack {
                    WebPanelView(title: "仪电周结",
                                 subtitle: "we.kangkang.me",
                                 urlString: "http://we.kangkang.me/index.php")
                }
                .tabItem { Label("周结", systemImage: "calendar") }
            }
            .tint(.blue)
        }
        .onAppear { net.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { net.refresh() }
        }
        .onOpenURL { url in handleOpenURL(url) }
    }

    /// 支持「在 YUNFENG 中打开 .conf」：从文件 App / 分享面板把配置送进来
    private func handleOpenURL(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let p = WGConfig.parse(text, name: url.deletingPathExtension().lastPathComponent)
        else { return }
        store.addProfile(p)
    }
}
