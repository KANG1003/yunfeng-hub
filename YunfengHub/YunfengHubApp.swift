//
//  YunfengHubApp.swift
//  云峰工作台
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
                NavigationHomeView()
                    .tabItem { Label("导航", systemImage: "safari") }

                VPNView()
                    .tabItem { Label("VPN", systemImage: "shield.lefthalf.filled") }

                DailyReportView()
                    .tabItem { Label("日报", systemImage: "square.and.pencil") }

                WeeklyView()
                    .tabItem { Label("weekiy", systemImage: "chart.bar.xaxis") }

                BackgroundSettingsView()
                    .tabItem { Label("背景", systemImage: "paintpalette") }
            }
            .tint(.blue)
        }
    }
}
