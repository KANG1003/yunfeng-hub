//
//  BackgroundManager.swift
//  背景管理系统：壁纸 / 模糊 / 色调 / 卡片不透明度
//

import SwiftUI
import UIKit
import Observation

enum WallpaperStyle: String, CaseIterable, Codable, Identifiable {
    case midnight, forest, orchid, ember, ocean, graphite, sapphire, magenta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "午夜蓝"
        case .forest:   return "深林"
        case .orchid:   return "幽兰"
        case .ember:    return "炭火"
        case .ocean:    return "深海"
        case .graphite: return "石墨"
        case .sapphire: return "宝蓝"
        case .magenta:  return "紫红"
        }
    }

    var colors: [Color] {
        switch self {
        case .midnight: return [Color(hex: 0x0D1220), Color(hex: 0x1B2540), Color(hex: 0x2A3D63)]
        case .forest:   return [Color(hex: 0x101A18), Color(hex: 0x12332C), Color(hex: 0x1D5C4A)]
        case .orchid:   return [Color(hex: 0x1A1020), Color(hex: 0x2A1836), Color(hex: 0x4A2A5E)]
        case .ember:    return [Color(hex: 0x20140F), Color(hex: 0x3A2318), Color(hex: 0x6B3D22)]
        case .ocean:    return [Color(hex: 0x0B1420), Color(hex: 0x123049), Color(hex: 0x1A5B7A)]
        case .graphite: return [Color(hex: 0x141414), Color(hex: 0x232323), Color(hex: 0x3A3A3A)]
        case .sapphire: return [Color(hex: 0x0F1A2B), Color(hex: 0x12294A), Color(hex: 0x2B5CA8)]
        case .magenta:  return [Color(hex: 0x1B1024), Color(hex: 0x3A1150), Color(hex: 0x7A1F6B)]
        }
    }

    var view: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [Color.white.opacity(0.10), .clear],
                               center: .topLeading, startRadius: 4, endRadius: 520)
            )
    }
}

@MainActor
@Observable
final class BackgroundManager {

    var style: WallpaperStyle = .midnight { didSet { persist() } }
    var blur: Double = 18 { didSet { persist() } }
    var tint: Double = 1.0 { didSet { persist() } }
    var cardOpacity: Double = 0.08 { didSet { persist() } }
    var imageData: Data? { didSet { persist() } }

    var currentWallpaper: WallpaperStyle { style }

    /// 实际铺在最底层的壁纸：自定义图片优先，支持模糊与色调
    @ViewBuilder
    var wallpaper: some View {
        if let data = imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .blur(radius: blur)
                .overlay(Color.black.opacity(tint * 0.30))
                .clipped()
        } else {
            style.view
                .overlay(Color.black.opacity(tint * 0.08))
        }
    }

    private let key = "bg-settings"
    private let imagePath: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("custom-wallpaper.jpg")
    }()

    init() {
        load()
        if let data = try? Data(contentsOf: imagePath) { imageData = data }
    }

    var glassFill: Color {
        Color.white.opacity(cardOpacity)
    }

    // 供卡片统一使用的样式
    var cardMaterial: some ShapeStyle {
        .ultraThinMaterial
    }

    struct Settings: Codable {
        var style: WallpaperStyle
        var blur: Double
        var tint: Double
        var opacity: Double
    }

    func persist() {
        let s = Settings(style: style, blur: blur, tint: tint, opacity: cardOpacity)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if let imageData {
            try? imageData.write(to: imagePath, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: imagePath)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return }
        style = s.style; blur = s.blur; tint = s.tint; cardOpacity = s.opacity
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
