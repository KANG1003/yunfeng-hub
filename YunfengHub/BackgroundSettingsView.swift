//
//  BackgroundSettingsView.swift
//  背景管理：壁纸 / 模糊 / 色调 / 卡片不透明度 / 自定义图片
//

import SwiftUI
import PhotosUI

struct BackgroundSettingsView: View {
    @Environment(BackgroundManager.self) private var bg
    @State private var pickerItem: PhotosPickerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        @Bindable var bg = bg

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("背景管理").font(.system(size: 27, weight: .bold))
                    Text("壁纸 / 模糊 / 色调，实时预览").font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                GlassCard {
                    Text("壁纸").font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.bottom, 10)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(WallpaperStyle.allCases) { style in
                            Button { bg.style = style } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(LinearGradient(colors: style.colors,
                                                             startPoint: .topLeading,
                                                             endPoint: .bottomTrailing))
                                        .frame(height: 64)
                                    if bg.style == style {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 3)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(bg.style == style ? Color.white.opacity(0.6)
                                                                        : Color.white.opacity(0.14),
                                                      lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                            Text("用相册图片做壁纸")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .padding(.top, 12)
                }

                GlassCard {
                    sliderRow(title: "模糊强度", value: $bg.blur, range: 0...40, display: Int(bg.blur))
                    Divider().opacity(0.25).padding(.vertical, 6)
                    sliderRow(title: "色调强度", value: $bg.tint, range: 0...1.5, display: Int(bg.tint * 100))
                    Divider().opacity(0.25).padding(.vertical, 6)
                    sliderRow(title: "卡片不透明度", value: $bg.cardOpacity,
                              range: 0.02...0.3, display: Int(bg.cardOpacity * 100))
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("跟随系统深色模式").font(.system(size: 13.5, weight: .semibold))
                            Text("夜间自动切换低亮度壁纸").font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: .constant(true)).labelsHidden()
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    bg.imageData = data
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, display: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text("\(display)").font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).tint(.blue)
        }
    }
}
