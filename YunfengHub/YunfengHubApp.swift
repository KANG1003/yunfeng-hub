//
//  YunfengHubApp.swift
//  yunfeng
//
//  入口 + 根视图（底部 5 个 Tab）
//

import SwiftUI

@main
struct YunfengHubApp: App {
    @State private var store = AppStore()
    @State private var bg = BackgroundManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(bg)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(BackgroundManager.self) private var bg

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
                    VPNView()
                }
                .tabItem { Label("VPN", systemImage: "shield.lefthalf.filled") }

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
    }
}
