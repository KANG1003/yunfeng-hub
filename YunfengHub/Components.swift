//
//  Components.swift
//  通用卡片 / 标签 / 按钮样式
//

import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(BackgroundManager.self) private var bg
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(bg.cardOpacity))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(text).font(.system(size: 14, weight: .semibold))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 4)
    }
}

struct StatusDot: View {
    let on: Bool
    var warn: Bool = false
    var body: some View {
        Circle()
            .fill(on ? (warn ? Color.orange : Color.green) : Color.gray.opacity(0.5))
            .frame(width: 8, height: 8)
            .shadow(color: on ? (warn ? .orange : .green).opacity(0.7) : .clear, radius: 4)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Color.blue.opacity(0.22) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.blue.opacity(0.5) : Color.white.opacity(0.16),
                                           lineWidth: 1)
                )
                .foregroundStyle(selected ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
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
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
